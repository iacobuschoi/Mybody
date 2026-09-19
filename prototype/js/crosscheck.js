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
  var DELTA = {
    weightKg: { warn: 2.0, bad: 5.0, floorWarn: 1.5, label: '체중', unit: 'kg' },
    smmKg:    { warn: 0.5, bad: 2.0, floorWarn: 0.8, label: '골격근량', unit: 'kg' },
    bfmKg:    { warn: 1.5, bad: 4.0, floorWarn: 1.5, label: '체지방량', unit: 'kg' },
    pbfPct:   { warn: 2.0, bad: 6.0, floorWarn: 2.0, label: '체지방률', unit: '%p' }
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
      id: 'C1', label: '제지방 = 체중 − 체지방',
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
      id: 'C2', label: '체지방률 = 체지방 ÷ 체중',
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
      id: 'C3', label: 'BMI = 체중 ÷ 키²',
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
      id: 'C4', label: '체수분 + 단백질 + 무기질 + 체지방 = 체중',
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
      id: 'C5', label: '체수분 ≈ 제지방의 73%',
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
      id: 'C6', label: '골격근은 제지방 안에 있다',
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
      id: 'C9', label: '기초대사량 ≈ 370 + 21.6 × 제지방',
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
      id: 'CK', label: '골격근 비율이 지난 측정과 이어진다',
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
        var tol = Math.min(3.0, 1.2 + (ctx.gapDays / 30) * 0.25);
        var gap = Math.abs(v.smmKg - expect);
        return {
          ok: gap <= tol,
          why: '지난 측정(' + gapWord(ctx.gapDays) + ')의 비율로 보면 ' +
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
      gapDays: 0
    };
    if (prevScan && scan.measuredAt && prevScan.measuredAt) {
      var g = (Date.parse(scan.measuredAt) - Date.parse(prevScan.measuredAt)) / 86400000;
      ctx.gapDays = isFinite(g) ? Math.abs(g) : 0;
    }
    // 간격을 모르면 k 검산의 허용치를 정할 수 없습니다. 0 으로 두면
    // 가장 빡빡한 허용치라 멀쩡한 값이 모순으로 찍힙니다.
    if (ctx.prev && !(ctx.gapDays > 0)) ctx.prev = null;

    var checks = [], fields = {}, counts = { pass: 0, fail: 0, skip: 0 };

    RULES.forEach(function (rule) {
      var r = rule.run(v, ctx);
      if (!r) { counts.skip++; return; }
      checks.push({ id: rule.id, label: rule.label, ok: r.ok, why: r.why,
                    fields: rule.fields.slice(), fix: usableFix(rule, r.fix, v) });
      if (r.ok) counts.pass++; else counts.fail++;
      rule.fields.forEach(function (f) {
        if (v[f] == null) return;
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
    if (ctx.prev && ctx.gapDays > 0) {
      var weeks = Math.max(ctx.gapDays / 7, 0.15);     // 하루 미만도 최소치를 둡니다
      Object.keys(DELTA).forEach(function (k) {
        var a = ctx.prev[k], b = v[k];
        if (a == null || b == null) return;
        var d = b - a, ad = Math.abs(d);
        var D = DELTA[k];
        var warnAt = Math.max(D.floorWarn, D.warn * weeks);
        var badAt = Math.max(D.floorWarn * 2.5, D.bad * weeks);
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

    return { checks: checks, fields: fields, counts: counts, status: status,
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
  function usableFix(rule, fix, v) {
    if (!fix) return null;
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

  /** "19일 만에" / "같은 날에" */
  function spanWord(days) {
    var d = Math.round(days);
    return d >= 1 ? d + '일 만에' : '같은 날에';
  }

  /** "19일 전" / "같은 날" — 0일 전이라는 말은 없습니다. */
  function gapWord(days) {
    var d = Math.round(days);
    return d >= 1 ? d + '일 전' : '같은 날';
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
