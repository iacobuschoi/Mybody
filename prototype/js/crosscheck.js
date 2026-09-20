/* =============================================================================
 * crosscheck.js — 결과지 검산 (판독 파이프라인 1층)
 *
 * 인바디 결과지는 내부적으로 수식이 맞아떨어지는 문서입니다.
 *   제지방 = 체중 − 체지방
 *   체지방률 = 체지방 ÷ 체중
 *   체수분 + 단백질 + 무기질 + 체지방 = 체중
 *   기초대사량 ≈ 370 + 21.6 × 제지방
 * 그래서 한 칸을 잘못 읽으면 다른 칸과 어긋납니다. 이게 판독 오류를
 * 잡는 가장 강한 도구이고, OCR 엔진이 무엇이든(사람 손 · 서버 · 미래의
 * 무엇이든) 그대로 쓸 수 있습니다.
 *
 * 왜 OCR 신뢰도를 안 쓰는가
 *   시험 삼아 떠 본 신뢰도 점수는 맞은 값 24.8 에 14 점, 틀린 값 19.3 에
 *   39 점을 줬습니다. 글자를 얼마나 선명하게 봤는지는 그 숫자가 맞는지와
 *   거의 상관이 없습니다. 그래서 화면에는 신뢰도 대신 검산 상태를 띄웁니다:
 *     검산됨   — 다른 칸과 맞아떨어진다
 *     미검산   — 짝이 없어서 확인할 방법이 없다
 *     모순     — 다른 칸과 어긋난다
 *
 * engine.validateScan() 과의 관계
 *   validateScan 은 "이 측정으로 계획을 세울 수 있는가" 를 묻는 플래너의
 *   문지기입니다. 여기 run() 은 "이 결과지를 제대로 읽었는가" 를 묻습니다.
 *   질문이 달라서 따로 둡니다. 규칙이 일부 겹치지만(k 비율), 한쪽을
 *   느슨하게 고치다가 다른 쪽까지 같이 느슨해지는 일이 없습니다.
 *
 * 순수 함수입니다 — DOM · 저장소 · 시계를 건드리지 않습니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  /* 범위 검증. hard 를 벗어나면 값 자체가 틀린 것이고, soft 는 흔한 구간일
     뿐이라 벗어나도 경고까지입니다. 소수점 소실(63.4 → 634)은 hard 에서
     걸립니다. */
  var RANGE = {
    weightKg:         { hard: [25, 250],   soft: [40, 120],  label: '체중', unit: 'kg' },
    smmKg:            { hard: [8, 60],     soft: [18, 45],   label: '골격근량', unit: 'kg' },
    bfmKg:            { hard: [1, 120],    soft: [3, 50],    label: '체지방량', unit: 'kg' },
    pbfPct:           { hard: [2, 65],     soft: [5, 45],    label: '체지방률', unit: '%' },
    ffmKg:            { hard: [20, 130],   soft: [35, 75],   label: '제지방량', unit: 'kg' },
    bmi:              { hard: [10, 55],    soft: [16, 38],   label: 'BMI', unit: '' },
    tbwL:             { hard: [15, 90],    soft: [25, 55],   label: '체수분', unit: 'L' },
    proteinKg:        { hard: [3, 25],     soft: [7, 16],    label: '단백질', unit: 'kg' },
    mineralKg:        { hard: [1, 10],     soft: [2.5, 5.5], label: '무기질', unit: 'kg' },
    bmrKcal:          { hard: [700, 3500], soft: [1100, 2200], label: '기초대사량', unit: 'kcal' },
    visceralFatLevel: { hard: [1, 30],     soft: [1, 20],    label: '내장지방 레벨', unit: '' },
    whr:              { hard: [0.55, 1.30], soft: [0.70, 1.05], label: '복부지방률', unit: '' },
    inbodyScore:      { hard: [0, 100],    soft: [40, 100],  label: 'InBody 점수', unit: '점' },
    idealWeightKg:    { hard: [25, 200],   soft: [40, 110],  label: '적정체중', unit: 'kg' }
  };

  /* 스캔 사이의 변화량 상한(주당). 몸은 이보다 빨리 안 변합니다 —
     이만큼 튀었으면 판독 오류이거나 남의 결과지입니다. */
  /* 바닥은 앱의 오차 상수에서 끌어냅니다. 베껴 쓰면 어긋납니다 —
     실제로 골격근 바닥이 0.8kg 로 박혀 있었는데, 앱이 "구분할 수 없다"
     고 보는 문턱은 0.6 × √2 = 0.849kg 이었습니다. 구분할 수 없다고
     말하는 차이에 대고 "빠른 편입니다" 라고 경고한 셈입니다.
     앱이 자기 모순을 말하면 사용자는 둘 중 아무 말이나 믿게 됩니다. */
  function noise() {
    return (global.MB_MODES && global.MB_MODES.NOISE) || { weight: 1.0, smm: 0.6, bfm: 1.0 };
  }
  function floorOf(key) {
    var N = noise();
    // 두 측정의 차이라 오차가 두 번 들어옵니다 (√2)
    if (key === 'weightKg') return N.weight * Math.SQRT2;
    if (key === 'smmKg') return N.smm * Math.SQRT2;
    if (key === 'bfmKg') return N.bfm * Math.SQRT2;
    // 체지방률은 체중과 체지방에서 나오므로 따로 재지 않고 넉넉히 둡니다
    return 2.0;
  }

  var DELTA = {
    weightKg: { warn: 2.0, bad: 5.0, label: '체중', unit: 'kg' },
    smmKg:    { warn: 0.5, bad: 2.0, label: '골격근량', unit: 'kg' },
    bfmKg:    { warn: 1.5, bad: 4.0, label: '체지방량', unit: 'kg' },
    pbfPct:   { warn: 2.0, bad: 6.0, label: '체지방률', unit: '%p' }
  };

  function n(x) { return (typeof x === 'number' && isFinite(x)) ? x : null; }
  function r1(x) { return Math.round(x * 10) / 10; }
  function r2(x) { return Math.round(x * 100) / 100; }
  function fmt(x, d) { return (Math.round(x * Math.pow(10, d || 1)) / Math.pow(10, d || 1)).toFixed(d || 1); }

  /** 결과지에 인쇄되지 않았어도 다른 칸에서 끌어낼 수 있는 값들 */
  function fill(s) {
    var o = {};
    Object.keys(RANGE).forEach(function (k) { o[k] = n(s[k]); });
    // 체지방량과 체지방률은 서로를 만들 수 있습니다. 어느 쪽이 인쇄된
    // 값인지 기억해 둬야 "검산" 이 자기 자신과의 비교가 되지 않습니다.
    o._printed = {};
    Object.keys(RANGE).forEach(function (k) { o._printed[k] = n(s[k]) != null; });
    if (o.bfmKg == null && o.weightKg != null && o.pbfPct != null) {
      o.bfmKg = r1(o.weightKg * o.pbfPct / 100);
    }
    if (o.ffmKg == null && o.weightKg != null && o.bfmKg != null) {
      o.ffmKg = r1(o.weightKg - o.bfmKg);
    }
    return o;
  }

  /* ------------------------------------------------------------------ */
  /* 검산 규칙                                                           */
  /*                                                                     */
  /* 규칙 하나는 { id, label, fields, run(v, ctx) } 입니다.               */
  /* run 은 null(해당 없음) 이나 { ok, why, fix } 를 돌려줍니다.          */
  /* fix 는 { field, value } — 고칠 값을 제안만 하고, 확정은 사람이       */
  /* 합니다. 추출기가 값을 말없이 고치는 일은 없습니다.                  */
  /* ------------------------------------------------------------------ */
  var RULES = [
    {
      id: 'C1', tight: true, label: '제지방 = 체중 − 체지방',
      fields: ['ffmKg', 'weightKg', 'bfmKg'],
      run: function (v) {
        if (!v._printed.ffmKg || v.weightKg == null || v.bfmKg == null) return null;
        var calc = v.weightKg - v.bfmKg, gap = Math.abs(v.ffmKg - calc);
        return {
          ok: gap <= 0.5,
          why: '체중 ' + fmt(v.weightKg) + ' − 체지방 ' + fmt(v.bfmKg) + ' = ' + fmt(calc) +
               'kg, 결과지의 제지방 ' + fmt(v.ffmKg) + 'kg' +
               (gap <= 0.5 ? '' : ' (' + fmt(gap) + 'kg 차이)'),
          fix: gap <= 0.5 ? null : { field: 'ffmKg', value: r1(calc) }
        };
      }
    },
    {
      id: 'C2', tight: true, label: '체지방률 = 체지방 ÷ 체중',
      fields: ['pbfPct', 'bfmKg', 'weightKg'],
      run: function (v) {
        if (!v._printed.pbfPct || !v._printed.bfmKg || !(v.weightKg > 0)) return null;
        var calc = v.bfmKg / v.weightKg * 100, gap = Math.abs(v.pbfPct - calc);
        return {
          ok: gap <= 0.8,
          why: '체지방 ' + fmt(v.bfmKg) + ' ÷ 체중 ' + fmt(v.weightKg) + ' = ' + fmt(calc) +
               '%, 결과지의 체지방률 ' + fmt(v.pbfPct) + '%' +
               (gap <= 0.8 ? '' : ' (' + fmt(gap) + '%p 차이)'),
          fix: gap <= 0.8 ? null : { field: 'pbfPct', value: r1(calc) }
        };
      }
    },
    {
      id: 'C3', tight: true, label: 'BMI = 체중 ÷ 키²',
      fields: ['bmi', 'weightKg'],
      run: function (v, ctx) {
        if (!v._printed.bmi || v.weightKg == null || !(ctx.heightM > 0)) return null;
        var calc = v.weightKg / (ctx.heightM * ctx.heightM), gap = Math.abs(v.bmi - calc);
        return {
          ok: gap <= 0.5,
          why: '키 ' + Math.round(ctx.heightM * 100) + 'cm · 체중 ' + fmt(v.weightKg) +
               'kg 이면 BMI ' + fmt(calc) + ', 결과지는 ' + fmt(v.bmi) +
               (gap <= 0.5 ? '' : ' (프로필의 키가 맞는지도 확인해 주세요)'),
          fix: gap <= 0.5 ? null : { field: 'bmi', value: r1(calc) }
        };
      }
    },
    {
      id: 'C4', tight: true, label: '체수분 + 단백질 + 무기질 + 체지방 = 체중',
      fields: ['tbwL', 'proteinKg', 'mineralKg', 'bfmKg', 'weightKg'],
      run: function (v) {
        if (v.tbwL == null || v.proteinKg == null || v.mineralKg == null ||
            v.bfmKg == null || v.weightKg == null) return null;
        var sum = v.tbwL + v.proteinKg + v.mineralKg + v.bfmKg;
        var gap = Math.abs(sum - v.weightKg);
        return {
          ok: gap <= 0.8,
          why: fmt(v.tbwL) + ' + ' + fmt(v.proteinKg) + ' + ' + fmt(v.mineralKg) + ' + ' +
               fmt(v.bfmKg) + ' = ' + fmt(sum) + ', 체중 ' + fmt(v.weightKg) + 'kg' +
               (gap <= 0.8 ? '' : ' (' + fmt(gap) + 'kg 차이)'),
          fix: null      // 넷 중 어느 칸이 틀렸는지 이 규칙만으로는 모릅니다
        };
      }
    },
    {
      id: 'C5', tight: false, label: '체수분 ≈ 제지방의 73%',
      fields: ['tbwL', 'ffmKg'],
      run: function (v) {
        if (v.tbwL == null || !(v.ffmKg > 0)) return null;
        var ratio = v.tbwL / v.ffmKg;
        return {
          ok: ratio >= 0.66 && ratio <= 0.80,
          why: '체수분 ' + fmt(v.tbwL) + 'L ÷ 제지방 ' + fmt(v.ffmKg) + 'kg = ' +
               Math.round(ratio * 100) + '% (보통 70~76%)',
          fix: null
        };
      }
    },
    {
      id: 'C6', tight: false, label: '골격근은 제지방 안에 있다',
      fields: ['smmKg', 'ffmKg'],
      run: function (v) {
        if (v.smmKg == null || !(v.ffmKg > 0)) return null;
        var k = v.smmKg / v.ffmKg;
        return {
          ok: k >= 0.45 && k <= 0.65,
          why: '골격근 ' + fmt(v.smmKg) + ' ÷ 제지방 ' + fmt(v.ffmKg) + ' = ' +
               Math.round(k * 100) + '% (사람은 45~65% 안에 들어옵니다)' +
               (k > 1 ? ' — 골격근이 제지방보다 클 수는 없습니다' : ''),
          fix: null
        };
      }
    },
    {
      id: 'C9', tight: false, label: '기초대사량 ≈ 370 + 21.6 × 제지방',
      fields: ['bmrKcal', 'ffmKg'],
      run: function (v) {
        if (v.bmrKcal == null || !(v.ffmKg > 0)) return null;
        var calc = 370 + 21.6 * v.ffmKg;
        var off = Math.abs(v.bmrKcal - calc) / calc;
        return {
          ok: off <= 0.12,
          why: '제지방 ' + fmt(v.ffmKg) + 'kg 이면 ' + Math.round(calc) + 'kcal 근처, 결과지는 ' +
               Math.round(v.bmrKcal) + 'kcal',
          fix: off <= 0.12 ? null : { field: 'bmrKcal', value: Math.round(calc) }
        };
      }
    },
    {
      id: 'CK', tight: false, label: '골격근 비율이 지난 측정과 이어진다',
      fields: ['smmKg'],
      /* 골격근량은 결과지 안에 짝이 없습니다. 다른 값은 서로 검산되는데
         골격근만 홀로 서 있어서, 한 자리를 잘못 읽어도 등식이 하나도
         안 깨집니다. 실측으로 확인해 보니 체중·체지방을 고정한 채
         골격근을 23.4~43.3kg 훑어도 전부 통과했습니다(폭 19.9kg).
         그 안에서 31kg 과 40kg 의 목표일 차이는 2년 4개월입니다.

         그런데 k = 골격근/제지방 은 한 사람 안에서 아주 안정적입니다.
         주인 실측 3회가 0.56829 / 0.56753 / 0.56822 (폭 0.00076),
         직전 k 로 다음을 예측한 오차가 62일 간격에도 0.05kg 이었습니다.
         그래서 지난 측정이 있으면 그걸 골격근의 짝으로 씁니다. */
      run: function (v, ctx) {
        var p = ctx.prev;
        if (!p || v.smmKg == null || !(v.ffmKg > 0)) return null;
        if (!(p.ffmKg > 0) || !(p.smmKg > 0)) return null;
        var expect = p.smmKg / p.ffmKg * v.ffmKg;
        // 기본 1.2kg + 한 달마다 0.25kg. k 는 훈련으로 아주 천천히 오릅니다.
        /* 간격을 모르면 가장 너그러운 허용치를 씁니다.
           언제 잰 건지 모르면 몸이 얼마나 변할 수 있었는지도 모릅니다.
           그렇다고 검사를 통째로 끄면, k 검산이 잡으라고 있는 자릿수
           오독(37.9 → 73.9)까지 같이 놓칩니다. 그건 6개월이 지나도
           일어날 수 없는 값이라 느슨한 허용치로도 잡힙니다.
           간격이 0인 경우(같은 시각 두 측정)는 반대로 제일 빡빡해야
           맞지만, 바닥을 1.2kg 로 둡니다 — 그 아래는 사람 몸의 차이가
           아니라 판독 오류입니다. */
        var tol = ctx.gapKnown
          ? Math.min(3.0, 1.2 + (ctx.gapDays / 30) * 0.25)
          : 3.0;
        var gap = Math.abs(v.smmKg - expect);
        return {
          ok: gap <= tol,
          why: '지난 측정(' + (ctx.gapKnown ? gapWord(ctx.signedDays) : '날짜 모름') + ')의 비율로 보면 ' +
               fmt(expect) + 'kg 근처, 이번 판독은 ' + fmt(v.smmKg) + 'kg' +
               (gap <= tol ? '' : ' (' + fmt(gap) + 'kg 차이)'),
          fix: gap <= tol ? null : { field: 'smmKg', value: r1(expect) }
        };
      }
    }
  ];

  /* ------------------------------------------------------------------ */
  /* 자릿수 복구 제안                                                    */
  /*                                                                     */
  /* 모순이 난 칸에 대해 흔한 오독을 되돌려 보고, 되돌린 뒤에 검산이     */
  /* 전부 통과하는 후보가 "딱 하나" 일 때만 제안합니다. 둘 이상이면      */
  /* 무엇이 맞는지 모르는 것이고, 그 상태에서 하나를 고르는 것은         */
  /* 추측입니다.                                                         */
  /* ------------------------------------------------------------------ */
  function repairCandidates(x) {
    var out = [], seen = {};
    function add(y) {
      if (!isFinite(y) || y <= 0) return;
      var k = String(r2(y));
      if (k === String(r2(x)) || seen[k]) return;
      seen[k] = 1; out.push(r2(y));
    }
    add(x / 10); add(x * 10);                 // 소수점 한 칸 (634 → 63.4)
    var s = String(x).replace('.', '');
    if (s.length >= 2) {                       // 앞 두 자리 자리바꿈 (53.2 → 35.2)
      var sw = s[1] + s[0] + s.slice(2);
      var dot = String(x).indexOf('.');
      add(parseFloat(dot < 0 ? sw : sw.slice(0, dot) + '.' + sw.slice(dot)));
    }
    [['8', '3'], ['3', '8'], ['5', '6'], ['6', '5'],
     ['1', '7'], ['7', '1'], ['0', '8'], ['8', '0'],
     ['4', '9'], ['9', '4']].forEach(function (p) {   // 흔한 글자 혼동
      var t = String(x).split(p[0]).join(p[1]);
      if (t !== String(x)) add(parseFloat(t));
    });
    return out;
  }

  /* ------------------------------------------------------------------ */
  /* 본체                                                                */
  /* ------------------------------------------------------------------ */

  /**
   * @param {object} scan     검수 중인 값들 (review 화면의 편집 중 상태 그대로)
   * @param {object} profile  키·성별 (BMI 검산과 체지방률 상식에 필요)
   * @param {object} prevScan 직전 확정 스캔 (없으면 null)
   * @returns {{checks:Array, fields:Object, status:string, counts:Object, suggestions:Array}}
   */
  function run(scan, profile, prevScan) {
    scan = scan || {};
    profile = profile || {};
    var v = fill(scan);
    var ctx = {
      heightM: profile.heightCm > 0 ? profile.heightCm / 100 : 0,
      sex: profile.sex || null,
      prev: prevScan ? fill(prevScan) : null,
      gapDays: 0,
      signedDays: 0,
      gapKnown: false
    };
    if (prevScan && scan.measuredAt && prevScan.measuredAt) {
      var g = (Date.parse(scan.measuredAt) - Date.parse(prevScan.measuredAt)) / 86400000;
      /* 부호를 버리면 안 됩니다. 예전에는 Math.abs 를 써서, 지난 기록을
         나중에 채워 넣는 경우(backfill)에 "지난 측정 80일 전" 이라고
         했습니다 — 실제로는 80일 뒤 측정이었습니다. */
      ctx.gapKnown = isFinite(g);
      ctx.signedDays = ctx.gapKnown ? g : 0;
      ctx.gapDays = Math.abs(ctx.signedDays);
    }
    /* 두 측정의 시각이 완전히 같아도 검산을 끕니다 — 였습니다.
       그런데 시각이 같은 두 측정은 정확히 "같은 결과지를 두 번 넣었거나
       남의 결과지" 인 경우라, 검사가 제일 필요한 자리입니다. 끄는 대신
       허용치에 바닥을 둡니다(아래 tol 과 weeks). */
    if (ctx.prev && !isFinite(ctx.gapDays)) ctx.prev = null;

    var checks = [], fields = {}, counts = { pass: 0, fail: 0, skip: 0 };

    /* 1차: 판정만 모읍니다. 어느 칸이 틀렸는지는 전체를 봐야 압니다. */
    var raw = [];
    RULES.forEach(function (rule) {
      var r = rule.run(v, ctx);
      if (!r) { counts.skip++; return; }
      raw.push({ rule: rule, r: r });
    });
    var suspect = blame(raw.map(function (x) {
      return { ok: x.r.ok, tight: x.rule.tight, fields: x.rule.fields };
    }), v);

    raw.forEach(function (x) {
      var rule = x.rule, r = x.r;
      checks.push({ id: rule.id, label: rule.label, ok: r.ok, why: r.why,
                    fields: rule.fields.slice(), fix: usableFix(rule, r.fix, v, suspect),
                    suspect: suspect });
      if (r.ok) counts.pass++; else counts.fail++;
      /* 결과지에 인쇄된 칸만 상태를 받습니다.
         제지방은 보통 인쇄되지 않아서 체중 − 체지방으로 만들어 씁니다.
         그런데 그건 우리가 한 산수지 확인이 아닙니다. 비어 있는 칸에
         초록 "검산됨" 점이 찍히면, 사용자는 넣지도 않은 값이 확인됐다고
         읽습니다. 파생값은 계산에는 쓰되 상태는 안 붙입니다. */
      /* 깨졌을 때는 계산된 칸을 만든 칸들까지 짚습니다(realFields).
         통과했을 때는 안 그럽니다 — 계산된 값으로 통과한 것은 그 칸을
         확인해 준 것이 아니라 우리 산수가 맞아떨어진 것뿐이고,
         그걸로 초록 점을 찍으면 넣지도 않은 값이 확인됐다고 읽힙니다. */
      (r.ok ? rule.fields : realFields(rule, v)).forEach(function (f) {
        if (v[f] == null || !v._printed[f]) return;
        if (!r.ok) fields[f] = 'conflict';
        else if (fields[f] !== 'conflict') fields[f] = 'verified';
      });
    });

    /* 범위 — 검산은 아니지만 같은 목록에 올립니다. 사용자에게는
       "이 칸이 이상하다" 가 한 줄로 보이는 편이 낫습니다. */
    var rangeIssues = [];
    Object.keys(RANGE).forEach(function (k) {
      var x = n(scan[k]);
      if (x == null) return;
      var R = RANGE[k];
      if (x < R.hard[0] || x > R.hard[1]) {
        rangeIssues.push({ field: k, level: 'bad',
          why: R.label + ' ' + fmt(x, dec(k)) + R.unit + ' 은 사람의 값이 아닙니다 (' +
               R.hard[0] + '~' + R.hard[1] + R.unit + ').' });
        fields[k] = 'conflict';
      } else if (x < R.soft[0] || x > R.soft[1]) {
        rangeIssues.push({ field: k, level: 'warn',
          why: R.label + ' ' + fmt(x, dec(k)) + R.unit + ' 은 흔한 구간(' +
               R.soft[0] + '~' + R.soft[1] + R.unit + ') 밖입니다. 맞으면 그대로 두세요.' });
      }
    });

    /* 체지방률 상식 — 성별을 알 때만 */
    if (ctx.sex && v.pbfPct != null) {
      var lim = ctx.sex === 'female' ? [10, 55] : [3, 45];
      if (v.pbfPct < lim[0] || v.pbfPct > lim[1]) {
        rangeIssues.push({ field: 'pbfPct', level: 'bad',
          why: '체지방률 ' + fmt(v.pbfPct) + '% 는 ' +
               (ctx.sex === 'female' ? '여성' : '남성') + '에게 나올 수 없는 값입니다. ' +
               '프로필의 성별이 맞는지도 확인해 주세요.' });
        fields.pbfPct = 'conflict';
      }
    }

    /* 스캔 간 변화량 — 하루 만에 골격근 3kg 이 붙지는 않습니다 */
    var deltaIssues = [];
    /* 변화량 검사는 "주당 얼마" 가 기준이라, 며칠이 지났는지 모르면
       아무 말도 할 수 없습니다. k 검산과 달리 여기서는 건너뜁니다. */
    if (ctx.prev && ctx.gapKnown) {
      var weeks = Math.max(ctx.gapDays / 7, 0.15);     // 같은 날이어도 최소치를 둡니다
      Object.keys(DELTA).forEach(function (k) {
        var a = ctx.prev[k], b = v[k];
        if (a == null || b == null) return;
        var d = b - a, ad = Math.abs(d);
        var D = DELTA[k];
        var fl = floorOf(k);
        var warnAt = Math.max(fl, D.warn * weeks);
        var badAt = Math.max(fl * 2.5, D.bad * weeks);
        if (ad > badAt) {
          deltaIssues.push({ field: k, level: 'bad',
            why: D.label + '이 ' + spanWord(ctx.gapDays) + ' ' +
                 (d > 0 ? '+' : '−') + fmt(ad, dec(k)) + D.unit + ' 움직였습니다. ' +
                 '몸이 이 속도로 변하지는 않습니다 — 판독 오류이거나 다른 사람의 결과지입니다.' });
          fields[k] = 'conflict';
        } else if (ad > warnAt) {
          deltaIssues.push({ field: k, level: 'warn',
            why: D.label + ' ' + (d > 0 ? '+' : '−') + fmt(ad, dec(k)) + D.unit +
                 ' (' + (Math.round(ctx.gapDays) >= 1 ? Math.round(ctx.gapDays) + '일' : '같은 날') +
                 '). 빠른 편입니다 — 맞는지 한 번 보세요.' });
        }
      });
    }

    /* 모순 난 칸에 대한 복구 제안 */
    var suggestions = [];
    Object.keys(fields).forEach(function (k) {
      if (fields[k] !== 'conflict') return;
      var x = n(scan[k]);
      if (x == null) return;
      var before = failCount(scan, profile, prevScan, null, null);
      var good = [];
      repairCandidates(x).forEach(function (cand) {
        if (failCount(scan, profile, prevScan, k, cand) === 0 && before > 0) good.push(cand);
      });
      if (good.length === 1) {
        suggestions.push({ field: k, from: x, to: good[0],
          why: obj(RANGE[k] ? RANGE[k].label : k) + ' ' + fmt(good[0], dec(k)) +
               (RANGE[k] ? RANGE[k].unit : '') + ' 로 보면 검산이 전부 맞아떨어집니다.' });
      }
    });

    var status = counts.fail > 0 ||
                 rangeIssues.some(isBad) || deltaIssues.some(isBad) ? 'conflict'
               : (rangeIssues.length || deltaIssues.length) ? 'review'
               : counts.pass > 0 ? 'ok' : 'review';

    /* 용의자를 못 고른 채 등식이 깨졌으면, 관련된 칸들을 알려 줍니다.
       "이 중 하나가 틀렸는데 결과지만으로는 어느 것인지 모릅니다" 가
       우리가 아는 전부이고, 그걸 그대로 말하는 편이 낫습니다. */
    var involved = null;
    if (!suspect && counts.fail > 0) {
      var seen2 = {}, list2 = [];
      checks.forEach(function (c) {
        if (c.ok) return;
        realFields(c, v).forEach(function (f) {
          if (v[f] == null || !v._printed[f] || seen2[f]) return;
          seen2[f] = 1; list2.push(f);
        });
      });
      if (list2.length > 1) involved = list2;
    }

    return { checks: checks, fields: fields, counts: counts, status: status,
             suspect: suspect, involved: involved,
             rangeIssues: rangeIssues, deltaIssues: deltaIssues, suggestions: suggestions };
  }

  /* 고침 제안을 내보낼지 말지.
   *
   * 검산 하나가 깨졌을 때 "그럼 이 칸을 이 값으로" 라고 말할 수는 있는데,
   * 그 값은 같은 식의 나머지 칸에서 나옵니다. 나머지가 이미 망가져
   * 있으면 제안도 같이 망가집니다. 실제로 체중을 867 로 잘못 넣었더니
   * "골격근량을 481.3kg 로 고치기" 버튼이 떴습니다. 누르면 그때부터는
   * 두 칸이 틀립니다.
   *
   * 그래서 두 가지를 봅니다:
   *   (가) 제안하는 값 자체가 사람의 값인가
   *   (나) 이 식이 기대는 다른 칸들이 사람의 값인가
   * 둘 중 하나라도 아니면 제안하지 않습니다. 경고는 그대로 뜹니다 —
   * 무엇이 어긋났는지는 말해 주되, 고치는 방향은 짐작하지 않습니다.
   */
  function usableFix(rule, fix, v, suspect) {
    if (!fix) return null;
    /* 용의자가 정해졌을 때만 고침을 내놓습니다.
       용의자가 없다는 것은 "어느 칸이 틀렸는지 이 결과지만으로는 모른다"
       는 뜻입니다. 예를 들어 체중과 체지방량 중 하나가 틀렸는데 BMI 나
       체수분이 인쇄돼 있지 않으면, 둘을 가를 증인이 없습니다. 그때 아무
       칸이나 고치라고 하면 맞던 것을 틀린 것에 맞추게 됩니다.
       모르면 안 고칩니다 — 무엇이 어긋났는지는 그대로 말해 줍니다. */
    if (fix.field !== suspect) return null;
    var R = RANGE[fix.field];
    if (R && (fix.value < R.hard[0] || fix.value > R.hard[1])) return null;
    var sane = rule.fields.every(function (f) {
      if (f === fix.field) return true;
      var x = v[f];
      if (x == null) return true;
      var F = RANGE[f];
      return !F || (x >= F.hard[0] && x <= F.hard[1]);
    });
    return sane ? fix : null;
  }

  /* 어느 칸이 틀렸는지 찾아내기.
   *
   * 등식 하나가 깨졌을 때 "이 칸을 이 값으로" 라고 말하려면, 먼저
   * 어느 칸이 틀렸는지 알아야 합니다. 등식만 보고는 모릅니다 —
   * 제지방 = 체중 − 체지방 이 안 맞으면 셋 중 아무거나 틀린 것입니다.
   *
   * 실제로 이래서 나쁜 일이 났습니다. 체지방량만 23.0 으로 잘못 넣었더니
   * 화면이 "제지방을 63.7 로" 와 "체지방률을 26.5% 로" 를 같이 내놨습니다.
   * 둘 다 제대로 읽은 칸이고, 누르면 틀린 칸이 하나에서 둘이 됩니다.
   *
   * 다른 등식을 증인으로 씁니다.
   *   · 깨진 식에만 나오고 맞은 식에는 안 나오는 칸 = 용의자
   *   · 맞은 식에 한 번이라도 나오면 다른 칸이 그 값을 뒷받침하는 것
   * 용의자가 하나로 좁혀지고, 깨진 식들이 그 칸의 값에 대해 같은 답을
   * 내놓을 때만 고침을 제안합니다. 답이 갈리면 아무 말도 안 합니다 —
   * 모르는 것을 아는 척하지 않습니다.
   */
  /* 규칙이 가리키는 칸을 "사람이 실제로 넣은 칸" 으로 바꿉니다.
   *
   * 제지방(ffmKg)과 체지방량(bfmKg)은 결과지에 안 찍혀 있으면 다른 칸에서
   * 계산합니다. 그런데 어긋났다고 짚을 때는 계산된 칸의 이름을 댔습니다 —
   * 사람은 그 칸을 화면에서 고칠 수가 없고(원래 없는 칸이고), 그래서
   * 애먼 칸을 고치게 됩니다.
   *
   * 실제로 이랬습니다. 체지방량 칸에 체지방'률' 32.2 를 잘못 넣으면
   * (결과지에서 제일 흔한 실수이고, 이 앱이 두 번이나 경고하는 실수)
   * 제지방이 61.4 − 32.2 = 29.2 로 계산되고, 골격근 23.1 ÷ 29.2 = 79%
   * 가 범위를 벗어납니다. 화면은 "골격근량이 어긋납니다" 라고 빨간 줄을
   * 골격근 칸에 그었습니다. 사진을 다시 봐도 골격근은 맞으니, 사용자는
   * 맞는 값을 틀린 값에 맞춰 고치거나 그냥 저장합니다.
   *
   * 계산된 칸이 걸리면 그 칸을 만든 칸들을 같이 올립니다. */
  function sourcesOf(f, v) {
    if (f === 'ffmKg' && !v._printed.ffmKg) {
      return ['weightKg', 'bfmKg'].filter(function (k) { return v[k] != null; });
    }
    if (f === 'bfmKg' && !v._printed.bfmKg) {
      return ['weightKg', 'pbfPct'].filter(function (k) { return v[k] != null; });
    }
    return [f];
  }
  function realFields(c, v) {
    var out = [], seen = {};
    c.fields.forEach(function (f) {
      sourcesOf(f, v).forEach(function (k) {
        if (!seen[k]) { seen[k] = 1; out.push(k); }
      });
    });
    return out;
  }

  function blame(checks, v) {
    var broke = {}, ok = {};
    checks.forEach(function (c) {
      realFields(c, v).forEach(function (f) {
        if (v[f] == null) return;
        /* 통과한 검사가 면죄부가 되려면 그 검사가 값을 좁게 묶어야
           합니다. 등식(제지방 = 체중 − 체지방)은 한 값만 허용하니
           증인이 됩니다. 범위 검사(골격근/제지방이 45~65%)는 폭이
           넓어서, 틀린 값도 그 안에 들어옵니다.
           실제로 제지방을 66.7 대신 60.0 으로 넣었더니 C6 이 통과해서
           제지방이 면죄부를 받고, 범인을 못 찾았습니다. */
        if (c.ok) { if (c.tight) ok[f] = (ok[f] || 0) + 1; }
        else broke[f] = (broke[f] || 0) + 1;
      });
    });
    var best = null, bestN = 0, tie = false;
    Object.keys(broke).forEach(function (f) {
      if (ok[f]) return;                       // 다른 식이 이 칸을 뒷받침합니다
      if (broke[f] > bestN) { best = f; bestN = broke[f]; tie = false; }
      else if (broke[f] === bestN) { tie = true; }
    });
    return tie ? null : best;
  }

  function isBad(x) { return x.level === 'bad'; }

  function dec(k) { return (k === 'whr') ? 2 : (k === 'bmrKcal' || k === 'inbodyScore' || k === 'visceralFatLevel' ? 0 : 1); }

  /* 받침 있으면 '을', 없으면 '를'.
     영문 약어는 읽는 소리로 정합니다 — BMI 는 "비엠아이" 라 '를',
     WHR 은 "더블유에이치알" 이라 '을'. 글자만 봐서는 알 수 없어서
     쓰는 것만 적어 둡니다. */
  var OBJ_LATIN = { BMI: '를', WHR: '을', SMM: '을', BFM: '을', FFM: '을', TBW: '를', BMR: '을' };

  function obj(word) {
    var w = String(word);
    if (OBJ_LATIN[w]) return w + OBJ_LATIN[w];
    var c = w.charCodeAt(w.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return w + '을';             // 모르는 글자는 안전한 쪽
    return w + (((c - 0xAC00) % 28) ? '을' : '를');
  }

  /** "19일 만에" / "같은 날에" (간격은 크기만 쓰므로 절댓값) */
  function spanWord(days) {
    var d = Math.round(Math.abs(days));
    return d >= 1 ? d + '일 만에' : '같은 날에';
  }

  /** "19일 전" / "80일 뒤" / "같은 날" — 부호가 방향입니다. */
  function gapWord(signed) {
    var d = Math.round(signed);
    if (d >= 1) return d + '일 전';
    if (d <= -1) return Math.abs(d) + '일 뒤';
    return '같은 날';
  }

  /** 한 칸을 바꿔 끼우고 검산이 몇 개 깨지는지 — 복구 제안이 쓰는 저울 */
  function failCount(scan, profile, prevScan, field, value) {
    var s2 = {};
    Object.keys(scan).forEach(function (k) { s2[k] = scan[k]; });
    if (field) s2[field] = value;
    var v = fill(s2);
    var ctx = {
      heightM: profile && profile.heightCm > 0 ? profile.heightCm / 100 : 0,
      sex: (profile && profile.sex) || null,
      prev: prevScan ? fill(prevScan) : null,
      gapDays: 0
    };
    if (prevScan && s2.measuredAt && prevScan.measuredAt) {
      var g = (Date.parse(s2.measuredAt) - Date.parse(prevScan.measuredAt)) / 86400000;
      ctx.gapDays = isFinite(g) ? Math.abs(g) : 0;
    }
    if (ctx.prev && !(ctx.gapDays > 0)) ctx.prev = null;
    var bad = 0;
    RULES.forEach(function (rule) {
      var r = rule.run(v, ctx);
      if (r && !r.ok) bad++;
    });
    Object.keys(RANGE).forEach(function (k) {
      var x = n(s2[k]);
      if (x == null) return;
      if (x < RANGE[k].hard[0] || x > RANGE[k].hard[1]) bad++;
    });
    return bad;
  }

  /** 한 칸의 상태를 한국어 한 단어로 */
  function stateLabel(state) {
    return state === 'verified' ? '검산됨'
         : state === 'conflict' ? '모순' : '미검산';
  }

  global.MB_CHECK = {
    run: run, RANGE: RANGE, DELTA: DELTA, RULES: RULES,
    stateLabel: stateLabel, repairCandidates: repairCandidates, obj: obj
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = global.MB_CHECK;
})(typeof window !== 'undefined' ? window : globalThis);
