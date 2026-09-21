/* =============================================================================
 * gen-modes-dart.js — modes.js 의 **데이터**를 Dart 로 찍어냅니다.
 *
 * modes.js 는 절반이 산문입니다: 모드 7개의 설명, 거부 문구 11개,
 * 선택 규칙 22개의 이유와 근거. 전부 화면에 그대로 나가는 글이라
 * 한 글자도 바뀌면 안 되고, 눈으로 옮기면 반드시 바뀝니다.
 *
 * 판정식(test)은 여기서 안 찍습니다 — 함수라서 데이터가 아닙니다.
 * 대신 각 항목이 들고 있는 `source` 문자열(그 판정식의 원문)을 같이
 * 찍어서, 손으로 옮긴 Dart 판정식 옆에 원문이 남게 합니다.
 * 맞는지는 tools/difftest.js 가 수천 개를 넣어 봅니다.
 *
 *   node tools/gen-modes-dart.js > packages/mybody_core/lib/modes_data.dart
 * ========================================================================== */
const { lit, loadPrototype } = require('./dart-literal');
loadPrototype('modes');
const M = global.MB_MODES;

/* 거부 규칙에는 source 칸이 없습니다. 판정식 원문을 함수 본문에서 꺼냅니다 —
   옮긴 Dart 판정식 옆에 원문이 없으면 맞는지 볼 방법이 없습니다. */
function sourceOf(fn) {
  const m = /return \(([\s\S]*)\);\s*\}\s*$/.exec(String(fn));
  return m ? m[1].trim() : null;
}


/* 규칙의 `source` 는 판정식의 **원문이라고 주장하는 문자열**입니다.
   주장일 뿐이라 어긋날 수 있고, 어긋나면 옮긴 Dart 는 실제로 도는 것이
   아니라 주석을 따라가게 됩니다. 그래서 찍기 전에 대조합니다 —
   실제로 규칙 하나를 여기 기준으로 잘못 옮겼다가 차이 검사에 걸렸습니다. */
(function assertSourcesMatch() {
  const bad = [];
  M.RULES.forEach((r, n) => { if (sourceOf(r.test) !== r.source) bad.push('RULES[' + n + ']'); });
  if (bad.length) {
    process.stderr.write('판정식과 source 가 다릅니다: ' + bad.join(', ') + '\n' +
      'modes.js 를 고치거나 source 를 맞춘 뒤 다시 돌리세요.\n');
    process.exit(1);
  }
})();

const out = [];
out.push(`/* =============================================================================
 * modes_data.dart — prototype/js/modes.js 의 데이터 (손으로 옮기지 않았습니다)
 *
 * 찍어낸 것입니다: node tools/gen-modes-dart.js
 * 화면에 그대로 나가는 글이라 한 글자도 달라지면 안 됩니다.
 *
 * 판정식(test)은 함수라서 여기 없습니다. 각 항목의 \`source\` 에 원문이
 * 남아 있고, 옮긴 Dart 판정식은 modes.dart 에 있습니다.
 * 정수도 소수(18.0)로 찍습니다 — 이유는 data.dart 와 같습니다.
 * ========================================================================== */
library;
`);
out.push('/// 측정 노이즈 바닥 (근거 문장까지 그대로).');
out.push('const Map<String, Object?> kNoise = ' + lit(M.NOISE, 0) + ';\n');
out.push('/// 몸만들기 모드 7종.');
out.push('const List<Object?> kModes = ' + lit(M.MODES, 0) + ';\n');
out.push('/// 거부 규칙 — 문구와 판정식 원문. 순서가 곧 심각도입니다.');
out.push('const List<Object?> kRefusals = ' + lit(M.REFUSALS.map(r => ({ message: r.message, source: sourceOf(r.test) })), 0) + ';\n');
out.push('/// 선택 규칙 — 순서·모드·이유·판정식 원문.');
out.push('const List<Object?> kRules = ' + lit(M.RULES.map(r => ({ order: r.order, modeId: r.modeId, reason: r.reason, source: r.source })), 0) + ';\n');
out.push('/// 오너 케이스에 대한 판단 (화면에는 안 나가고 문서로 남습니다).');
out.push('const String kOwnerVerdict = ' + lit(M.OWNER_VERDICT, 0) + ';\n');
process.stdout.write(out.join('\n'));
