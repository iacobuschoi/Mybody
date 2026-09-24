/* =============================================================================
 * engine.js — 플래닝 엔진
 *
 * 핵심 설계:
 *  - 강도(상/중/하)는 난이도 라벨이 아니라 "얼마나 빨리 갈 것인가" = 기간이다.
 *  - 기간은 나눗셈 한 방이 아니라 주차별 시뮬레이션으로 구한다.
 *    (체중이 줄면 TDEE가 줄고, 체지방이 줄면 동원 가능한 에너지 상한도 줄기 때문)
 *  - 근성장 속도는 생리적 상한이 있고, 적자가 클수록 더 떨어진다.
 *    그래서 "빨리 깎으면 근육 목표는 오히려 늦어지는" 역설이 실제로 발생한다.
 *    엔진은 이걸 숨기지 않고 전략 비교(동시진행 vs 분할)로 노출한다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KCAL_PER_KG_FAT = 7700;   // 지방 1kg당 에너지
  var MAX_WEEKS = 208;          // 시뮬레이션 상한 (4년)

  var PAL = {
    sedentary:  { mult: 1.20, label: '좌식 (거의 앉아서 생활)' },
    light:      { mult: 1.375, label: '가벼움 (주 1~3회 운동)' },
    moderate:   { mult: 1.55, label: '보통 (주 3~5회 운동)' },
    active:     { mult: 1.725, label: '활동적 (주 6~7회 운동)' },
    veryActive: { mult: 1.90, label: '매우 활동적 (육체노동/2회 운동)' }
  };

  /* 훈련연령별 최대 제지방 증가율 (%FFM/월, 남성 기준 · 중앙값)
   *
   * 기준을 체중에서 제지방으로 바꿨습니다. 체중 기준이면 같은 훈련연령에서
   * 비만 입문자가 마른 입문자보다 52% 빨리 근육이 붙는다는 역설이 생깁니다 —
   * 지방은 근육을 만들지 않습니다.
   * 값은 기준 조성 0.80(추정치)으로 재앵커한 ×1.15 입니다.
   * 논문 22개군 대조에서 전체 제지방 MAE 2.83 → 2.21. */
  var MUSCLE_BASE = {
    novice:       { pct: 1.44, label: '입문 (6개월 미만)' },
    intermediate: { pct: 0.86, label: '중급 (6개월~3년)' },
    advanced:     { pct: 0.43, label: '숙련 (3년 이상)' },
    elite:        { pct: 0.20, label: '상급 정체기 (5년+)' }
  };

  // 칼로리 수지 상황별 근성장 배율
  var MUSCLE_SITUATION = {
    surplus:  { novice: 1.00, intermediate: 1.00, advanced: 1.00, elite: 1.00 },
    maintain: { novice: 0.50, intermediate: 0.50, advanced: 0.50, elite: 0.50 },
    recomp:   { novice: 0.70, intermediate: 0.35, advanced: 0.15, elite: 0.10 }, // 적자 ≤15%
    cut:      { novice: 0.30, intermediate: 0.05, advanced: 0.00, elite: 0.00 }  // 적자 >15%
  };

  /* 강도는 이제 이산 3단계가 아니라 연속 변수 a ∈ [0,1] 이다.
   * a=0  : 가장 여유로운(느린) 계획   a=1 : 가장 공격적인(빠른) 계획
   * 상/중/하는 "a값 3개"가 아니라 "기간 3개"이고, 각 기간에 필요한 a를 역산한다. */
  var CUT_RANGE = {
    ratePct:       [0.0015, 0.0090],  // 주당 체중 변화율 (%BW)
    deficitPct:    [0.050,  0.275],   // TDEE 대비 적자
    proteinPerFFM: [2.0,    3.1],     // g/kg FFM — Helms·Zinn 2014 의 2.3~3.1 상단까지 연다
    fatPerKg:      [0.95,   0.60],    // g/kg BW
    days:          [3,      6],
    sessionMin:    [40,     85],
    cardioMin:     [60,     240],
    setsPerMuscle: [8,      20],
    deloadEvery:   [10,     4]
  };
  var BULK_RANGE = {
    surplusPct:    [0.040,  0.175],
    leanFraction:  [0.75,   0.40],    // 늘어난 체중 중 제지방 비율
    proteinPerFFM: [1.9,    2.2],
    fatPctKcal:    [0.30,   0.22],
    days:          [3,      6],
    sessionMin:    [45,     80],
    cardioMin:     [90,     75],
    setsPerMuscle: [10,     22],
    deloadEvery:   [10,     4]
  };

  function lerp(range, a) { return range[0] + (range[1] - range[0]) * a; }

  /**
   * @param a       공격성 0..1
   * @param mode    'cut' | 'bulk'
   * @param con     선택된 몸만들기 모드의 제약 {aMin,aMax,proteinPerFfmMin,proteinPerFfmMax} | null
   */
  function paramsAt(a, mode, con) {
    a = Math.max(0, Math.min(1, a));
    var R = mode === 'bulk' ? BULK_RANGE : CUT_RANGE;
    var p = { a: a, mode: mode };
    Object.keys(R).forEach(function (k) {
      var v = lerp(R[k], a);
      p[k] = (k === 'days' || k === 'sessionMin' || k === 'cardioMin' ||
              k === 'setsPerMuscle' || k === 'deloadEvery') ? Math.round(v) : v;
    });
    p.difficulty = a < 0.34 ? 1 : (a < 0.7 ? 2 : 3);
    p.difficultyLabel = ['', '★☆☆ 낮음', '★★☆ 보통', '★★★ 높음'][p.difficulty];
    p.cheatMealsPerWeek = a < 0.34 ? 2 : (a < 0.7 ? 1 : 0);
    p.tracking = a < 0.34 ? '단백질만 대충 기록'
               : (a < 0.7 ? '칼로리 + 단백질 기록' : '4대 매크로 전부 + 주 4회 체중');
    // 감량에서 공격적인 구간은 연속 지속 한계가 있다
    p.maxContinuousWeeks = mode === 'cut' ? (a >= 0.7 ? 12 : (a >= 0.45 ? 20 : 24)) : null;
    p.muscleLossRisk = mode === 'cut'
      ? (a >= 0.7 ? '중간~높음' : (a >= 0.45 ? '낮음' : '매우 낮음'))
      : '해당 없음';
    // 모드가 단백질 하한·상한을 따로 정하면 그 범위 안에서 다시 보간한다
    if (con && con.proteinPerFfmMin != null && con.proteinPerFfmMax != null) {
      var span = (con.aMax != null && con.aMax > con.aMin) ? (con.aMax - con.aMin) : 1;
      var t = Math.max(0, Math.min(1, (a - (con.aMin || 0)) / span));
      p.proteinPerFFM = con.proteinPerFfmMin + (con.proteinPerFfmMax - con.proteinPerFfmMin) * t;
    }
    return p;
  }

  // 상/중/하 = 기간 배수. 상은 엔진이 찾은 최단, 중/하는 그 배수만큼 여유롭게.
  var LEVEL_SPEC = [
    { key: 'high', label: '상', title: '최단',   durationMult: 1.0,
      blurb: '가능한 가장 빠르게. 식단 제약이 가장 빡빡합니다.' },
    { key: 'mid',  label: '중', title: '표준',   durationMult: 1.4,
      blurb: '여유를 조금 두고. 근육 보존과 지속성의 균형점입니다.' },
    { key: 'low',  label: '하', title: '여유',   durationMult: 2.0,
      blurb: '생활을 크게 바꾸지 않고. 중도 포기 확률이 가장 낮습니다.' }
  ];

  /* ---------------------------------------------------------------------- */
  /* 1. 파생값                                                                */
  /* ---------------------------------------------------------------------- */

  /**
   * 물리적으로 불가능한 스캔을 걸러냅니다.
   *
   * 이게 없어서 {weightKg:70, bfmKg:90} 이 조용히 통과했고,
   * 제지방 -20kg · 체지방률 128.6% · BMR -62kcal 짜리 계획이 나왔습니다.
   * OCR 이 근육/지방 칸을 바꿔 읽으면 k=1.2 로 통과하기도 했습니다.
   *
   * modes.js A절이 "k가 0.40~0.60 범위를 벗어나면 입력 오류로 안내합니다"를
   * 이미 문장으로 명시하고 있는데 구현이 없었습니다.
   *
   * @returns null 이면 정상, 아니면 { invalid: [문제 필드들], reasons: [사람이 읽는 설명] }
   */
  function validateScan(scan, prevScan) {
    if (!scan) return { invalid: ['스캔'], reasons: ['측정 기록이 없습니다.'] };
    var bad = [], why = [];
    var w = scan.weightKg;
    var b = scan.bfmKg != null ? scan.bfmKg : (w != null && scan.pbfPct != null ? w * scan.pbfPct / 100 : null);
    var smm = scan.smmKg;

    if (!(w >= 25 && w <= 300)) { bad.push('체중'); why.push('체중이 25~300kg 범위를 벗어났습니다.'); }
    if (b == null || !(b >= 0)) { bad.push('체지방량'); why.push('체지방량을 읽지 못했습니다.'); }
    else if (w >= 25 && b > 0.65 * w) {
      bad.push('체지방량');
      why.push('체지방량이 체중의 65%를 넘습니다. 체중과 체지방 칸이 바뀌지 않았는지 확인해 주세요.');
    }

    var ffm = (w != null && b != null) ? w - b : null;
    if (ffm != null && !(ffm > 0)) { bad.push('제지방량'); why.push('체지방량이 체중보다 큽니다.'); }

    if (smm == null || !(smm >= 0)) { bad.push('골격근량'); why.push('골격근량을 읽지 못했습니다.'); }
    else if (ffm != null && ffm > 0) {
      var k = smm / ffm;
      if (k < 0.35 || k > 0.65) {
        bad.push('골격근량');
        why.push('골격근량이 제지방량의 ' + Math.round(k * 100) + '% 입니다. 보통 40~60% 입니다 — ' +
                 '근육과 지방 칸이 바뀌지 않았는지 확인해 주세요.');
      }
    }
    /* 골격근량은 결과지 안에 짝이 없습니다.
     *
     * 다른 값들은 서로 검산됩니다 — 제지방 = 체중 − 체지방, 체지방률 =
     * 체지방/체중 같은 식으로요. 골격근량만 홀로 서 있어서, 한 자리를
     * 잘못 읽어도 아무 등식이 깨지지 않습니다.
     *
     * 실측 확인: 체중 86.7 · 체지방 20.0 을 고정하고 골격근량을 훑으면
     * 23.4~43.3kg 이 전부 통과합니다(폭 19.9kg). 그 구간 안에서
     * 31kg 이면 목표일이 2029-08, 40kg 이면 2027-03 — 2년 4개월 차이인데
     * 경고가 한 줄도 없었습니다.
     *
     * 그런데 k = 골격근/제지방 은 한 사람 안에서 아주 안정적입니다.
     * 주인 실측 3회에서 0.56829 / 0.56753 / 0.56822 (폭 0.00076)이고,
     * 직전 k 로 다음 측정을 예측한 오차가 62일 간격에도 0.05kg —
     * 측정 노이즈(0.6kg)의 1/12 입니다.
     *
     * 그래서 이전 측정이 있으면 그걸로 예측해서 대조합니다.
     * 허용치는 넉넉하게 둡니다 — 잡으려는 것은 미세한 편차가 아니라
     * 자릿수·자리바꿈 같은 판독 오류입니다. */
    if (prevScan && w > 0 && b != null && smm > 0) {
      var pw = prevScan.weightKg;
      var pb = prevScan.bfmKg != null ? prevScan.bfmKg
             : (pw != null && prevScan.pbfPct != null ? pw * prevScan.pbfPct / 100 : null);
      var pffm = prevScan.ffmKg != null ? prevScan.ffmKg
               : (pw != null && pb != null ? pw - pb : null);
      var ffmNow = w - b;
      if (pffm > 0 && prevScan.smmKg > 0 && ffmNow > 0) {
        var kPrev = prevScan.smmKg / pffm;
        var expect = kPrev * ffmNow;
        var gapDays = Math.abs(Date.parse(scan.measuredAt) - Date.parse(prevScan.measuredAt)) / 86400000;
        if (isFinite(gapDays)) {
          // 기본 1.2kg + 한 달마다 0.25kg. k 는 훈련으로 아주 천천히 오릅니다.
          var tol = Math.min(3.0, 1.2 + (gapDays / 30) * 0.25);
          if (Math.abs(smm - expect) > tol) {
            bad.push('골격근량');
            why.push('이전 측정으로 보면 골격근량이 ' + (Math.round(expect * 10) / 10) +
                     'kg 근처여야 하는데 ' + smm + 'kg 입니다. ' +
                     '자릿수나 자리를 잘못 읽지 않았는지 확인해 주세요.');
          }
        }
      }
    }

    if (!bad.length) return null;
    // 같은 필드가 여러 번 들어갈 수 있으니 정리합니다
    var seen = {}, uniq = [];
    bad.forEach(function (x) { if (!seen[x]) { seen[x] = 1; uniq.push(x); } });
    return { invalid: uniq, reasons: why };
  }

  function derive(scan, profile) {
    var w = scan.weightKg;
    var bfm = scan.bfmKg != null ? scan.bfmKg : (w * (scan.pbfPct / 100));
    var ffm = scan.ffmKg != null ? scan.ffmKg : (w - bfm);
    var smm = scan.smmKg;
    var h = profile.heightCm / 100;
    // 인바디 BMR은 Katch-McArdle과 사실상 동일(검증됨) → 있으면 그대로 신뢰
    var bmrKatch = 370 + 21.6 * ffm;
    var bmrMifflin = profile.sex === 'male'
      ? (10 * w + 6.25 * profile.heightCm - 5 * profile.age + 5)
      : (10 * w + 6.25 * profile.heightCm - 5 * profile.age - 161);
    var bmr = scan.bmrKcal || bmrKatch;
    var pal = (PAL[profile.activityLevel] || PAL.moderate).mult;

    return {
      weightKg: r1(w),
      smmKg: r1(smm),
      bfmKg: r1(bfm),
      ffmKg: r1(ffm),
      pbfPct: r1(bfm / w * 100),
      bmi: r1(w / (h * h)),
      smmToFfm: smm / ffm,            // 개인별 SMM/FFM 비율 (오너는 ≈0.568)
      bmrKcal: Math.round(bmr),
      bmrKatch: Math.round(bmrKatch),
      bmrMifflin: Math.round(bmrMifflin),
      bmrSource: scan.bmrKcal ? 'InBody 인쇄값' : 'Katch-McArdle 계산값',
      pal: pal,
      tdeeKcal: Math.round(bmr * pal)
    };
  }

  /* ---------------------------------------------------------------------- */
  /* 2. 목표 분류 + 정합성                                                    */
  /* ---------------------------------------------------------------------- */

  function classifyGoal(cur, goal) {
    var dW = goal.weightKg - cur.weightKg;
    var dSMM = goal.smmKg - cur.smmKg;
    var dBFM = goal.bfmKg - cur.bfmKg;

    // 체중 = 제지방 + 체지방. 사용자가 세 값을 다 입력하면 과결정(over-determined)이라
    // 서로 안 맞을 수 있다. 얼마나 안 맞는지 계산해서 UI가 알려준다.
    var impliedFfm = goal.smmKg / cur.smmToFfm;
    var impliedWeight = impliedFfm + goal.bfmKg;
    var mismatchKg = goal.weightKg - impliedWeight;

    // 측정 노이즈 바닥. modes.js 가 있으면 거기 값을 쓴다 (인바디 실사용 변동 기준).
    var NF = global.MB_MODES ? global.MB_MODES.NOISE : { weight: 1.0, smm: 0.6, bfm: 1.0 };
    var wantsFatLoss = dBFM < -NF.bfm;
    var wantsFatGain = dBFM > NF.bfm;
    var wantsMuscle  = dSMM > NF.smm;
    var losesMuscle  = dSMM < -NF.smm;

    var type, typeLabel;
    if (wantsFatLoss && wantsMuscle)      { type = 'recomp';   typeLabel = '리컴프 (지방↓ + 근육↑ 동시)'; }
    else if (wantsFatLoss)                { type = 'cut';      typeLabel = '감량'; }
    else if (wantsMuscle && !wantsFatLoss){ type = 'bulk';     typeLabel = '증량'; }
    else if (wantsFatGain && losesMuscle) { type = 'contrary'; typeLabel = '방향이 반대인 목표'; }
    else                                  { type = 'maintain'; typeLabel = '유지'; }

    return {
      type: type, typeLabel: typeLabel,
      dWeightKg: r1(dW), dSmmKg: r1(dSMM), dBfmKg: r1(dBFM),
      targetPbfPct: r1(goal.bfmKg / goal.weightKg * 100),
      impliedWeightKg: r1(impliedWeight),
      mismatchKg: r1(mismatchKg),
      isConsistent: Math.abs(mismatchKg) <= 1.0,
      noise: NF,
      subNoise: {
        weight: Math.abs(dW) < NF.weight,
        smm: Math.abs(dSMM) < NF.smm,
        bfm: Math.abs(dBFM) < NF.bfm
      }
    };
  }

  /* ---------------------------------------------------------------------- */
  /* 3. 속도 모델                                                             */
  /* ---------------------------------------------------------------------- */

  /**
   * 운동 처방은 식단 공격성(a)이 아니라 "사용자가 낼 수 있는 시간"과 "목표"가 결정한다.
   * 식단을 여유롭게 간다고 운동까지 줄일 이유는 없다 — 오히려 근육 목표가 있으면
   * 볼륨은 지켜야 한다. a가 건드리는 건 유산소 분량과 세션 길이의 미세 조정뿐이다.
   */
  function resolveTraining(profile, params, goalInfo) {
    var days = Math.min(6, Math.max(3, profile.daysPerWeek || params.days));
    var sessionMin = profile.sessionMinutes || params.sessionMin;
    var sets = params.setsPerMuscle;
    var reason = [];
    if (goalInfo && goalInfo.dSmmKg > 0.3) {
      // 근육 증가가 목표면 주당 세트 수를 성장 구간(12~20)으로 끌어올린다
      sets = Math.max(sets, 12);
      reason.push('근육 증가가 목표라 근육군당 주 ' + sets + '세트를 유지합니다');
    }
    if (goalInfo && goalInfo.dBfmKg < -0.3) {
      reason.push('감량 중에는 볼륨을 유지하는 것이 근손실을 막는 가장 강력한 수단입니다');
    }
    // 유산소만 강도를 따라간다 (적자를 칼로리로만 만들지 않기 위해)
    var cardioMin = params.cardioMin;
    return { days: days, sessionMin: sessionMin, setsPerMuscle: sets,
             cardioMin: cardioMin, reason: reason };
  }

  /* --- 제지방량 천장 -------------------------------------------------------
   * 근성장은 속도만 제한하면 안 된다. 절대 상한도 있어야 한다.
   * 제지방량지수 FFMI = 제지방량(kg) / 키(m)^2 로, 약물을 쓰지 않은 사람의
   * 상한이 대략 25 근처로 보고돼 있다 (Kouri 1995, 남성 보디빌더 조사).
   * 이게 없으면 시뮬레이션에서 제지방 134kg 같은 값이 나온다 — 실제로 나왔다.
   * -------------------------------------------------------------------- */
  function ffmiOf(ffmKg, heightCm) {
    var h = (heightCm || 175) / 100;
    return ffmKg / (h * h);
  }
  function ffmiCeiling(sex) { return sex === 'female' ? 22.0 : 25.0; }

  /** 천장에 가까울수록 성장률이 0으로 수렴한다 (절벽이 아니라 경사) */
  function ffmiFactor(ffmKg, profile) {
    var ceil = ffmiCeiling(profile.sex);
    var cur = ffmiOf(ffmKg, profile.heightCm);
    var taper = ceil - 2.0;
    if (cur <= taper) return 1;
    if (cur >= ceil) return 0;
    return (ceil - cur) / (ceil - taper);
  }

  function ageFactor(age) {
    if (age >= 50) return 0.65;
    if (age >= 40) return 0.80;
    if (age < 18)  return 0.90;
    return 1.00;
  }

  // 주당 SMM 증가 상한 (kg/주) — 최적 조건에서의 생리적 천장
  function baseSmmRatePerWeek(weightKg, profile, smmToFfm, ffmKg, weekIndex) {
    var base = (MUSCLE_BASE[profile.trainingAge] || MUSCLE_BASE.intermediate).pct;
    var sexFactor = profile.sex === 'male' ? 1.0 : 0.5;
    // 체중이 아니라 제지방 기준입니다 (MUSCLE_BASE 주석 참조).
    var anchor = ffmKg != null ? ffmKg : weightKg * 0.80;
    var ffmPerMonth = anchor * (base / 100) * sexFactor;
    var smmPerMonth = ffmPerMonth * smmToFfm;
    var rate = smmPerMonth / 4.345 * ageFactor(profile.age);

    /* 저항운동 게이트.
     * 예전에는 훈련 변수가 이 식에 아예 안 들어와서, 운동을 하나도 안 해도
     * 근육이 붙는다고 계산했습니다. 시험 내 짝 비교 3건이 전부 실패했고
     * 그중 1건은 부호가 반대였습니다.
     * 값이 없으면 1.0 — 모르는 것을 0으로 치면 기존 계획이 전부 뒤집힙니다. */
    /* null 과 undefined 를 구분합니다.
         null      = "보고되지 않음" (검증 하네스의 일부 논문) → 게이트 1.0
         undefined = 필드가 아예 없음 (앱)                  → 프로필의 운동일수를 씀
         숫자      = 그대로
       앱에서 profile.daysPerWeek 은 사용자가 고른 주당 저항운동 일수입니다.
       하네스에서는 이 값이 3 이상으로 클램프되므로 따로 넘겨받습니다. */
    var rt = profile.resistanceDaysPerWeek;
    if (rt === undefined) rt = profile.daysPerWeek;
    if (rt != null && isFinite(rt)) {
      rate *= Math.max(0, Math.min(1, rt / 4));
    }

    /* 시간 포화.
     * 훈련연령은 계획 시작 시점에 고정되지만, 계획이 진행되는 동안 사람은
     * 실제로 경력이 쌓입니다. 이 항이 없으면 근성장 천장이 78주 내내
     * 입문자 수준으로 유지되고, 오차가 기간에 정비례해서 커집니다
     * (논문 22개군에서 기간과 제지방 오차의 상관 r = +0.83).
     *
     * 26주마다 한 단계씩 올라가는 것으로 봅니다. 지수 감쇠 대신 이 방식을
     * 쓴 이유는 바닥이 0 이 아니라 다음 단계의 실제 값이기 때문입니다 —
     * 6개월 훈련했다고 근성장 능력이 사라지지는 않습니다. */
    if (weekIndex != null && weekIndex > 0) {
      var LADDER = ['novice', 'intermediate', 'advanced', 'elite'];
      var at = LADDER.indexOf(profile.trainingAge);
      if (at >= 0) {
        var steps = Math.floor(weekIndex / 26);
        var eff = LADDER[Math.min(LADDER.length - 1, at + steps)];
        var effPct = MUSCLE_BASE[eff].pct;
        if (effPct < base) rate *= effPct / base;
      }
    }

    if (profile.hadPriorPeak) rate *= 2.5;   // 머슬메모리
    if (ffmKg != null) rate *= ffmiFactor(ffmKg, profile);
    return rate;
  }

  function muscleSituation(deficitRatio) {
    if (deficitRatio < -0.02) return 'surplus';
    if (Math.abs(deficitRatio) <= 0.05) return 'maintain';
    if (deficitRatio <= 0.15) return 'recomp';
    return 'cut';
  }

  /**
   * 주당 제지방 손실 (kg). 0 이상.
   * 적자가 깊거나, 단백질이 모자라거나, 체지방이 바닥이면 근육은 실제로 빠진다.
   * 이 경로가 없으면 엔진은 어떤 무리한 계획에서도 "근육은 그대로"라고 답하게 된다.
   */
  function leanLossPerWeek(deficitRatio, proteinPerFFM, pbfPct, sex, ffm) {
    var lean  = pbfPct < (sex === 'male' ? 10 : 18);
    var deep  = deficitRatio > 0.20;
    var lowP  = proteinPerFFM != null && proteinPerFFM < 2.0;
    if (!deep && !lowP && !lean) return 0;
    var frac = 0;                                  // 주당 제지방 손실 비율
    if (deep) frac += Math.min(0.0010, (deficitRatio - 0.20) * 0.01);
    if (lowP) frac += 0.0005;
    if (lean) frac += 0.0005;
    return Math.min(0.0015, frac) * ffm;
  }

  function kcalFloor(profile, bmr) {
    return Math.max(Math.round(bmr * 1.1), profile.sex === 'male' ? 1500 : 1200);
  }

  /* ---------------------------------------------------------------------- */
  /* 4. 주차별 시뮬레이션                                                     */
  /* ---------------------------------------------------------------------- */

  /**
   * 한 주를 전진시킨다.
   * phase: 'cut' | 'bulk' | 'maintain'
   */
  function stepWeek(st, phase, params, profile, k, weekIndex) {
    var ffm = st.smmKg / k;
    var w = ffm + st.bfmKg;
    var bmr = 370 + 21.6 * ffm;
    var pal = (PAL[profile.activityLevel] || PAL.moderate).mult;
    var tdee = bmr * pal;

    var intake, deficit, fatDelta = 0, smmDelta = 0, capped = false, floored = false;
    var hitFatFloor = false;

    if (phase === 'cut') {
      var want = params.deficitPct * tdee;
      var cap = 31 * st.bfmKg;              // 체지방 동원 상한 (kcal/day)
      deficit = Math.min(want, cap);
      if (deficit < want - 1) capped = true;
      intake = tdee - deficit;
      var floor = kcalFloor(profile, bmr);
      if (intake < floor) { intake = floor; deficit = tdee - intake; floored = true; }
      var fatFromKcal = deficit * 7 / KCAL_PER_KG_FAT;
      var fatFromRate = params.ratePct * w;
      fatDelta = -Math.min(fatFromKcal, fatFromRate);
    } else if (phase === 'bulk') {
      var surplus = params.surplusPct * tdee;
      intake = tdee + surplus;
      deficit = -surplus;
      smmDelta = baseSmmRatePerWeek(w, profile, k, ffm);
      var ffmGain = smmDelta / k;
      var totalGain = ffmGain / params.leanFraction;
      fatDelta = Math.max(0, totalGain - ffmGain);
    } else { // maintain
      intake = tdee;
      deficit = 0;
    }

    var leanLoss = 0;
    if (phase !== 'bulk') {
      var deficitRatio = deficit / tdee;
      var situation = muscleSituation(deficitRatio);
      var mult = MUSCLE_SITUATION[situation][profile.trainingAge] != null
        ? MUSCLE_SITUATION[situation][profile.trainingAge]
        : MUSCLE_SITUATION[situation].intermediate;
      smmDelta = baseSmmRatePerWeek(w, profile, k, ffm, weekIndex) * mult;
      if (phase === 'cut') {
        var ffmNow = st.smmKg / k;
        leanLoss = leanLossPerWeek(deficitRatio, params.proteinPerFFM,
                                   st.bfmKg / w * 100, profile.sex, ffmNow);
        smmDelta -= leanLoss * k;          // 제지방 손실을 골격근 단위로 환산
      }
    }

    /* 필수지방 아래로는 내려가지 않습니다.
       엔진이 목표는 필수지방과 대조하면서 궤적에는 하한이 없어서,
       계획이 길어지면 체지방률 1.3% 짜리 주차가 만들어졌습니다.
       생리적으로 불가능하고, 그 위에 세운 계산은 전부 무의미합니다. */
    var next = {
      smmKg: Math.max(1, st.smmKg + smmDelta),
      bfmKg: Math.max(0.5, st.bfmKg + fatDelta)
    };
    next.ffmKg = next.smmKg / k;
    var essentialPct = profile.sex === 'female' ? 12 : 5;   // 경기 직전 선수 수준의 하한
    var floorFat = next.ffmKg * essentialPct / (100 - essentialPct);
    if (next.bfmKg < floorFat) { next.bfmKg = floorFat; hitFatFloor = true; }
    next.weightKg = next.ffmKg + next.bfmKg;

    return {
      state: next, fatFloor: hitFatFloor,
      tdee: Math.round(tdee),
      bmr: Math.round(bmr),
      intake: Math.round(intake),
      deficit: Math.round(deficit),
      capped: capped,
      floored: floored,
      fatDelta: fatDelta,
      smmDelta: smmDelta,
      leanLoss: leanLoss
    };
  }

  function snapshot(st, week, phase, meta) {
    return {
      week: week, phase: phase,
      weightKg: r1(st.weightKg), smmKg: r2(st.smmKg),
      bfmKg: r2(st.bfmKg), ffmKg: r1(st.ffmKg),
      pbfPct: r1(st.bfmKg / st.weightKg * 100),
      intake: meta ? meta.intake : null,
      tdee: meta ? meta.tdee : null,
      deficit: meta ? meta.deficit : null
    };
  }

  /**
   * 전략 A — 동시 진행 (리컴프 / 단순감량 / 단순증량)
   */
  function simulateSimultaneous(cur, goal, profile, a, goalInfo, con) {
    var k = cur.smmToFfm;
    /* 지방 목표가 지금보다 0.05kg 넘게 낮으면 감량으로 시작합니다. 예전엔 0.3kg 까지를
       "지방 목표 없음" 으로 보고 증량으로 시작했는데, 끝났을 때 지방은 목표 + 0.05 안이어야
       해서 — 시작부터 이미 넘은 상태라 — 지방 0.05~0.3kg 줄이기 목표는 어떤 강도로도
       "4년 안에 안 됨" 이었습니다. 0.5kg 줄이기는 되는데 0.2kg 줄이기는 안 되던 것. */
    var isCutting = goalInfo.dBfmKg < -0.05;
    var mode = isCutting ? 'cut' : (goalInfo.dSmmKg > 0.3 ? 'bulk' : 'maintain');
    var params = paramsAt(a, mode === 'bulk' ? 'bulk' : 'cut', con);
    var phase = mode;

    var st = { smmKg: cur.smmKg, bfmKg: cur.bfmKg, ffmKg: cur.ffmKg, weightKg: cur.weightKg };
    var traj = [snapshot(st, 0, phase, null)];
    /* fatWeek 을 0 으로 못박고 다시 확인하지 않던 것이 버그였습니다.
       증량 계획이 목표 지방을 8kg 넘기고 끝나도 "도달"로 표시됐습니다 —
       79kg 을 입력한 사람의 마지막 마일스톤이 88.8kg 이었습니다. */
    var fatWeek = goalInfo.dBfmKg >= -0.05 ? 0 : null;
    var smmWeek = goalInfo.dSmmKg <= 0.3 ? 0 : null;
    var anyCapped = false, anyFloored = false, cutWeeks = 0, leanLossTotal = 0;
    var fatBreached = false, anyFatFloor = false;

    for (var wk = 1; wk <= MAX_WEEKS; wk++) {
      var r = stepWeek(st, phase, params, profile, k, wk);
      /* 증량 한 주가 지방을 목표 위로 올리면, 그 주부터 잉여를 멈춥니다(유지).
         예전엔 넘긴 **뒤에** 멈춰서 마지막 주에 붙은 지방만큼 넘은 채로 끝났고, 끝의 지방은
         목표 안이어야 하므로 "도달 못 함" 이 됐습니다 — 근육 +1kg · 지방 그대로(또는 +0.5kg)
         목표가 어떤 강도로도 안 된다고 나왔고, 지방을 더 많이 올려도 되는 목표만 됐습니다. */
      if (phase === 'bulk' && r.state.bfmKg > goal.bfmKg + 0.05) {
        phase = 'maintain'; fatBreached = true;
        r = stepWeek(st, phase, params, profile, k, wk);
      }
      st = r.state;
      if (phase === 'cut') cutWeeks++;
      if (r.capped) anyCapped = true;
      if (r.floored) anyFloored = true;
      // 필수지방 하한에 닿았다면 더 뺄 수 없습니다 — 계속 돌려봐야 같은 값입니다
      if (r.fatFloor) { anyFatFloor = true; break; }
      if (r.leanLoss > 0) leanLossTotal += r.leanLoss;
      traj.push(snapshot(st, wk, phase, r));

      if (fatWeek === null && st.bfmKg <= goal.bfmKg + 0.05) fatWeek = wk;
      if (smmWeek === null && st.smmKg >= goal.smmKg - 0.005) smmWeek = wk;


      if (fatWeek !== null && smmWeek !== null && st.bfmKg <= goal.bfmKg + 0.05) break;
      // 목표 체지방 도달 후에는 더 깎지 않고 유지로 전환
      if (phase === 'cut' && fatWeek !== null && smmWeek === null) phase = 'maintain';
    }

    // 끝난 시점의 지방이 목표 안에 있어야 도달입니다. 중간에 한 번 지나갔다가
    // 다시 넘어간 것은 도달이 아닙니다.
    var fatOk = st.bfmKg <= goal.bfmKg + 0.05;
    var reached = fatWeek !== null && smmWeek !== null && fatOk;
    var weeks = reached ? Math.max(fatWeek, smmWeek) : null;
    var bottleneck = !reached ? (fatBreached || !fatOk ? 'fatOvershoot' : 'unreachable')
      : (smmWeek > fatWeek ? 'muscle' : (fatWeek > smmWeek ? 'fat' : 'both'));

    return {
      strategy: 'simultaneous',
      strategyLabel: '동시 진행',
      strategyDesc: isCutting && goalInfo.dSmmKg > 0.3
        ? '체지방을 줄이면서 동시에 근육을 늘립니다 (리컴프)'
        : (isCutting ? '체지방 감량에 집중합니다' : '근육 증가에 집중합니다'),
      a: a, params: params, mode: mode,
      weeks: weeks, reached: reached,
      fatWeek: fatWeek, smmWeek: smmWeek,
      fatOvershootKg: fatOk ? 0 : Math.round((st.bfmKg - goal.bfmKg) * 100) / 100,
      bottleneck: bottleneck,
      trajectory: traj,
      capped: anyCapped, floored: anyFloored, fatFloorReached: anyFatFloor,
      continuousCutWeeks: cutWeeks,
      leanLossKg: Math.round(leanLossTotal * 100) / 100,
      phases: [{ name: mode === 'cut' ? '감량' : (mode === 'bulk' ? '증량' : '유지'),
                 from: 0, to: weeks, phase: mode }]
    };
  }

  /**
   * 전략 B — 분할 (감량 → 유지 2주 → 증량 → 미니컷)
   * 근육 목표가 병목일 때 동시 진행보다 빠를 수 있다.
   */
  function simulateSplit(cur, goal, profile, a, goalInfo, con) {
    var k = cur.smmToFfm;
    var cutP = paramsAt(a, 'cut', con);
    var bulkP = paramsAt(a, 'bulk', con);
    var st = { smmKg: cur.smmKg, bfmKg: cur.bfmKg, ffmKg: cur.ffmKg, weightKg: cur.weightKg };
    var traj = [snapshot(st, 0, 'cut', null)];
    var wk = 0, guard = 0;
    var phaseMarks = [];
    var anyCapped = false, anyFloored = false, longestCut = 0, leanLossTotal = 0;

    function run(phase, params, stop, label, maxLen) {
      var start = wk, len = 0;
      while (guard++ < MAX_WEEKS && (maxLen == null || len < maxLen)) {
        if (stop(st)) break;
        var r = stepWeek(st, phase, params, profile, k, wk);
        st = r.state; wk++; len++;
        if (r.capped) anyCapped = true;
        if (r.floored) anyFloored = true;
        if (r.leanLoss > 0) leanLossTotal += r.leanLoss;
        traj.push(snapshot(st, wk, phase, r));
      }
      if (len > 0) {
        phaseMarks.push({ name: label, from: start, to: wk, phase: phase, weeks: len });
        if (phase === 'cut') longestCut = Math.max(longestCut, len);
      }
    }

    run('cut', cutP, function (s) { return s.bfmKg <= goal.bfmKg + 0.05; }, '1단계 · 감량', null);
    run('maintain', cutP, function () { return false; }, '2단계 · 유지 (대사 회복)', 2);
    run('bulk', bulkP, function (s) { return s.smmKg >= goal.smmKg - 0.005; }, '3단계 · 증량', null);
    run('cut', cutP, function (s) { return s.bfmKg <= goal.bfmKg + 0.05; }, '4단계 · 미니컷', null);

    var reached = st.bfmKg <= goal.bfmKg + 0.1 && st.smmKg >= goal.smmKg - 0.02;
    return {
      strategy: 'split',
      strategyLabel: '분할 (감량 → 증량)',
      strategyDesc: '먼저 체지방을 빼고, 유지기를 거쳐 근육을 올린 뒤, 붙은 지방을 다시 정리합니다',
      a: a, params: cutP, bulkParams: bulkP, mode: 'split',
      weeks: reached ? wk : null, reached: reached,
      bottleneck: 'sequence',
      trajectory: traj,
      capped: anyCapped, floored: anyFloored,
      continuousCutWeeks: longestCut,
      leanLossKg: Math.round(leanLossTotal * 100) / 100,
      phases: phaseMarks
    };
  }

  /** 주어진 공격성 a에서 더 빠른 전략을 고른다 */
  function bestAt(cur, goal, profile, a, goalInfo, con) {
    var force = con && con.strategy && con.strategy !== 'auto' ? con.strategy : null;
    var sim = simulateSimultaneous(cur, goal, profile, a, goalInfo, con);
    if (force === 'simultaneous') { sim.alternative = null; return sim; }
    /* 증량 목표도 분할과 견줍니다. 지방 목표가 빠듯하면(지금 체지방 그대로 · 조금 줄이기)
       동시 진행은 잉여를 거의 못 써서 유지 칼로리로만 근육을 붙이는데, 경력이 있으면
       매우 느립니다(53세 · 중급 · 근육 +1kg · 지방 −0.2kg: 64주 — 분할이면 26주).
       지방 여유가 넉넉한 보통의 증량은 분할이 유지 2주만큼 늘 느려서 그대로입니다. */
    if (goalInfo.type !== 'recomp' && goalInfo.type !== 'bulk' && force !== 'split') {
      sim.alternative = null; return sim;
    }
    var split = simulateSplit(cur, goal, profile, a, goalInfo, con);
    if (force === 'split' && split.reached) { split.alternative = null; return split; }
    var best, alt;
    if (split.reached && (!sim.reached || split.weeks < sim.weeks)) { best = split; alt = sim; }
    else { best = sim; alt = split; }
    best.alternative = alt.reached
      ? { strategy: alt.strategy, strategyLabel: alt.strategyLabel, weeks: alt.weeks }
      : null;
    return best;
  }

  /* ---------------------------------------------------------------------- */
  /* 5. 강도 = 기간 — 역산                                                    */
  /* ---------------------------------------------------------------------- */

  var A_GRID = (function () { var g = []; for (var i = 0; i <= 50; i++) g.push(i / 50); return g; })();

  /**
   * a를 0→1로 훑어 (공격성, 소요기간) 곡선을 만든다.
   * 이 곡선이 단조가 아니라는 게 핵심이다 — 너무 공격적이면 근육이 안 늘어
   * 오히려 기간이 늘어난다. 그 지점을 찾아서 사용자에게 보여준다.
   */
  function scanCurve(cur, goal, profile, goalInfo, con) {
    var lo = con && con.aMin != null ? con.aMin : 0;
    var hi = con && con.aMax != null ? con.aMax : 1;
    if (hi <= lo) hi = Math.min(1, lo + 0.05);
    return A_GRID.map(function (t) {
      var a = lo + (hi - lo) * t;
      var sim = bestAt(cur, goal, profile, a, goalInfo, con);
      return { a: a, weeks: sim.reached ? sim.weeks : null, sim: sim };
    });
  }

  /**
   * 세 강도(상=최단 / 중=×1.4 / 하=×2.0)를 계산한다.
   * - 상: 곡선의 최소 기간 지점 (동률이면 더 편한 a를 고른다)
   * - 중/하: 목표 기간에 가장 가까운, 상보다 여유로운 a
   */
  function compareLevels(scan, profile, goal, startDateISO, deadlineWeeks, modeDef) {
    var cur = derive(scan, profile);
    var goalInfo = classifyGoal(cur, goal);
    var start = startDateISO ? new Date(startDateISO) : new Date();
    var con = modeDef ? {
      aMin: modeDef.aMin, aMax: modeDef.aMax, strategy: modeDef.strategy,
      proteinPerFfmMin: modeDef.proteinPerFfmMin, proteinPerFfmMax: modeDef.proteinPerFfmMax
    } : null;
    /* 유지 목표는 "언제 도달하나"가 아니라 "얼마나 유지하나"다.
       궤적을 평평하게 깔고 기간을 준다. 이게 없으면 기간 0, 목표일=오늘이 된다. */
    if (goalInfo.type === 'maintain') {
      return maintenancePlan(cur, goal, goalInfo, profile, start, modeDef, deadlineWeeks);
    }

    var curve = scanCurve(cur, goal, profile, goalInfo, con);
    var reachable = curve.filter(function (c) { return c.weeks != null; });

    if (!reachable.length) {
      return {
        current: cur, goal: goal, goalInfo: goalInfo, curve: curve, mode: modeDef || null,
        startDate: toISODate(start), results: [], recommended: null,
        warnings: ['어떤 강도로도 4년 안에 목표에 도달하지 않습니다. 목표치를 조정해 주세요.'],
        bottleneckNote: null, impossible: true
      };
    }

    var minWeeks = Math.min.apply(null, reachable.map(function (c) { return c.weeks; }));
    // 동률이면 가장 여유로운(a 작은) 쪽 — 같은 기간이면 쉬운 게 낫다
    var fastest = reachable.filter(function (c) { return c.weeks === minWeeks; })[0];
    var maxWeeks = Math.max.apply(null, reachable.map(function (c) { return c.weeks; }));

    // 이 모드에서 실제로 갈 수 있는 "가장 느린" 계획.
    // 고정 배수(1.4x / 2.0x)로 목표를 잡으면 모드가 a 하한을 걸어 둔 경우 중·하가
    // 둘 다 하한에 붙어 같은 계획이 된다. 그래서 목표 기간을 "갈 수 있는 범위" 안으로 접는다.
    var gentlePool = reachable.filter(function (c) { return c.a <= fastest.a; });
    if (!gentlePool.length) gentlePool = reachable;
    var slowest = gentlePool.reduce(function (b, c) { return c.weeks > b.weeks ? c : b; }, gentlePool[0]);
    var slowWeeks = Math.min(slowest.weeks, Math.round(minWeeks * 2.0));
    var TARGET = {
      high: minWeeks,
      mid: Math.round((minWeeks + slowWeeks) / 2),
      low: slowWeeks
    };

    var results = LEVEL_SPEC.map(function (spec) {
      var targetWeeks = TARGET[spec.key];
      var chosen = (spec.key === 'high') ? fastest : gentlePool.reduce(function (best, c) {
        return Math.abs(c.weeks - targetWeeks) < Math.abs(best.weeks - targetWeeks) ? c : best;
      }, gentlePool[0]);
      var sim = chosen.sim;
      var macros = macrosFor(sim, cur, profile);
      var training = resolveTraining(profile, sim.params, goalInfo);
      var feas = feasibility(sim, goalInfo, cur, profile, deadlineWeeks);
      return {
        level: spec.key, label: spec.label, title: spec.title, blurb: spec.blurb,
        targetWeeks: targetWeeks,
        weeks: sim.weeks,
        months: r1(sim.weeks / 4.345),
        targetDate: addWeeks(start, sim.weeks),
        a: chosen.a,
        sim: sim, macros: macros, feasibility: feas,
        difficulty: sim.params.difficulty,
        difficultyLabel: sim.params.difficultyLabel,
        training: training,
        daysPerWeek: training.days,
        sessionMin: training.sessionMin,
        cardioMin: training.cardioMin,
        setsPerMuscle: training.setsPerMuscle,
        cheatMeals: sim.params.cheatMealsPerWeek,
        tracking: sim.params.tracking,
        muscleLossRisk: sim.params.muscleLossRisk,
        weeklyRateKg: avgWeeklyRate(sim.trajectory, 8),
        weeklyRatePct: r2(Math.abs(avgWeeklyRate(sim.trajectory, 8)) / cur.weightKg * 100),
        weeklyFatKg: avgWeeklyFat(sim.trajectory, 8),
        weeklySmmKg: avgWeeklySmm(sim.trajectory, 8)
      };
    });

    // 중복 제거: 세 강도가 같은 a로 수렴하면 표시로 알린다
    var warnings = [];
    var uniqueA = {};
    results.forEach(function (r) { uniqueA[r.a] = (uniqueA[r.a] || 0) + 1; });
    if (Object.keys(uniqueA).length < 3) {
      if (modeDef) {
        var atFloor = results.filter(function (r) {
          return Math.abs(r.a - modeDef.aMin) < 0.005;
        }).length >= 2;
        var atCeil = results.filter(function (r) {
          return Math.abs(r.a - modeDef.aMax) < 0.005;
        }).length >= 2;
        if (atFloor) {
          warnings.push('「' + modeDef.nameKo + '」는 이보다 느리게 가지 않습니다. 이 모드가 허용하는 ' +
            '가장 여유로운 속도에 이미 닿아 있어서, 중·하가 같은 계획이 됩니다. ' +
            '더 천천히 가고 싶으면 모드를 바꿔야 합니다.');
        } else if (atCeil) {
          warnings.push('「' + modeDef.nameKo + '」는 이보다 빠르게 가지 않습니다. 이 모드의 속도 상한은 ' +
            '장식이 아니라 근육을 지키기 위한 잠금장치입니다.');
        } else {
          warnings.push('일부 강도가 같은 계획으로 수렴했습니다. 체지방이 줄면서 안전하게 쓸 수 있는 ' +
            '에너지 상한에 먼저 걸려서, 강도를 올려도 속도가 더 나오지 않는 구간입니다.');
        }
      } else {
        warnings.push('일부 강도가 같은 계획으로 수렴했습니다. 목표 변화량이 작아 속도를 더 낮출 여지가 없다는 뜻입니다.');
      }
    }

    // 역설 탐지
    var aggressive = curve[curve.length - 1];
    if (aggressive.weeks != null && aggressive.weeks > minWeeks * 1.1) {
      warnings.push('가장 공격적인 계획(a=1.0)은 ' + aggressive.weeks + '주로, 최단(' + minWeeks +
        '주)보다 오히려 깁니다. 적자가 크면 근육이 거의 늘지 않아서입니다 — 근육 목표가 있을 때는 무작정 빡세게가 답이 아닙니다.');
    }

    results.forEach(function (r) {
      if (r.sim.params.maxContinuousWeeks && r.sim.continuousCutWeeks > r.sim.params.maxContinuousWeeks) {
        r.capWarning = '이 강도의 감량은 연속 ' + r.sim.params.maxContinuousWeeks +
          '주가 한계인데 계획상 ' + r.sim.continuousCutWeeks + '주 연속입니다. 중간에 2주 유지기를 넣으세요.';
      }
      if (r.sim.leanLossKg > 0.3) {
        r.leanLossWarning = '이 속도로 가면 계획 기간 동안 제지방이 약 ' +
          r1(r.sim.leanLossKg) + 'kg 빠질 것으로 계산됩니다. 적자가 깊거나 단백질이 부족하거나 ' +
          '체지방이 이미 낮을 때 생깁니다.';
      }
      if (r.sim.capped) {
        r.capNote = '체지방이 줄면서 안전하게 동원 가능한 에너지 상한에 걸려, 후반부에는 계획보다 적자가 자동으로 작아집니다.';
      }
      if (r.sim.floored) {
        r.floorNote = '계산상 섭취량이 최소 섭취 기준 아래로 내려가 바닥값으로 올렸습니다.';
      }
    });

    // 추천: 기간 차이가 15% 이내면 더 쉬운 쪽
    var ok = results.filter(function (r) { return r.sim.reached; });
    var recommended = null;
    if (ok.length) {
      var best = ok.slice().sort(function (x, y) { return x.weeks - y.weeks; })[0];
      var near = ok.filter(function (r) { return r.weeks <= best.weeks * 1.15; });
      near.sort(function (x, y) { return x.difficulty - y.difficulty; });
      recommended = near[0].level;
    }

    return {
      current: cur, goal: goal, goalInfo: goalInfo, mode: modeDef || null,
      startDate: toISODate(start),
      minWeeks: minWeeks, maxWeeks: maxWeeks,
      spanWeeks: [minWeeks, slowest.weeks],
      spanNote: spanNote(minWeeks, slowest.weeks, modeDef),
      curve: curve.map(function (c) { return { a: c.a, weeks: c.weeks }; }),
      results: results, recommended: recommended, warnings: warnings,
      bottleneckNote: bottleneckNote(results, goalInfo)
    };
  }

  /* ---------------------------------------------------------------------- */
  /* 6. 매크로 / 운동 / 식단                                                  */
  /* ---------------------------------------------------------------------- */

  function macrosFor(sim, cur, profile) {
    // 계획 1주차 기준으로 제시한다. 체크인마다 재계산되는 값이다.
    var t = sim.trajectory[1] || sim.trajectory[0];
    var intake = t.intake || cur.tdeeKcal;
    var ffm = t.ffmKg, bw = t.weightKg;
    var firstPhase = (sim.phases[0] && sim.phases[0].phase) || 'cut';
    var isBulk = firstPhase === 'bulk';
    var p = isBulk ? (sim.bulkParams || paramsAt(sim.a, 'bulk')) : sim.params;

    // 체중 기준 하한도 함께 건다 (근육 목표가 있을 때 단백질이 모자라면 계획 자체가 무의미)
    var proteinG = Math.round(Math.max(ffm * p.proteinPerFFM, bw * 1.6));
    var fatG = isBulk ? Math.round(intake * p.fatPctKcal / 9) : Math.round(bw * p.fatPerKg);
    var carbKcal = intake - proteinG * 4 - fatG * 9;
    if (carbKcal < 200) {                     // 탄수 바닥 — 지방부터 줄인다
      var need = 200 - carbKcal;
      fatG = Math.max(Math.round(bw * 0.4), fatG - Math.ceil(need / 9));
      carbKcal = intake - proteinG * 4 - fatG * 9;
    }
    var carbG = Math.max(50, Math.round(carbKcal / 4));

    return {
      intakeKcal: Math.round(intake),
      tdeeKcal: t.tdee || cur.tdeeKcal,
      deficitKcal: t.deficit || 0,
      proteinG: proteinG, carbG: carbG, fatG: fatG,
      proteinPerFFM: r1(p.proteinPerFFM),
      proteinPerBW: r1(proteinG / bw),
      pctProtein: Math.round(proteinG * 4 / intake * 100),
      pctCarb: Math.round(carbG * 4 / intake * 100),
      pctFat: Math.round(fatG * 9 / intake * 100)
    };
  }

  var SPLITS = {
    3: { name: '전신 3분할',   days: ['전신 A', '휴식', '전신 B', '휴식', '전신 C', '휴식', '휴식'] },
    4: { name: '상하체 4분할', days: ['상체 A', '하체 A', '휴식', '상체 B', '하체 B', '휴식', '휴식'] },
    5: { name: 'PPL + 상하체', days: ['가슴·어깨·삼두', '등·이두', '하체', '휴식', '상체 전체', '하체·코어', '휴식'] },
    6: { name: 'PPL 2회전',    days: ['푸시 A', '풀 A', '레그 A', '푸시 B', '풀 B', '레그 B', '휴식'] }
  };

  function workoutFor(sim, cur, profile, scan, goalInfo) {
    var p = sim.params;
    var tr = resolveTraining(profile, p, goalInfo);
    var days = tr.days;
    var split = SPLITS[days] || SPLITS[4];
    var E = global.MB_DATA.EXERCISES;

    // 인바디 부위별 분석 → 종목 편향 (인바디를 실제로 쓰고 있다는 체감 포인트)
    var bias = [];
    if (scan && scan.segmentalLean) {
      var L = scan.segmentalLean;
      if (L.rightArm === '표준이하' || L.leftArm === '표준이하') bias.push('팔 근육 표준 이하 → 팔 보조 볼륨 주 +2세트');
      if (L.trunk === '표준이하') bias.push('몸통 근육 표준 이하 → 코어·척추기립근 보강');
      if (L.rightLeg === '표준이하' || L.leftLeg === '표준이하') bias.push('하체 근육 표준 이하 → 하체 볼륨 주 +3세트');
      if (L.rightArm !== L.leftArm) bias.push('좌우 팔 불균형 → 원암(편측) 종목 우선');
      if (L.rightLeg !== L.leftLeg) bias.push('좌우 다리 불균형 → 불가리안 스플릿스쿼트 필수');
    }
    if (scan && scan.segmentalFat) {
      var F = scan.segmentalFat;
      if (F.trunk === '표준이상') bias.push('몸통 지방 표준 이상 → 내장지방 우선, Z2 유산소 비중 ↑');
      if (F.rightArm === '표준이상' && F.rightLeg === '표준') bias.push('상체에 지방이 몰린 패턴 → 상체 볼륨보다 전신 에너지 소모 우선');
    }
    /* 부위별 값이 없으면 "약점 없음" 이라고 말하지 않습니다.
     *
     * 예전엔 bias 가 비면 무조건 '부위별 분석상 뚜렷한 약점 없음' 을
     * 붙였습니다. 그런데 부위별 값은 앱에 들어오는 길이 없습니다 —
     * 화면에도 없고, 서버 판독이 읽는 14개 칸에도 없습니다. 시드에만
     * 있습니다. 그래서 모든 사용자가 "당신의 인바디를 봤더니 약점이
     * 없더라" 는 말을 들었습니다. 본 적이 없는데요.
     *
     * 결과지에는 실제로 좌우 근육량 비교가 인쇄돼 있습니다. 그걸
     * 읽지도 않고 "괜찮다" 고 말하면, 진짜 불균형이 있는 사람은
     * 확인받았다고 믿고 넘어갑니다. 없는 것은 없다고 말합니다. */
    var hasSegmental = !!(scan && (scan.segmentalLean || scan.segmentalFat));
    if (!bias.length) {
      bias.push(hasSegmental
        ? '부위별 분석상 뚜렷한 약점 없음 → 균형 프로그램'
        : '부위별 분석은 아직 넣을 수 없습니다 → 지금은 균형 배분입니다');
    }

    function pick(group, n) {
      var pool = E[group] || [];
      return pool.slice(0, Math.min(n, pool.length));
    }

    var sessions = split.days.map(function (label, i) {
      if (label === '휴식') return { day: i, label: label, rest: true, exercises: [] };
      var groups;
      if (/전신/.test(label))           groups = [['quads',1],['back',1],['chest',1],['shoulder',1],['core',1]];
      else if (/상체/.test(label))      groups = [['chest',2],['back',2],['shoulder',1],['arms',2]];
      else if (/하체|레그/.test(label)) groups = [['quads',2],['hamsGlutes',2],['core',1]];
      else if (/푸시|가슴/.test(label)) groups = [['chest',2],['shoulder',2],['arms',1]];
      else if (/풀|등/.test(label))     groups = [['back',3],['arms',1]];
      else                              groups = [['chest',1],['back',1],['quads',1],['core',1]];

      var ex = [];
      groups.forEach(function (g) {
        pick(g[0], g[1]).forEach(function (item) {
          var isCompound = /스쿼트|데드|벤치|프레스|로우|풀업|딥스/.test(item.name);
          ex.push({
            name: item.name, equip: item.equip, note: item.note, group: g[0],
            sets: isCompound ? (tr.setsPerMuscle >= 16 ? 4 : 3) : 3,
            reps: isCompound ? '5-8' : '10-15',
            restSec: isCompound ? 150 : 75,
            rpe: p.difficulty >= 3 ? '8-9' : (p.difficulty === 2 ? '7-8' : '6-8')
          });
        });
      });
      return { day: i, label: label, rest: false, exercises: ex, minutes: tr.sessionMin };
    });

    tr.reason.forEach(function (r) { bias.push(r); });

    return {
      splitName: split.name,
      daysPerWeek: days,
      sessionMinutes: tr.sessionMin,
      setsPerMuscle: tr.setsPerMuscle,
      cardioMinPerWeek: tr.cardioMin,
      cardioPlan: tr.cardioMin >= 180 ? 'Z2 저강도 40분 × 4회 + HIIT 15분 × 2회'
                : (tr.cardioMin >= 120 ? 'Z2 저강도 45분 × 3회' : 'Z2 저강도 40분 × 2회'),
      deloadEvery: p.deloadEvery,
      progression: '더블 프로그레션 — 목표 반복 상단에 도달하면 다음 세션에 중량 2.5~5kg 증가',
      inbodyBias: bias,
      hasSegmental: hasSegmental,
      sessions: sessions
    };
  }

  function dietFor(macros, profile) {
    var meals = profile.mealsPerDay === 2 ? 2 : (profile.mealsPerDay === 4 ? 4 : 3);
    var names   = meals === 2 ? ['점심','저녁'] : (meals === 4 ? ['아침','점심','간식','저녁'] : ['아침','점심','저녁']);
    var weights = meals === 2 ? [0.5,0.5]      : (meals === 4 ? [0.25,0.30,0.15,0.30]      : [0.30,0.35,0.35]);
    var F = global.MB_DATA.FOODS;
    function byTag(t) { return F.filter(function (x) { return x.tags.indexOf(t) >= 0; }); }
    var proteins = byTag('protein'), carbs = byTag('carb'), sides = byTag('side'), soups = byTag('soup');

    var mealPlan = names.map(function (n, i) {
      var kcal    = Math.round(macros.intakeKcal * weights[i]);
      var protein = Math.round(macros.proteinG  * weights[i]);
      var carb    = Math.round(macros.carbG     * weights[i]);
      var fat     = Math.round(macros.fatG      * weights[i]);
      var pf = proteins[i % proteins.length];
      var cf = carbs[i % carbs.length];
      var sf = sides[i % sides.length];
      var soup = soups[i % soups.length];
      var riceG = Math.round(carb / (cf.c || 60) * 100);
      var meatG = Math.round(protein / (pf.p || 20) * 100);
      return {
        name: n, kcal: kcal, proteinG: protein, carbG: carb, fatG: fat,
        options: [
          { label: '한식 A', items: [cf.name + ' 약 ' + riceG + 'g', pf.name + ' ' + meatG + 'g', soup.name + ' (국물 남기기)', sf.name] },
          { label: '간편 B', items: ['유청단백 1스쿱', '고구마 150g', '삶은계란 2개', '샐러드채소 100g'] }
        ]
      };
    });

    return {
      mealsPerDay: meals,
      meals: mealPlan,
      proteinPerMeal: Math.round(macros.proteinG / meals),
      hydrationL: 2.5,
      eatingOut: global.MB_DATA.EATING_OUT,
      notes: [
        '단백질은 끼니당 30~40g씩 고르게 나누는 편이 근단백 합성에 유리합니다.',
        '한식은 국·찌개의 나트륨이 높아 체중계 숫자를 며칠씩 흔듭니다. 국물은 남기세요.',
        '체중은 수분·나트륨 때문에 하루 ±1kg 흔들립니다. 하루 값이 아니라 주 평균으로 보세요.'
      ]
    };
  }

  /* ---------------------------------------------------------------------- */
  /* 7. 실현가능성 / 안전장치                                                 */
  /* ---------------------------------------------------------------------- */

  function feasibility(sim, goalInfo, cur, profile, deadlineWeeks) {
    var blockers = [];
    var essentialFat = profile.sex === 'male' ? 8 : 15;
    // 목표 제지방량이 사람의 상한을 넘는가
    var goalFfm = (cur.smmKg + goalInfo.dSmmKg) / cur.smmToFfm;
    var goalFfmi = ffmiOf(goalFfm, profile.heightCm);
    var ceil = ffmiCeiling(profile.sex);
    if (goalFfmi > ceil) {
      blockers.push('목표 골격근량이 약물 없이 도달 가능한 상한을 넘습니다 (제지방량지수 ' +
        r1(goalFfmi) + ', 상한 약 ' + ceil + ').');
    }
    if (goalInfo.targetPbfPct < essentialFat) {
      blockers.push('목표 체지방률 ' + goalInfo.targetPbfPct + '%는 필수지방(' + essentialFat + '%) 아래입니다.');
    }
    if (!sim.reached) blockers.push('이 설정으로는 4년 안에도 목표에 도달하지 않습니다.');

    var verdict, badge, message;
    if (blockers.length)                        { verdict='blocked';      badge='⛔'; message=blockers[0]; }
    else if (!deadlineWeeks)                    { verdict='ok';           badge='🟢'; message='이 강도로 약 ' + sim.weeks + '주 걸립니다.'; }
    else if (sim.weeks <= deadlineWeeks)        { verdict='ok';           badge='🟢'; message='희망하신 ' + deadlineWeeks + '주 안에 가능합니다 (예상 ' + sim.weeks + '주).'; }
    else if (sim.weeks <= deadlineWeeks * 1.5)  { verdict='tough';        badge='🟡'; message='가능은 하지만 ' + sim.weeks + '주가 필요합니다 (희망보다 ' + (sim.weeks - deadlineWeeks) + '주 김).'; }
    else                                        { verdict='unrealistic';  badge='🔴'; message=deadlineWeeks + '주 안에는 어렵습니다. 정직하게 약 ' + sim.weeks + '주가 필요합니다.'; }

    return { verdict: verdict, badge: badge, message: message, blockers: blockers, weeks: sim.weeks };
  }

  /**
   * 이 모드에서 고를 수 있는 기간 폭이 왜 이만큼인지 설명한다.
   * 좁으면 좁은 이유를 말해야지, 세 장의 카드로 넓은 척하면 안 된다.
   */
  function spanNote(minW, maxW, modeDef) {
    var spread = maxW - minW;
    var ratio = minW > 0 ? maxW / minW : 1;
    if (!modeDef) {
      return { spread: spread, tight: ratio < 1.35,
               text: '이 목표는 ' + minW + '~' + maxW + '주 사이에서 고를 수 있습니다.' };
    }
    var text = '「' + modeDef.nameKo + '」 안에서는 이 목표가 ' + minW + '~' + maxW + '주입니다.';
    if (ratio < 1.35) {
      text += ' 폭이 좁은 이유는 두 가지입니다 — 아래로는 이 모드가 허용하는 가장 느린 속도(공격성 ' +
              modeDef.aMin + ')에 이미 닿았고, 위로는 체지방이 하루에 안전하게 내놓을 수 있는 ' +
              '에너지 상한에 걸립니다. 더 여유롭게 가고 싶으면 강도가 아니라 모드를 바꿔야 합니다.';
    }
    return { spread: spread, tight: ratio < 1.35, text: text };
  }

  /**
   * 유지 계획 — 상/중/하는 "얼마나 오래 유지할까"가 된다.
   * 감량 직후 대사 회복, 증량 전 안정화, 목표 달성 후 굳히기에 쓰인다.
   */
  function maintenancePlan(cur, goal, goalInfo, profile, start, modeDef, deadlineWeeks) {
    var SPAN = { high: 4, mid: 8, low: 12 };
    if (deadlineWeeks) {
      SPAN = { high: Math.max(2, Math.round(deadlineWeeks * 0.5)),
               mid: Math.max(3, deadlineWeeks),
               low: Math.max(4, Math.round(deadlineWeeks * 1.5)) };
    }
    var k = cur.smmToFfm;
    var params = paramsAt(0, 'cut', modeDef ? {
      aMin: modeDef.aMin, aMax: modeDef.aMax,
      proteinPerFfmMin: modeDef.proteinPerFfmMin, proteinPerFfmMax: modeDef.proteinPerFfmMax
    } : null);

    var results = LEVEL_SPEC.map(function (spec) {
      var weeks = SPAN[spec.key];
      var st = { smmKg: cur.smmKg, bfmKg: cur.bfmKg, ffmKg: cur.ffmKg, weightKg: cur.weightKg };
      var traj = [snapshot(st, 0, 'maintain', null)];
      for (var w = 1; w <= weeks; w++) {
        var r = stepWeek(st, 'maintain', params, profile, k, w);
        st = r.state;
        traj.push(snapshot(st, w, 'maintain', r));
      }
      var sim = {
        strategy: 'maintain', strategyLabel: '유지',
        strategyDesc: '지금 몸을 지키면서 대사와 습관을 안정시킵니다',
        a: 0, params: params, mode: 'maintain',
        weeks: weeks, reached: true, bottleneck: 'none',
        trajectory: traj, capped: false, floored: false, continuousCutWeeks: 0,
        leanLossKg: 0, alternative: null,
        phases: [{ name: '유지', from: 0, to: weeks, phase: 'maintain', weeks: weeks }]
      };
      var macros = macrosFor(sim, cur, profile);
      var training = resolveTraining(profile, params, goalInfo);
      return {
        level: spec.key, label: spec.label,
        title: ({ high: '짧게', mid: '표준', low: '길게' })[spec.key],
        blurb: ({ high: '4주만 굳히고 다음 단계로',
                  mid: '8주 — 대사 회복에 보통 권하는 길이',
                  low: '12주 — 습관이 자리 잡을 때까지' })[spec.key],
        targetWeeks: weeks, weeks: weeks, months: r1(weeks / 4.345),
        targetDate: addWeeks(start, weeks), a: 0,
        sim: sim, macros: macros,
        feasibility: { verdict: 'ok', badge: '🟢',
                       message: weeks + '주 동안 지금 몸을 지킵니다.', blockers: [], weeks: weeks },
        difficulty: 1, difficultyLabel: '★☆☆ 낮음',
        training: training, daysPerWeek: training.days, sessionMin: training.sessionMin,
        cardioMin: training.cardioMin, setsPerMuscle: training.setsPerMuscle,
        cheatMeals: 2, tracking: '무게만 주 2~3회',
        muscleLossRisk: '매우 낮음',
        weeklyRateKg: 0, weeklyRatePct: 0, weeklyFatKg: 0, weeklySmmKg: avgWeeklySmm(traj, 8)
      };
    });

    return {
      current: cur, goal: goal, goalInfo: goalInfo, mode: modeDef || null,
      startDate: toISODate(start),
      minWeeks: SPAN.high, maxWeeks: SPAN.low,
      spanWeeks: [SPAN.high, SPAN.low],
      spanNote: { spread: SPAN.low - SPAN.high, tight: false,
                  text: '유지는 도달할 목표가 아니라 지켜낼 기간입니다. 얼마나 오래 유지할지를 고릅니다.' },
      curve: [], results: results, recommended: 'mid',
      warnings: [],
      bottleneckNote: { key: 'none', text: '유지 구간입니다. 체중이 ±1kg 안에서 움직이면 성공입니다.' },
      isMaintenance: true
    };
  }

  function bottleneckNote(results, goalInfo) {
    var r = results.find(function (x) { return x.sim.reached; });
    if (!r) return null;
    var b = r.sim.bottleneck;
    if (b === 'muscle') return { key: 'muscle', text: '병목은 근육 목표입니다. 체지방은 훨씬 먼저 도달하지만, 근육은 생리적 속도 상한 때문에 기다려야 합니다.' };
    if (b === 'fat')    return { key: 'fat',    text: '병목은 체지방 목표입니다. 근육 목표는 먼저 달성됩니다.' };
    if (b === 'sequence') return { key: 'sequence', text: '감량과 증량을 순서대로 나누는 전략이 더 빠릅니다. 동시에 하면 근육 증가가 거의 멈추기 때문입니다.' };
    return { key: 'both', text: '체지방과 근육 목표가 비슷한 시점에 도달합니다.' };
  }

  /** 선택된 강도로 최종 플랜 조립 */
  function buildPlan(comparison, level, scan, profile) {
    var r = comparison.results.find(function (x) { return x.level === level; });
    if (!r) return null;
    return {
      level: level,
      mode: comparison.mode || null,
      goal: {
        weightKg: comparison.goal.weightKg,
        smmKg: comparison.goal.smmKg,
        bfmKg: comparison.goal.bfmKg,
        modeId: comparison.goal.modeId || null
      },
      label: r.label,
      title: r.title,
      weeks: r.weeks,
      targetDate: r.targetDate,
      startDate: comparison.startDate,
      strategy: r.sim.strategy,
      strategyLabel: r.sim.strategyLabel,
      strategyDesc: r.sim.strategyDesc,
      phases: r.sim.phases,
      trajectory: r.sim.trajectory,
      bottleneck: comparison.bottleneckNote,
      macros: r.macros,
      workout: workoutFor(r.sim, comparison.current, profile, scan, comparison.goalInfo),
      diet: dietFor(r.macros, profile),
      feasibility: r.feasibility,
      capWarning: r.capWarning || null,
      milestones: milestonesFrom(r.sim.trajectory, comparison.startDate)
    };
  }

  function milestonesFrom(traj, startISO) {
    var out = [], start = new Date(startISO);
    for (var i = 4; i < traj.length; i += 4) {
      var t = traj[i];
      out.push({
        week: t.week, date: addWeeks(start, t.week),
        weightKg: t.weightKg, smmKg: t.smmKg, bfmKg: t.bfmKg, pbfPct: t.pbfPct
      });
    }
    var last = traj[traj.length - 1];
    if (!out.length || out[out.length - 1].week !== last.week) {
      out.push({ week: last.week, date: addWeeks(start, last.week),
                 weightKg: last.weightKg, smmKg: last.smmKg, bfmKg: last.bfmKg,
                 pbfPct: last.pbfPct, final: true });
    } else { out[out.length - 1].final = true; }
    return out;
  }

  /**
   * 계획 대비 지금 어디쯤인가.
   * "계획보다 2주 빠릅니다" 처럼 사람이 바로 이해하는 단위로 돌려준다.
   * kg 차이만 말하면 그게 빠른 건지 느린 건지 판단을 사용자에게 떠넘기게 된다.
   */
  function planDrift(plan, scans, profile) {
    if (!plan || !scans || scans.length < 1) return null;
    var latest = scans[scans.length - 1];
    var cur = derive(latest, profile);
    var start = new Date(plan.startDate + 'T00:00:00');
    var now = new Date(String(latest.measuredAt).slice(0, 10) + 'T00:00:00');
    var weeksElapsed = (now - start) / (86400000 * 7);
    if (weeksElapsed < 0) weeksElapsed = 0;

    var traj = plan.trajectory || [];
    if (traj.length < 2) return null;

    function at(week) {
      var w = Math.max(0, Math.min(traj.length - 1, week));
      var lo = Math.floor(w), hi = Math.min(traj.length - 1, lo + 1), f = w - lo;
      function mix(k) { return traj[lo][k] + (traj[hi][k] - traj[lo][k]) * f; }
      return { weightKg: mix('weightKg'), smmKg: mix('smmKg'), bfmKg: mix('bfmKg') };
    }
    var expected = at(weeksElapsed);

    var NF = global.MB_MODES ? global.MB_MODES.NOISE : { weight: 1.0, smm: 0.6, bfm: 1.0 };
    var gapBfm = cur.bfmKg - expected.bfmKg;          // 음수 = 계획보다 지방이 적다
    var gapWeight = cur.weightKg - expected.weightKg;
    var gapSmm = cur.smmKg - expected.smmKg;

    /* 어느 축으로 진행을 재는가.
     *
     * 예전에는 무조건 체지방 축이었습니다. 그래서 증량 계획에서
     *   지방만 +2kg          → "계획보다 22주 빠릅니다" (칭찬)
     *   지방 -2kg (린벌크 성공) → "계획보다 8주 느립니다" (질책)
     *   근육 -2kg (근손실)     → "계획대로 가고 있습니다"
     * 가 나왔습니다. gapSmm 은 계산해 놓고 판정에 쓰지 않았습니다. */
    var fatSpan = Math.max.apply(null, traj.map(function (t) { return t.bfmKg; })) -
                  Math.min.apply(null, traj.map(function (t) { return t.bfmKg; }));
    var smmSpan = Math.max.apply(null, traj.map(function (t) { return t.smmKg; })) -
                  Math.min.apply(null, traj.map(function (t) { return t.smmKg; }));
    var fatMoves = fatSpan >= NF.bfm;
    var smmMoves = smmSpan >= NF.smm;

    // 계획이 실제로 움직이겠다고 한 축만 씁니다. 둘 다 움직이면 더 크게 움직이는 쪽.
    var axis = null;
    if (fatMoves && smmMoves) axis = (fatSpan / NF.bfm >= smmSpan / NF.smm) ? 'bfm' : 'smm';
    else if (fatMoves) axis = 'bfm';
    else if (smmMoves) axis = 'smm';

    var isCut = traj[traj.length - 1].bfmKg < traj[0].bfmKg;
    var weeksAhead = null, matchWeek = null;
    if (axis) {
      var key = axis === 'bfm' ? 'bfmKg' : 'smmKg';
      var goingDown = traj[traj.length - 1][key] < traj[0][key];
      var val = axis === 'bfm' ? cur.bfmKg : cur.smmKg;
      for (var i = 0; i < traj.length; i++) {
        var hit = goingDown ? (traj[i][key] <= val) : (traj[i][key] >= val);
        if (hit) { matchWeek = i; break; }
      }
      if (matchWeek === null) matchWeek = goingDown ? 0 : traj.length - 1;
      weeksAhead = matchWeek - weeksElapsed;
    }

    var gapAxis = axis === 'smm' ? -gapSmm : gapBfm;   // 두 축 모두 "양수 = 뒤처짐"
    var noiseAxis = axis === 'smm' ? NF.smm : NF.bfm;

    var status, headline;
    var absAhead = weeksAhead === null ? 0 : Math.abs(weeksAhead);
    if (axis === null) {
      /* 유지 계획입니다. 궤적이 노이즈 안에서만 움직이므로 "몇 주 빠르다"는
         경과 시간의 함수로 퇴화하고, 지방이 많을수록 점수가 높아집니다.
         주차 숫자를 아예 내지 않습니다. */
      status = (Math.abs(gapWeight) < NF.weight) ? 'onTrack' : 'off';
      headline = status === 'onTrack' ? '유지 범위 안입니다.' : '유지 범위를 벗어났습니다.';
    } else if (Math.abs(gapAxis) < noiseAxis) {
      status = 'onTrack';
      headline = '계획대로 가고 있습니다.';
    } else if (weeksAhead > 0) {
      status = 'ahead';
      headline = Math.round(absAhead) === 0 ? '계획보다 조금 빠릅니다.'
                                            : '계획보다 ' + Math.round(absAhead) + '주 빠릅니다.';
    } else if (Math.round(absAhead) === 0) {
      /* 반올림하면 0 인데 "0주 느립니다"라고 말하고 있었습니다.
         축의 차이는 노이즈를 넘었지만 주차로는 한 주도 안 되는 경우입니다. */
      status = 'behind';
      headline = '계획보다 조금 느립니다.';
    } else {
      status = absAhead >= 4 ? 'off' : 'behind';
      headline = '계획보다 ' + Math.round(absAhead) + '주 느립니다.';
    }

    /* 근손실은 어느 축을 쓰든 따로 말합니다. 축이 지방이면 근육이 빠져도
       "계획대로"가 나오는데, 그건 이 앱이 절대 하면 안 되는 말입니다.
     *
     * 단 "계획이 기대한 만큼 안 늘었다"와 "실제로 줄었다"는 다릅니다.
     * 전자는 흔한 편차이고 후자만 경고입니다. 예전 수정은 이걸 구분하지 않아
     * "4주 빠릅니다"인데 상태는 behind 인 모순을 만들었습니다.
     * headline 도 건드리지 않습니다 — 축의 판정과 섞이면 문장이 모순됩니다. */
    var muscleWarning = null;
    var smmFell = cur.smmKg - traj[0].smmKg;          // 시작 대비 실제 변화
    if (smmFell < -NF.smm) {
      muscleWarning = '시작보다 근육이 ' + Math.abs(r2(smmFell)) + 'kg 줄었습니다.';
      if (status === 'onTrack' || status === 'ahead') status = 'behind';
    } else if (gapSmm < -NF.smm) {
      // 줄지는 않았지만 계획이 기대한 만큼 안 늘었습니다. 상태는 안 바꿉니다.
      muscleWarning = '근육이 계획보다 ' + Math.abs(r2(gapSmm)) + 'kg 적습니다.';
    }

    // 지금 속도가 아니라 지금 몸 상태에서 남은 거리를 다시 계산한 날짜
    var projectedDate = null, dayDelta = null;
    try {
      var goal = plan.goal;
      if (goal) {
        var modeDef = (goal.modeId && global.MB_MODES) ? global.MB_MODES.byId(goal.modeId) : null;
        var cmp = compareLevels(latest, profile, goal, toISODate(now),
                                null, modeDef);
        var same = cmp.results.filter(function (r) { return r.level === plan.level; })[0];
        if (same && same.targetDate) {
          projectedDate = same.targetDate;
          dayDelta = daysUntil(plan.targetDate, projectedDate);   // 양수 = 당겨짐
        }
      }
    } catch (e) { /* 재계산 실패는 치명적이지 않다 */ }

    /* onTrack 인 동안에는 계획 변경을 권하지 않습니다.
       예전엔 "계획대로 가고 있습니다" 와 계획 변경 권유가 같이 나왔습니다. */
    var recommend = status !== 'onTrack' &&
                    ((status === 'off') ||
                     (status === 'behind' && absAhead >= 3) ||
                     (dayDelta !== null && Math.abs(dayDelta) >= 21));

    return {
      weeksElapsed: Math.round(weeksElapsed * 10) / 10,
      expected: { weightKg: r1(expected.weightKg), smmKg: r2(expected.smmKg), bfmKg: r2(expected.bfmKg) },
      actual: { weightKg: cur.weightKg, smmKg: cur.smmKg, bfmKg: cur.bfmKg },
      gapWeightKg: r1(gapWeight), gapSmmKg: r2(gapSmm), gapBfmKg: r2(gapBfm),
      weeksAhead: weeksAhead === null ? null : Math.round(weeksAhead * 10) / 10,
      axis: axis, muscleWarning: muscleWarning,
      status: status, headline: headline,
      projectedDate: projectedDate, dayDelta: dayDelta,
      recommendChange: recommend,
      noise: NF
    };
  }

  /**
   * 식단 달성률.
   * 미기록일은 분모에서 뺀다 — 0으로 치환하면 평균이 폭락하고,
   * 그 값을 보고 칼로리를 더 깎으면 실제로 사람을 굶기게 된다.
   *
   * @param days   [{date, logged, kcal, p, c, f}]  기록 유무 포함
   * @param target {intakeKcal, proteinG, carbG, fatG}
   */
  function dietAdherence(days, target) {
    if (!target) return null;
    var loggedDays = days.filter(function (d) { return d.logged; });
    var n = loggedDays.length;
    var out = {
      totalDays: days.length, loggedDays: n, missedDays: days.length - n,
      logRatePct: days.length ? Math.round(n / days.length * 100) : 0,
      avg: null, pct: null, inBandDays: 0, proteinHitDays: 0, band: null
    };
    // 칼로리는 점이 아니라 밴드다. TDEE 추정 오차와 기록 오차를 합치면
    // ±10% 안쪽은 "맞춘 것"으로 봐야 한다. 2,400 목표에 2,500 먹고 빨간불이
    // 켜지는 앱은 없는 정밀도를 파는 것이다.
    out.band = { lo: Math.round(target.intakeKcal * 0.9), hi: Math.round(target.intakeKcal * 1.1) };
    if (!n) return out;

    var sum = { kcal: 0, p: 0, c: 0, f: 0 };
    loggedDays.forEach(function (d) {
      sum.kcal += d.kcal || 0; sum.p += d.p || 0; sum.c += d.c || 0; sum.f += d.f || 0;
      if ((d.kcal || 0) >= out.band.lo && (d.kcal || 0) <= out.band.hi) out.inBandDays++;
      if ((d.p || 0) >= target.proteinG * 0.9) out.proteinHitDays++;
    });
    out.avg = {
      kcal: Math.round(sum.kcal / n),
      p: Math.round(sum.p / n * 10) / 10,
      c: Math.round(sum.c / n * 10) / 10,
      f: Math.round(sum.f / n * 10) / 10
    };
    out.pct = {
      kcal: Math.round(out.avg.kcal / target.intakeKcal * 100),
      p: Math.round(out.avg.p / target.proteinG * 100),
      c: target.carbG ? Math.round(out.avg.c / target.carbG * 100) : null,
      f: target.fatG ? Math.round(out.avg.f / target.fatG * 100) : null
    };
    out.inBandPct = Math.round(out.inBandDays / n * 100);
    out.proteinHitPct = Math.round(out.proteinHitDays / n * 100);
    return out;
  }

  /**
   * 오늘 상태에 대한 한 줄 안내.
   * 명령이 아니라 상태 보고로 쓴다. "그만 드세요"는 앱이 내리는 지시이고,
   * "오늘 목표치를 다 채웠습니다"는 정보다. 정보는 결정권을 사람에게 남긴다.
   * 단백질 부족 안내는 덧셈형이라 안전하므로 그대로 둔다.
   */
  function dietNudge(today, target) {
    if (!target) return null;
    var kcal = today.kcal || 0, p = today.p || 0;
    var remainKcal = target.intakeKcal - kcal;
    var remainP = Math.max(0, target.proteinG - p);
    var band = { lo: target.intakeKcal * 0.9, hi: target.intakeKcal * 1.1 };
    var hour = new Date().getHours();

    if (!today.logged) {
      return { kind: 'none', tone: '', text: '오늘은 아직 기록이 없습니다.',
               detail: '한 끼만 적어도 주 평균이 살아납니다.' };
    }
    if (remainP > 25 && hour >= 19) {
      return { kind: 'protein', tone: 'warn',
               text: '단백질이 ' + Math.round(remainP) + 'g 남았습니다.',
               detail: '닭가슴살 한 팩이 약 23g, 계란 두 개가 약 12g입니다.' };
    }
    if (kcal > band.hi) {
      // 초과를 빚처럼 표시하지 않는다. 상태만 알린다.
      return { kind: 'over', tone: 'warn',
               text: '오늘 목표 범위를 넘었습니다 (' + Math.round(kcal) + ' / ' +
                     Math.round(target.intakeKcal) + 'kcal).',
               detail: '하루로 계획이 무너지지 않습니다. 내일 목표대로 돌아오면 주 평균은 유지됩니다.' };
    }
    if (kcal >= band.lo && kcal <= band.hi && remainP <= 10) {
      return { kind: 'done', tone: 'ok', text: '오늘 목표치를 다 채웠습니다.',
               detail: '칼로리도 단백질도 범위 안입니다.' };
    }
    if (remainP > 25) {
      return { kind: 'protein', tone: '',
               text: '단백질이 ' + Math.round(remainP) + 'g 남았습니다.',
               detail: '남은 끼니에 단백질 반찬을 하나 더 넣으면 채워집니다.' };
    }
    return { kind: 'ok', tone: '',
             text: remainKcal > 0 ? Math.round(remainKcal) + 'kcal 남았습니다.' : '목표 범위 안입니다.',
             detail: '단백질 ' + Math.round(p) + ' / ' + target.proteinG + 'g' };
  }

  /* --- 주간 체크인 판정 ----------------------------------------------------
   * 예전 판정은 이번 주 체중 하나를 계획선에 대 보고 **0.15kg** 만 달라도
   * "빠르다 · 느리다" 를 냈습니다. 체중은 하루에도 ±1kg 흔들립니다. 계획
   * 다음 날 집 체중계로 86.2 를 넣은 사람이 인바디 86.7 과 0.5kg 다르다는
   * 이유로 "하루 150kcal 늘리기" 를 받았습니다 — 흔들림에 반응한 제안입니다.
   *
   * 지금 규칙 (두 차례 독립 검토 + 모의실험으로 정한 판):
   *  · **체크인끼리만** 봅니다. 체크인마다 "그날 자리의 계획선과의 차이(잔차)" 를
   *    구하고, 잔차들에 **직선 추세**를 맞춥니다. 체중계와 인바디의 차이(0.5~1kg)는
   *    잔차에 똑같이 들어가 추세에는 안 나타납니다. 계획선은 주 사이를 이어서
   *    그날 자리에서 읽습니다(요일이 달라 생기는 가짜 차이가 없게).
   *  · **계획 주마다 마지막 값 하나**, 그리고 **이웃한 두 값이 5일 안이면 앞의 값을 버립니다.**
   *    일요일 · 월요일 이틀 연속을 "두 주 연속" 으로 세던 일이 없게. 주 칸이 고정이라
   *    묶음이 사슬처럼 이어지지 않습니다(바뀐 값부터 5일을 세던 판은 3~4일마다 재는
   *    사람을 끝없이 한 점으로 묶어 판정을 못 했습니다). 앱도 같은 주에 다시 저장하면
   *    그 주 값을 바꿉니다.
   *  · 판정은 체크인 4번 이상 · 3주(21일) 이상에 걸쳐 있을 때부터. 그 전엔 모으는 중.
   *    기간은 날 수로 셉니다(주로 나누면 20.999… 가 되어 딱 3주가 모자라다고 했습니다).
   *  · 추세가 그 기간 합쳐 **1kg 넘게** 계획선에서 벗어나고, 흔들림에 비해 확실할 때
   *    (기울기 ÷ 표준오차 ≥ 2.5)만 "벗어남". 흔들림 크기는 잔차에서 재되 0.35kg 밑으로는
   *    안 봅니다(점이 적을 때 우연히 딱 맞는 것을 확실하다고 믿지 않게).
   *  · **두 번 연속 체크인에서 같은 쪽으로 벗어남**일 때만 조정을 제안합니다.
   *    한 번이면 지켜봅니다.
   *    모의실험(계획대로 가는 사람, 체중 흔들림 σ 0.5kg, 12주): 예전 "±0.5kg 두 번"
   *    규칙은 30~60% 가 한 번 이상 가짜 조정을 받았고, 이 규칙은 약 5%. 주 0.5kg 감량
   *    계획에서 완전 정체는 체크인 5~6번(중앙값), 절반 정체는 7~8번이면 잡힙니다(재는 요일이
   *    ±2일 흔들릴 때). 느린 계획(주 0.2kg)은 정체가 쌓이는 속도도 느려서 더 오래 걸립니다 —
   *    흔들림과 구분할 만큼 차이가 쌓여야 하기 때문이고, 느린 계획의 정체는 그만큼 덜 급합니다.
   *  · **방향은 그 시점 계획의 단계**(trajectory[].phase — 점 k 의 단계는 k−1 → k
   *    구간의 것이라 x 를 포함하는 구간이 끝나는 점을 봅니다. 없으면 그 자리 기울기).
   *    **추세도 지금 단계 안에서만** 맞춥니다. 감량 → 유지 → 증량 계획에서 감량 때 정체한
   *    사람이 증량에 들어가 계획대로 늘자 "빨리 늘고 있다 · 150kcal 줄이기" 를 받았습니다 —
   *    감량 때 쌓인 차이가 증량 추세로 읽힌 것. 단계가 바뀌면 조정 때처럼 거기서부터 다시 봅니다.
   *    감량: 무거워지면 느림(slow), 가벼워지면 빠름(fast) · 증량: 반대 ·
   *    유지: 무거움(heavy) · 가벼움(light). 유지 단계는 **체중 자체도** 같은 쪽으로 1kg
   *    넘게 움직였을 때만 — 근육이 붙는다고 계획선이 조금씩 오르는 유지 계획에서 체중을
   *    그대로 지킨 사람에게 "더 드세요" 가 나오지 않게. 체중이 실제로 1kg 안에서 그대로면
   *    "지키고 있습니다"(held), 그렇지 않으면 "아직 확실하지 않습니다".
   *    칼로리는 **계획보다 무거워지면 −150, 가벼워지면 +150**. 유산소 +40분은 감량 중에
   *    무거워질 때만.
   *  · 식단을 70% 미만으로 지킨 주는 숫자를 건드리지 않습니다(adherence) — 먼저 봅니다.
   *  · 조정을 적용하면 그 뒤 체크인만 봅니다(plan.adjustments 의 마지막 at).
   *
   * readings: [{ week, day?, weightKg, at? }] — 오래된 것부터. day 는 계획 시작일로부터
   * 며칠째인지(planDayOf). 없으면 week×7. 날짜 → 날 수는 시간대를 타서 부르는 쪽이 셉니다.
   * devKg: 관측 기간 동안 추세로 본 **계획보다 무거워진** kg (+ 무거움, − 가벼움).
   * rateKg: 그 추세의 주당 kg. spanWeeks: 관측 기간(주).
   * ------------------------------------------------------------------------ */
  var CHECKIN_DRIFT_KG = 1.0;
  var CHECKIN_T = 2.5;
  var CHECKIN_MIN_SIGMA = 0.35;
  var CHECKIN_MIN_N = 4;
  var CHECKIN_MIN_SPAN_DAYS = 21;
  var CHECKIN_MERGE_DAYS = 5;
  var CHECKIN_KCAL_STEP = 150;
  var CHECKIN_CARDIO_MIN = 40;
  var CARDIO_NOTE_RE = / \+ 추가 유산소 주 -?\d+(\.\d+)?분 \(체크인 조정\)$/;

  function trajWeek(p, i) { return typeof p.week === 'number' ? p.week : i; }

  /** 계획선에서 그 주에 가장 가까운 점. week 칸이 없으면 자리 번호를 주차로 봅니다. */
  function trajAt(tr, wk) {
    var best = null, bestD = Infinity;
    for (var i = 0; i < tr.length; i++) {
      var d = Math.abs(trajWeek(tr[i], i) - wk);
      if (d < bestD) { best = tr[i]; bestD = d; }
    }
    return best;
  }

  /** 계획선의 체중을 x 주(소수) 자리에서 — 두 점 사이는 곧게 잇고, 끝 밖은 끝값. */
  function trajWeightAt(tr, x) {
    var pw = null, py = null;
    for (var i = 0; i < tr.length; i++) {
      var w = trajWeek(tr[i], i);
      var y = tr[i].weightKg;
      if (w === x) return y;
      if (w > x) {
        if (pw === null) return y;
        return py + (y - py) * (x - pw) / (w - pw);
      }
      pw = w; py = y;
    }
    return pw === null ? NaN : py;
  }

  /** 계획 시작일로부터 day 일째의 계획선 체중 — 화면이 판정과 같은 자리를 읽게. */
  function planWeightAt(plan, day) {
    var tr = (plan && plan.trajectory) || [];
    var d = typeof day === 'number' && isFinite(day) ? Math.max(0, day) : 0;
    return tr.length ? trajWeightAt(tr, d / 7) : null;
  }

  /** 그 자리의 계획 단계 — 'cut' · 'gain' · 'maintain'. 점 k 의 phase 는 k−1 → k 구간의 것. */
  function trajDirectionAt(tr, x) {
    var pt = null;
    for (var i = 0; i < tr.length; i++) {
      if (trajWeek(tr[i], i) > x) { pt = tr[i]; break; }
    }
    if (pt === null && tr.length) pt = tr[tr.length - 1];
    var ph = pt && pt.phase;
    if (ph === 'cut') return 'cut';
    if (ph === 'bulk') return 'gain';
    if (ph === 'maintain') return 'maintain';
    var lastW = tr.length ? trajWeek(tr[tr.length - 1], tr.length - 1) : 0;
    var a = x + 1 <= lastW ? x : x - 1, b = a + 1;
    if (a < 0) { a = 0; b = 1; }
    var slope = trajWeightAt(tr, b) - trajWeightAt(tr, a);
    return slope <= -0.1 ? 'cut' : (slope >= 0.1 ? 'gain' : 'maintain');
  }

  /** 'YYYY-MM-DD' 두 개 사이의 날 수 (음수는 0). */
  function planDayOf(startKey, dayKey) {
    var a = dateKeyUTC(startKey), b = dateKeyUTC(dayKey);
    if (a == null || b == null) return 0;
    var d = Math.round((b - a) / 86400000);
    return d <= 0 ? 0 : d;
  }
  /** 'YYYY-MM-DD' 두 개 사이의 계획 주차 (0부터, 음수는 0). */
  function planWeekOf(startKey, dayKey) {
    return Math.floor(planDayOf(startKey, dayKey) / 7);
  }
  function dateKeyUTC(k) {
    var m = /^(\d{4})-(\d{2})-(\d{2})/.exec(k == null ? '' : String(k));
    return m ? Date.UTC(+m[1], +m[2] - 1, +m[3]) : null;
  }

  /** [{x, e, d}] 에 직선을 맞춥니다. 점이 한 자리에 몰려 있으면 null.
      rawSigma: 잰 흔들림(바닥을 대기 전). spanDays: 첫 점부터 끝 점까지 날 수. */
  function checkinTrend(pts) {
    var n = pts.length, mx = 0, me = 0, i;
    for (i = 0; i < n; i++) { mx += pts[i].x; me += pts[i].e; }
    mx /= n; me /= n;
    var sxx = 0, sxy = 0;
    for (i = 0; i < n; i++) { var dx = pts[i].x - mx; sxx += dx * dx; sxy += dx * (pts[i].e - me); }
    if (!(sxx > 0)) return null;
    var slope = sxy / sxx, sse = 0;
    for (i = 0; i < n; i++) { var r = pts[i].e - (me + slope * (pts[i].x - mx)); sse += r * r; }
    var raw = n > 2 ? Math.sqrt(sse / (n - 2)) : 0;
    var sigma = raw >= CHECKIN_MIN_SIGMA ? raw : CHECKIN_MIN_SIGMA;
    var span = pts[n - 1].x - pts[0].x;
    return { slope: slope, drift: slope * span, span: span, spanDays: pts[n - 1].d - pts[0].d,
             t: slope / (sigma / Math.sqrt(sxx)), rawSigma: raw };
  }
  /** 그 점들로 "확실히 벗어남" 인가 — +1 무거워짐, −1 가벼워짐, 0 아님. */
  function checkinSide(pts) {
    if (pts.length < CHECKIN_MIN_N) return 0;
    var t = checkinTrend(pts);
    if (!t || !(t.spanDays >= CHECKIN_MIN_SPAN_DAYS)) return 0;
    if (!(Math.abs(t.drift) >= CHECKIN_DRIFT_KG) || !(Math.abs(t.t) >= CHECKIN_T)) return 0;
    return t.drift > 0 ? 1 : -1;
  }
  /** x 가 들어 있는 단계 구간이 시작하는 x. 단계 정보가 없으면 null(전부 봄).
      점 k 의 phase 는 k−1 → k 구간의 것이라, 같은 단계가 이어지는 첫 점 k 의 앞 점이 시작. */
  function phaseStartX(tr, x) {
    var g = -1, i;
    for (i = 0; i < tr.length; i++) { if (trajWeek(tr[i], i) > x) { g = i; break; } }
    if (g < 0) g = tr.length - 1;
    if (g < 0) return null;
    var ph = tr[g].phase;
    if (ph !== 'cut' && ph !== 'bulk' && ph !== 'maintain') return null;
    var k = g;
    while (k - 1 >= 0 && tr[k - 1].phase === ph) k--;
    return k >= 1 ? trajWeek(tr[k - 1], k - 1) : trajWeek(tr[0], 0);
  }

  function checkinReview(plan, readings, adherence) {
    var tr = (plan && plan.trajectory) || [];
    var out = { status: 'early', direction: null, devKg: null, rateKg: null, spanWeeks: null,
                weeks: 0, merged: 0, since: null, phaseFrom: null, held: false,
                rawOpposite: false, phaseEnding: false,
                suggestions: [], apply: null };

    /* 마지막 조정 이후만 — 그 전 체크인은 옛 칼로리로 산 주입니다. */
    var adjs = plan && Array.isArray(plan.adjustments) ? plan.adjustments : [];
    var adj = adjs.length ? adjs[adjs.length - 1] : null;
    var since = adj && typeof adj === 'object' && typeof adj.at === 'string' && adj.at ? adj.at : null;
    out.since = since;

    /* 계획 주마다 마지막 값(첫 단계), 그 대표들 중 이웃한 두 값이 5일 안이면 앞의 값을
       버립니다(둘째 단계). 둘째 단계는 대표끼리만 견주므로 사슬처럼 이어지지 않습니다.
       이상한 값은 건너뜁니다. */
    var byB = {}, bs = [], merged = 0;
    (readings || []).forEach(function (r) {
      if (!r) return;
      if (since && typeof r.at === 'string' && r.at < since) return;
      var wk = r.week, w = r.weightKg;
      if (typeof wk !== 'number' || !isFinite(wk)) return;
      if (typeof w !== 'number' || !isFinite(w) || w <= 0) return;
      wk = Math.max(0, Math.floor(wk));
      var day = typeof r.day === 'number' && isFinite(r.day) ? Math.max(0, r.day) : wk * 7;
      var b = Math.floor(day / 7);
      if (byB[b] == null) bs.push(b); else merged++;
      byB[b] = { h: w, day: day };
    });
    bs.sort(function (a, b) { return a - b; });
    var kept = [];
    bs.forEach(function (b) {
      var k = byB[b];
      if (kept.length && Math.abs(k.day - kept[kept.length - 1].day) < CHECKIN_MERGE_DAYS) {
        kept[kept.length - 1] = k; merged++;
      } else {
        kept.push(k);
      }
    });
    var n = kept.length;
    out.weeks = n;
    out.merged = merged;

    if (adherence && typeof adherence.dietPct === 'number' && adherence.dietPct < 70) {
      out.status = 'adherence';
      out.suggestions.push({ kind: 'adherence', title: '칼로리는 그대로 두고 순응도부터',
        detail: '식단 준수도가 ' + adherence.dietPct + '%입니다. 계획이 틀린 게 아니라 실행이 덜 된 상태라 칼로리를 더 줄이면 역효과입니다.' });
      return out;
    }
    if (!tr.length) {
      out.suggestions.push({ kind: 'hold', title: '계획이 없습니다',
        detail: '목표와 계획을 먼저 세우면 체크인을 계획선과 견줘 봅니다.' });
      return out;
    }
    if (n < 2) {
      out.suggestions.push(since
        ? { kind: 'hold', title: '조정 뒤 기준을 새로 잡았습니다',
            detail: '계획을 바꾼 뒤로는 그때 체크인부터 다시 봅니다.' }
        : (merged
          ? { kind: 'hold', title: '기준 체중을 다시 잡았습니다',
              detail: '같은 주(또는 5일 안)에 다시 잰 값이라 앞의 값을 이 값으로 바꿔 기준으로 씁니다.' }
          : { kind: 'hold', title: '기준 체중을 잡았습니다',
              detail: '첫 체크인은 판정하지 않습니다. 인바디와 집 체중계는 0.5~1kg 다를 수 있어서, ' +
                      '이 값부터 체크인끼리의 흐름으로 계획선과 견줘 봅니다.' }));
      return out;
    }

    /* 잔차 = 그날 체중 − 그날 자리의 계획선. 유지 단계 확인용으로 체중 그대로도. */
    var pts = [], flat = [], i;
    for (i = 0; i < n; i++) {
      var x = kept[i].day / 7;
      pts.push({ x: x, e: kept[i].h - trajWeightAt(tr, x), d: kept[i].day });
      flat.push({ x: x, e: kept[i].h, d: kept[i].day });
    }
    for (i = 0; i < n; i++) {
      if (!isFinite(pts[i].e)) {
        out.suggestions.push({ kind: 'hold', title: '판정하지 않습니다', detail: '계획선을 읽지 못했습니다.' });
        return out;
      }
    }
    var dir = trajDirectionAt(tr, pts[n - 1].x);
    out.direction = dir;
    /* 지금 단계 안의 체크인만 — 단계가 바뀌면 거기서부터 다시 봅니다. */
    var segX = phaseStartX(tr, pts[n - 1].x);
    if (segX != null && pts[0].x < segX) {
      out.phaseFrom = r1(segX);
      pts = pts.filter(function (q) { return q.x >= segX; });
      flat = flat.filter(function (q) { return q.x >= segX; });
      n = pts.length;
      out.weeks = n;
    }
    var trend = n >= 2 ? checkinTrend(pts) : null;
    if (trend) {
      out.devKg = r2(trend.drift);
      out.rateKg = r2(trend.slope);
      out.spanWeeks = r1(trend.span);
    }

    if (n < CHECKIN_MIN_N || !trend || !(trend.spanDays >= CHECKIN_MIN_SPAN_DAYS)) {
      out.status = 'collecting';
      out.suggestions.push({ kind: 'hold',
        title: out.phaseFrom != null ? '새 단계라 다시 모으는 중입니다' : '흐름을 모으는 중입니다',
        detail: (out.phaseFrom != null
                  ? '계획이 ' + ({ cut: '감량', gain: '증량', maintain: '유지' })[dir] + ' 단계로 넘어가 거기서부터 다시 봅니다. '
                  : '') +
                '판정은 3주 이상에 걸친 체크인 4번부터 합니다 — 지금 ' + n + '번 · ' +
                (trend ? r1(trend.spanDays / 7) : 0) + '주. ' +
                '한 번 한 번의 체중은 ±1kg 흔들려서, 추세가 보일 때까지 계획을 바꾸지 않습니다.' });
      return out;
    }

    /* 유지 단계는 체중 자체도 같은 쪽으로 움직였을 때만. */
    function side(p, f) {
      var s = checkinSide(p);
      if (s !== 0 && dir === 'maintain' && checkinSide(f) !== s) return 0;
      return s;
    }
    var s1 = side(pts, flat);
    var s0 = side(pts.slice(0, n - 1), flat.slice(0, n - 1));
    /* 체중을 지키고 있어서 거둔 것인가 — 계획선과는 벌어졌지만 체중 자체는 1kg 안에서 그대로. */
    var sP = checkinSide(pts);
    var rawT = checkinTrend(flat);
    var held = s1 === 0 && dir === 'maintain' && sP !== 0 &&
               !!rawT && Math.abs(rawT.drift) < CHECKIN_DRIFT_KG;
    out.held = held;
    /* 다음 주 체크인이 새 단계에 들어가는가 — 그러면 거기서 다시 모으므로 "다음 체크인에서
       정한다" 는 약속을 지킬 수 없습니다. */
    var segNext = segX == null ? null : phaseStartX(tr, pts[n - 1].x + 1);
    var ending = segNext != null && segNext !== segX;
    out.phaseEnding = ending;
    var nextTail = ending ? '이번 단계가 곧 끝나, 다음 단계에서 다시 모아 봅니다.' : '다음 체크인까지 보고 정합니다.';

    if (s1 === 0) {
      if (held) {
        out.status = 'onTrack';
        out.suggestions.push({ kind: 'hold', title: '체중을 지키고 있습니다',
          detail: '유지 기간이라 체중 자체가 그대로면 계획대로입니다. 계획선은 근육이 붙는 만큼 ' +
                  '조금씩 오르게 그려져 있어서 거기서는 벗어나 보이지만, 바꿀 이유는 없습니다.' });
      } else if (dir === 'maintain' && sP !== 0) {
        /* 계획선과는 확실히 벌어졌는데 체중 자체는 1kg 넘게 움직였고, 같은 쪽으로
           확실하지는 않은 경우 — 반대로 움직였거나(계획선이 체중보다 더 오름) 흔들림. */
        out.status = 'watch';
        var rs = checkinSide(flat);
        out.rawOpposite = rs === -sP;
        out.suggestions.push(rs === -sP
          ? { kind: 'watch', title: '바꾸지 않습니다',
              detail: '유지 기간이라 체중 자체로 봅니다. 계획선보다는 ' + (sP > 0 ? '무겁지만' : '가볍지만') +
                      ' 체중은 오히려 ' + (rs > 0 ? '늘고' : '줄고') + ' 있어서 칼로리를 바꿀 이유가 없습니다.' }
          : { kind: 'watch', title: '아직 확실하지 않습니다',
              detail: '유지 기간이라 체중 자체로 봅니다. 계획선과 벌어졌고 체중도 움직였지만, 흔들림이 커서 ' +
                      '한쪽으로 확실하지 않습니다. ' + nextTail });
      } else if (trend && Math.abs(trend.drift) >= CHECKIN_DRIFT_KG) {
        out.status = 'watch';
        out.suggestions.push(trend.rawSigma < CHECKIN_MIN_SIGMA
          ? { kind: 'watch', title: '아직 확실하지 않습니다',
              detail: '계획선에서 벗어나는 쪽으로 보이지만 아직 기간이 짧아 확실하지 않습니다. ' + nextTail }
          : { kind: 'watch', title: '아직 확실하지 않습니다',
              detail: '계획선에서 벗어나는 쪽으로 보이지만 체중이 많이 흔들려 확실하지 않습니다. ' +
                      '같은 조건(아침 공복, 화장실 다녀와서)으로 재면 더 빨리 판정할 수 있습니다.' });
      } else {
        out.status = 'onTrack';
        out.suggestions.push({ kind: 'hold', title: '계획 유지',
          detail: '체크인 ' + n + '번의 추세가 계획선과 1kg 안에서 맞습니다. 바꾸지 마세요.' });
      }
      return out;
    }
    if (s0 !== s1) {
      out.status = 'watch';
      out.suggestions.push(ending
        ? { kind: 'watch', title: '다음 단계에서 다시 봅니다',
            detail: '추세가 처음으로 계획선에서 1kg 넘게 벗어났지만 이번 단계가 곧 끝납니다. ' +
                    '다음 단계는 거기서부터 다시 모아 보고, 그때도 벗어나면 조정을 제안합니다.' }
        : { kind: 'watch', title: '한 번 더 보고 정합니다',
            detail: '추세가 처음으로 계획선에서 1kg 넘게 벗어났습니다. 다음 체크인에서도 같은 쪽이면 ' +
                    '그때 조정을 제안합니다.' });
      return out;
    }

    /* 두 번 연속 같은 쪽 — 이때만 조정합니다. */
    var heavy = s1 > 0;
    var kcal = heavy ? -CHECKIN_KCAL_STEP : CHECKIN_KCAL_STEP;
    var cardio = heavy && dir === 'cut' ? CHECKIN_CARDIO_MIN : 0;
    var detail;
    if (dir === 'cut') {
      out.status = heavy ? 'slow' : 'fast';
      detail = heavy ? '두 번 연속, 추세가 계획보다 덜 빠지고 있습니다.'
                     : '두 번 연속, 추세가 계획보다 빨리 빠지고 있습니다 — 너무 빠르면 근손실 위험이 올라갑니다.';
    } else if (dir === 'gain') {
      out.status = heavy ? 'fast' : 'slow';
      detail = heavy ? '두 번 연속, 추세가 계획보다 빨리 늘고 있습니다 — 빨리 늘면 지방도 같이 붙습니다.'
                     : '두 번 연속, 추세가 계획보다 덜 늘고 있습니다.';
    } else {
      out.status = heavy ? 'heavy' : 'light';
      detail = heavy ? '유지 기간인데 두 번 연속, 체중이 계획보다 늘고 있습니다.'
                     : '유지 기간인데 두 번 연속, 체중이 계획보다 줄고 있습니다.';
    }
    out.suggestions.push({ kind: 'kcal',
      title: '하루 ' + CHECKIN_KCAL_STEP + 'kcal ' + (kcal < 0 ? '줄이기' : '늘리기'), detail: detail });
    if (cardio) {
      out.suggestions.push({ kind: 'cardio', title: '유산소 주 ' + CHECKIN_CARDIO_MIN + '분 추가',
        detail: '칼로리만 더 줄이는 것보다 근육을 지키는 데 유리합니다.' });
    }
    out.apply = { kcalDelta: kcal, cardioMinDelta: cardio };
    return out;
  }

  /**
   * 체크인 제안을 계획에 적용한 **새 계획**. 원래 계획은 안 건드립니다.
   * 칼로리만 ±150 움직이고(탄수로 맞춤), 하한(kcalFloor) 밑으로는 안 내립니다.
   * 식단 예시(diet)는 새 칼로리로 다시 만들고, 무엇을 언제 바꿨는지 adjustments 에 남깁니다.
   * 적용할 것이 없으면 null.
   */
  function applyCheckinAdvice(plan, review, profile, week, atISO) {
    if (!plan || !plan.macros || !review || !review.apply || typeof review.apply !== 'object') return null;
    var intake = plan.macros.intakeKcal;
    if (typeof intake !== 'number' || !isFinite(intake)) return null;
    var pr = profile || {};
    var want = typeof review.apply.kcalDelta === 'number' ? review.apply.kcalDelta : 0;
    var wk = typeof week === 'number' && isFinite(week) ? week : 0;
    var tr = plan.trajectory || [];
    var pt = tr.length ? trajAt(tr, wk) : null;
    var ffm = pt && typeof pt.ffmKg === 'number' ? pt.ffmKg : null;
    var floor = kcalFloor(pr, ffm != null ? 370 + 21.6 * ffm : 0);
    var next = intake + want;
    if (want < 0) next = Math.max(next, Math.min(intake, floor));
    var delta = Math.round(next - intake);

    var m = Object.assign({}, plan.macros);
    m.intakeKcal = Math.round(intake + delta);
    if (typeof m.carbG === 'number') m.carbG = Math.max(50, Math.round(m.carbG + delta / 4));
    if (typeof m.deficitKcal === 'number') m.deficitKcal = Math.round(m.deficitKcal - delta);
    if (m.intakeKcal > 0) {
      if (typeof m.proteinG === 'number') m.pctProtein = Math.round(m.proteinG * 4 / m.intakeKcal * 100);
      if (typeof m.carbG === 'number') m.pctCarb = Math.round(m.carbG * 4 / m.intakeKcal * 100);
      if (typeof m.fatG === 'number') m.pctFat = Math.round(m.fatG * 9 / m.intakeKcal * 100);
    }

    var cardio = typeof review.apply.cardioMinDelta === 'number' ? review.apply.cardioMinDelta : 0;
    var np = Object.assign({}, plan, { macros: m });
    if (plan.workout && cardio) {
      var w = Object.assign({}, plan.workout);
      w.cardioMinPerWeek = (typeof w.cardioMinPerWeek === 'number' ? w.cardioMinPerWeek : 0) + cardio;
      np.workout = w;
    } else {
      cardio = 0;          // 운동 계획이 없으면 더할 곳이 없습니다
    }
    np.diet = dietFor(m, pr);
    np.adjustments = (Array.isArray(plan.adjustments) ? plan.adjustments : []).concat([{
      at: atISO || null, week: wk, status: review.status, kcalDelta: delta, cardioMinDelta: cardio
    }]);
    /* 유산소 설명 글(cardioPlan)도 같이 — 분만 늘고 글이 그대로면 플랜 화면에
       "주 172분" 바로 밑에 "45분 × 3회" 가 나옵니다. 더한 분은 따로 붙입니다. */
    if (cardio && typeof np.workout.cardioPlan === 'string') {
      var added = 0;
      np.adjustments.forEach(function (a) {
        if (a && typeof a.cardioMinDelta === 'number' && isFinite(a.cardioMinDelta)) added += a.cardioMinDelta;
      });
      np.workout.cardioPlan = np.workout.cardioPlan.replace(CARDIO_NOTE_RE, '') +
        ' + 추가 유산소 주 ' + added + '분 (체크인 조정)';
    }
    return { plan: np, kcalDelta: delta, cardioMinDelta: cardio, floored: delta !== want };
  }

  /* --- 유틸 -------------------------------------------------------------- */
  function avgWeeklyRate(traj, n) {
    var end = Math.min(n, traj.length - 1);
    if (end < 1) return 0;
    return r2((traj[end].weightKg - traj[0].weightKg) / end);
  }
  function avgWeeklyFat(traj, n) {
    var end = Math.min(n, traj.length - 1);
    if (end < 1) return 0;
    return r2((traj[end].bfmKg - traj[0].bfmKg) / end);
  }
  function avgWeeklySmm(traj, n) {
    var end = Math.min(n, traj.length - 1);
    if (end < 1) return 0;
    return Math.round((traj[end].smmKg - traj[0].smmKg) / end * 1000) / 1000;
  }
  function r1(x) { return Math.round(x * 10) / 10; }
  function r2(x) { return Math.round(x * 100) / 100; }
  function addWeeks(d, w) {
    var n = new Date(d.getTime());
    n.setDate(n.getDate() + Math.round(w * 7));
    return toISODate(n);
  }
  function toISODate(d) {
    var dt = (typeof d === 'string') ? new Date(d) : d;
    var m = String(dt.getMonth() + 1).padStart(2, '0');
    var day = String(dt.getDate()).padStart(2, '0');
    return dt.getFullYear() + '-' + m + '-' + day;
  }
  function daysUntil(iso, fromISO) {
    var a = new Date(iso + 'T00:00:00');
    var b = fromISO ? new Date(fromISO + 'T00:00:00') : new Date();
    return Math.round((a - b) / 86400000);
  }

  global.MB_ENGINE = {
    PAL: PAL, MUSCLE_BASE: MUSCLE_BASE, LEVEL_SPEC: LEVEL_SPEC,
    CUT_RANGE: CUT_RANGE, BULK_RANGE: BULK_RANGE, paramsAt: paramsAt,
    derive: derive, validateScan: validateScan, classifyGoal: classifyGoal, compareLevels: compareLevels,
    buildPlan: buildPlan, checkinReview: checkinReview, applyCheckinAdvice: applyCheckinAdvice,
    planWeekOf: planWeekOf, planDayOf: planDayOf, planWeightAt: planWeightAt, planDrift: planDrift,
    ffmiOf: ffmiOf, ffmiCeiling: ffmiCeiling, ffmiFactor: ffmiFactor,
    dietAdherence: dietAdherence, dietNudge: dietNudge,
    macrosFor: macrosFor, workoutFor: workoutFor, dietFor: dietFor, resolveTraining: resolveTraining,
    baseSmmRatePerWeek: baseSmmRatePerWeek,
    stepWeek: stepWeek,            // 검증 하네스(tools/validate.js)용 노출 — 로직 변경 없음
    /* 차이 검사(tools/difftest.js)용 노출 — 로직 변경 없음.
       옮긴 Dart 와 같은 답을 내는지 이 함수들을 직접 불러서 비교합니다.
       compareLevels 만으로는 어느 층에서 갈렸는지 알 수가 없습니다. */
    simulateSimultaneous: simulateSimultaneous, simulateSplit: simulateSplit,
    bestAt: bestAt, scanCurve: scanCurve, snapshot: snapshot,
    milestonesFrom: milestonesFrom, feasibility: feasibility, spanNote: spanNote,
    maintenancePlan: maintenancePlan, bottleneckNote: bottleneckNote,
    addWeeks: addWeeks, toISODate: toISODate, daysUntil: daysUntil, r1: r1
  };
})(window);
