/* =============================================================================
 * tools/gen-modes.js — 모드 레지스트리 JSON → prototype/js/modes.js 생성
 *
 *   node tools/gen-modes.js <registry.json>
 *
 * 선택 규칙의 condition 은 이미 유효한 JS 식이므로 eval 없이 함수 본문으로 굽는다.
 * 규칙이 바뀌면 JSON만 갈아끼우고 다시 돌리면 된다.
 * ========================================================================== */
const fs = require('fs');
const path = require('path');

const src = process.argv[2];
if (!src) { console.error('사용법: node tools/gen-modes.js <registry.json>'); process.exit(1); }
const R = JSON.parse(fs.readFileSync(src, 'utf8'));
const OUT = path.join(__dirname, '..', 'prototype', 'js', 'modes.js');

const VARS = ['dWeightKg', 'dSmmKg', 'dBfmKg', 'curPbfPct', 'curBmi', 'curSmmKg', 'curBfmKg',
              'curWeightKg', 'sex', 'age', 'trainingAge', 'hadPriorPeak', 'deadlineWeeks',
              'recentTrend', 'targetPbfPct'];

function preamble(indent) {
  return VARS.map(v => `${indent}var ${v} = i.${v};`).join('\n');
}
function q(s) { return JSON.stringify(s == null ? '' : String(s)); }

const L = [];
L.push('/* =============================================================================');
L.push(' * modes.js — 몸 만들기 모드 레지스트리 + 자동 선택');
L.push(' *');
L.push(' * 이 파일은 tools/gen-modes.js 가 생성합니다. 손으로 고치지 마세요.');
L.push(' *');
L.push(' * 모드는 "이름만 다른 라벨"이 아니라 서로 다른 계획이다. 각 모드는');
L.push(' * 방향(적자/잉여/유지), 공격성 a 의 허용 범위, 단백질 정책, 전략 선호,');
L.push(' * 전형적 기간, 연속 지속 한계, 그리고 "이 모드가 거절하는 것"을 갖는다.');
L.push(' * 상/중/하는 모드가 아니라 모드 안에서의 속도(기간) 손잡이다.');
L.push(' * ========================================================================== */');
L.push("(function (global) {");
L.push("  'use strict';");
L.push('');
L.push('  /* 인바디 측정 노이즈 바닥 — 이보다 작은 변화는 "변화가 있었다"고 말하지 않는다 */');
L.push('  var NOISE = {');
L.push(`    weight: ${R.noiseFloor.weightKg},`);
L.push(`    smm: ${R.noiseFloor.smmKg},`);
L.push(`    bfm: ${R.noiseFloor.bfmKg},`);
L.push(`    rationale: ${q(R.noiseFloor.rationale)}`);
L.push('  };');
L.push('');
L.push('  var MODES = [');
R.modes.forEach((m, idx) => {
  L.push('    {');
  L.push(`      id: ${q(m.id)},`);
  L.push(`      nameKo: ${q(m.nameKo)},`);
  L.push(`      aliasKo: ${q(m.aliasKo)},`);
  L.push(`      nameEn: ${q(m.nameEn)},`);
  L.push(`      oneLiner: ${q(m.oneLiner)},`);
  L.push(`      whoFor: ${q(m.whoFor)},`);
  L.push(`      notFor: ${q(m.notFor)},`);
  L.push(`      direction: ${q(m.direction)},`);
  L.push(`      aMin: ${m.aMin}, aMax: ${m.aMax},`);
  L.push(`      strategy: ${q(m.strategy)},`);
  L.push(`      proteinPerFfmMin: ${m.proteinPerFfmMin}, proteinPerFfmMax: ${m.proteinPerFfmMax},`);
  L.push(`      typicalWeeksMin: ${m.typicalWeeksMin}, typicalWeeksMax: ${m.typicalWeeksMax},`);
  L.push(`      maxContinuousWeeks: ${m.maxContinuousWeeks == null ? 'null' : m.maxContinuousWeeks},`);
  L.push(`      trainingPolicyKo: ${q(m.trainingPolicyKo)},`);
  L.push(`      expectedKo: ${q(m.expectedKo)},`);
  L.push(`      risksKo: ${q(m.risksKo)},`);
  L.push(`      exitCriteriaKo: ${q(m.exitCriteriaKo)},`);
  L.push(`      evidence: ${q(m.evidence)}`);
  L.push('    }' + (idx < R.modes.length - 1 ? ',' : ''));
});
L.push('  ];');
L.push('');
L.push('  /* 계획을 만들지 않고 막는 조건. 선택 규칙보다 먼저 평가된다. */');
L.push('  var REFUSALS = [');
R.refusals.forEach((x, idx) => {
  L.push('    {');
  L.push(`      test: function (i) {`);
  L.push(preamble('        '));
  L.push(`        return (${x.condition});`);
  L.push('      },');
  L.push(`      message: ${q(x.messageKo)}`);
  L.push('    }' + (idx < R.refusals.length - 1 ? ',' : ''));
});
L.push('  ];');
L.push('');
L.push('  /* 순서대로 평가해 처음 맞는 것을 쓴다. 마지막은 반드시 catch-all. */');
L.push('  var RULES = [');
const rules = R.selectionRules.slice().sort((a, b) => a.order - b.order);
rules.forEach((r, idx) => {
  L.push('    {');
  L.push(`      order: ${r.order},`);
  L.push(`      modeId: ${q(r.modeId)},`);
  L.push(`      reason: ${q(r.reasonKo)},`);
  L.push(`      source: ${q(r.condition)},`);
  L.push('      test: function (i) {');
  L.push(preamble('        '));
  L.push(`        return (${r.condition});`);
  L.push('      }');
  L.push('    }' + (idx < rules.length - 1 ? ',' : ''));
});
L.push('  ];');
L.push('');
L.push(`  var OWNER_VERDICT = ${q(R.ownerVerdict)};`);
L.push('');
L.push(`
  function byId(id) {
    for (var i = 0; i < MODES.length; i++) if (MODES[i].id === id) return MODES[i];
    return null;
  }

  /* 한국어 조사 교정 — 치환한 자리 바로 뒤에 붙은 조사만 손댄다.
     본문 전체를 훑으면 '증가' 같은 단어의 끝 글자를 조사로 오인한다. */
  var JOSA = {
    '이라서': ['이라서', '라서'], '라서': ['이라서', '라서'],
    '은': ['은', '는'], '는': ['은', '는'],
    '이': ['이', '가'], '가': ['이', '가'],
    '을': ['을', '를'], '를': ['을', '를'],
    '과': ['과', '와'], '와': ['과', '와'],
    '으로': ['으로', '로'], '로': ['으로', '로']
  };
  function hasFinalConsonant(s) {
    if (!s) return false;
    var c = s.charCodeAt(s.length - 1);
    if (c < 0xAC00 || c > 0xD7A3) return /[0-9]$/.test(s) ? /[0136780]$/.test(s) : true;
    return (c - 0xAC00) % 28 !== 0;
  }
  function fill(tpl, i) {
    return String(tpl).replace(/\\{(\\w+)\\}(이라서|라서|으로|로|은|는|이|가|을|를|과|와)?/g,
      function (_, k, josa) {
        var v = i[k];
        var s = (v == null) ? '—'
              : (typeof v === 'number' ? String(Math.round(v * 10) / 10) : String(v));
        if (!josa) return s;
        var pair = JOSA[josa];
        return s + (pair ? pair[hasFinalConsonant(s) ? 0 : 1] : josa);
      });
  }

  /**
   * 입력에서 모드를 고른다.
   * i = { dWeightKg, dSmmKg, dBfmKg, curWeightKg, curSmmKg, curBfmKg, curPbfPct, curBmi,
   *       sex, age, trainingAge, hadPriorPeak, deadlineWeeks, recentTrend }
   * recentTrend = { weeksSpan, dWeightKg, dSmmKg, dBfmKg } | null
   */
  function select(input) {
    var i = {};
    for (var k in input) if (Object.prototype.hasOwnProperty.call(input, k)) i[k] = input[k];
    i.NOISE = NOISE;
    if (i.targetPbfPct == null && i.curBfmKg != null && i.curWeightKg != null) {
      i.targetPbfPct = (i.curBfmKg + (i.dBfmKg || 0)) / (i.curWeightKg + (i.dWeightKg || 0)) * 100;
    }
    i.ratePct = (i.deadlineWeeks && i.curWeightKg)
      ? Math.abs(i.dWeightKg) / i.curWeightKg / i.deadlineWeeks * 100 : null;
    i.targetPbf = i.targetPbfPct;
    // 문구 치환용 파생값
    i.ffmKg = (i.dSmmKg || 0) * 1.75;          // 골격근 변화가 함의하는 제지방 변화
    i.fatKg = Math.abs(i.dBfmKg || 0);
    i.weeksSpan = i.recentTrend ? i.recentTrend.weeksSpan : null;
    i.pct = (i.recentTrend && i.curWeightKg)
      ? Math.abs(i.recentTrend.dWeightKg / i.curWeightKg * 100) : null;
    i.reason = i.hadPriorPeak ? '쉬었다 복귀한 경우'
             : (i.trainingAge === 'novice' ? '운동 입문 단계'
             : (i.curPbfPct >= (i.sex === 'male' ? 18 : 26) ? '체지방이 아직 남아 있는 상태'
             : '지금 구간'));

    // 시간 게이트: 간격이 4주 미만인 추세는 판정에 쓰지 않는다 (수분·시각 변동이 신호를 덮는다)
    var trendNote = null;
    if (i.recentTrend && i.recentTrend.weeksSpan != null && i.recentTrend.weeksSpan < 4) {
      trendNote = '최근 두 측정 간격이 ' + Math.round(i.recentTrend.weeksSpan * 7) +
                  '일이라 추세로 쓰지 않았습니다. 변화 판정은 4주 이상 간격이 필요합니다.';
      i.recentTrend = null;
    }

    for (var r = 0; r < REFUSALS.length; r++) {
      var ref = REFUSALS[r];
      var hit = false;
      try { hit = !!ref.test(i); } catch (e) { hit = false; }
      if (hit) {
        return { refused: true, message: fill(ref.message, i), mode: null, trendNote: trendNote };
      }
    }

    for (var n = 0; n < RULES.length; n++) {
      var rule = RULES[n];
      var ok = false;
      try { ok = !!rule.test(i); } catch (e) { ok = false; }
      if (ok) {
        var mode = byId(rule.modeId);
        return {
          refused: false, mode: mode, modeId: rule.modeId,
          reason: fill(rule.reason, i), ruleOrder: rule.order, ruleSource: rule.source,
          alternatives: alternativesFor(rule.modeId, i),
          trendNote: trendNote,
          subNoise: {
            weight: Math.abs(i.dWeightKg || 0) < NOISE.weight,
            smm: Math.abs(i.dSmmKg || 0) < NOISE.smm,
            bfm: Math.abs(i.dBfmKg || 0) < NOISE.bfm
          }
        };
      }
    }
    return { refused: false, mode: byId('maintain'), modeId: 'maintain',
             reason: '해당하는 규칙이 없어 유지로 둡니다.', ruleOrder: null,
             alternatives: [], trendNote: trendNote };
  }

  /** 선택되지 않았지만 "왜 이건 아닌가"를 설명해 줄 만한 모드들 */
  function alternativesFor(chosenId, i) {
    var out = [];
    MODES.forEach(function (m) {
      if (m.id === chosenId) return;
      var why = whyNot(m, i);
      if (why) out.push({ id: m.id, nameKo: m.nameKo, why: why });
    });
    return out;
  }

  function whyNot(m, i) {
    var maleGate = i.sex === 'male';
    if (m.id === 'cutting' && i.curPbfPct > (maleGate ? 18 : 26)) {
      return '체지방률 ' + Math.round(i.curPbfPct * 10) / 10 + '% 는 커팅 기준(' +
             (maleGate ? 18 : 26) + '%)보다 높습니다. 지금은 커팅이 아니라 감량입니다. ' +
             (maleGate ? 18 : 26) + '% 에 닿으면 자동으로 열립니다.';
    }
    if (m.id === 'muscleGain' && i.curPbfPct > (maleGate ? 18 : 26)) {
      return '체지방률이 높은 상태에서 증량하면 늘어나는 대부분이 지방입니다. 먼저 ' +
             (maleGate ? 18 : 26) + '% 아래로 내려가는 편이 결과가 좋습니다.';
    }
    if (m.id === 'recomp' && i.trainingAge === 'advanced' && i.curPbfPct < (maleGate ? 15 : 23)) {
      return '훈련 경력이 길고 이미 마른 상태에서는 리컴프 속도가 인바디 측정 오차보다 느립니다.';
    }
    if (m.id === 'miniCut' && (i.deadlineWeeks == null || i.deadlineWeeks > 6)) {
      return '단기커팅은 6주 안에 마감이 있을 때만 의미가 있습니다.';
    }
    if (m.id === 'recovery' && !(i.recentTrend && i.recentTrend.weeksSpan >= 8)) {
      return '최근에 긴 감량을 끝낸 기록이 없습니다. 회복모드는 감량 뒤에 오는 단계입니다.';
    }
    return null;
  }

  global.MB_MODES = {
    NOISE: NOISE, MODES: MODES, RULES: RULES, REFUSALS: REFUSALS,
    OWNER_VERDICT: OWNER_VERDICT,
    select: select, byId: byId, whyNot: whyNot
  };
})(window);`);

fs.writeFileSync(OUT, L.join('\n'));
console.log(`${OUT} — 모드 ${R.modes.length}개, 규칙 ${R.selectionRules.length}개, 거부 ${R.refusals.length}개`);
