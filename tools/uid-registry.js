/* =============================================================================
 * tools/uid-registry.js — 고유번호 레지스트리 생성기
 *
 *   node tools/uid-registry.js            docs/UID-REGISTRY.md 를 갱신
 *
 * 소스에서 data-uid / data-uid-label 쌍을 전부 긁어 화면·팝업별로 묶는다.
 * 손으로 관리하는 목록은 반드시 코드와 어긋나므로 생성한다.
 * ========================================================================== */
const fs = require('fs');
const path = require('path');

const SRC = path.join(__dirname, '..', 'prototype', 'js');
const OUT = path.join(__dirname, '..', 'docs', 'UID-REGISTRY.md');

const KIND = {
  P: '화면', M: '팝업', A: '토스트', B: '버튼', F: '입력',
  C: '카드', T: '탭', N: '내비', L: '리스트', G: '차트', S: '상태'
};

function walk(dir) {
  return fs.readdirSync(dir).flatMap(f => {
    const p = path.join(dir, f);
    return fs.statSync(p).isDirectory() ? walk(p) : (f.endsWith('.js') ? [p] : []);
  });
}

// uid: 'P05-B01', uidLabel: '강도 고르기'   /   uid: 'P05-B01' 단독
const RE_PAIR = /uid:\s*'([^']+)'(?:\s*\+\s*[^,]+)?\s*,\s*uidLabel:\s*'([^']*)'/g;
const RE_SOLO = /uid:\s*'([^']+)'/g;
/* 모달은 uidLabel 이 아니라 title 로 이름을 답니다 (UI.openModal 이 그걸 씁니다).
   RE_PAIR 만 보면 모달 이름을 하나도 못 읽고, 번호 재사용도 못 잡습니다. */
const RE_MODAL = /uid:\s*'(M\d{2})'\s*,\s*title:\s*'([^']*)'/g;

const found = new Map();   // uid -> {label, file}
/* 같은 번호가 서로 다른 뜻으로 두 번 선언되는 것을 잡습니다.
   found 는 Map 이라 중복이 조용히 뭉개집니다 — 그래서 여기서 따로 셉니다.
   번호를 재사용하면 그 번호에 달아 둔 피드백 메모가 엉뚱한 요소를 가리킵니다.
   모달은 화면별 스모크로 잡히지 않습니다: 서로 다른 화면에 있으면
   한 번에 같이 뜨는 일이 없기 때문입니다. */
const declared = new Map();   // uid -> Set(label)
const files = walk(SRC);

for (const f of files) {
  const src = fs.readFileSync(f, 'utf8');
  const rel = path.relative(path.join(__dirname, '..'), f);
  let m;
  RE_PAIR.lastIndex = 0;
  while ((m = RE_PAIR.exec(src))) {
    const uid = m[1].replace(/'\s*\+.*$/, '').trim();
    if (!found.has(uid) || !found.get(uid).label) found.set(uid, { label: m[2], file: rel });
    if (/^[PMA]\d{2}$/.test(uid)) {
      if (!declared.has(uid)) declared.set(uid, new Map());
      declared.get(uid).set(m[2], rel);
    }
  }
  RE_MODAL.lastIndex = 0;
  while ((m = RE_MODAL.exec(src))) {
    const uid = m[1];
    if (!found.has(uid) || !found.get(uid).label) found.set(uid, { label: m[2], file: rel });
    if (!declared.has(uid)) declared.set(uid, new Map());
    declared.get(uid).set(m[2], rel);
  }
  RE_SOLO.lastIndex = 0;
  while ((m = RE_SOLO.exec(src))) {
    const uid = m[1].trim();
    if (!found.has(uid)) found.set(uid, { label: '', file: rel });
  }
}

// 실행 중 수집한 목록이 있으면 라벨을 보강한다
const runtime = path.join(__dirname, '.shots', 'uids.json');
if (fs.existsSync(runtime)) {
  for (const r of JSON.parse(fs.readFileSync(runtime, 'utf8'))) {
    const base = r.uid.split('#')[0];
    const cur = found.get(base);
    if (!cur) found.set(base, { label: r.label, file: '(런타임)' });
    else if (!cur.label && r.label) cur.label = r.label;
  }
}

// 화면/팝업/토스트별로 묶는다
const groups = new Map();
for (const [uid, info] of found) {
  const base = uid.split('#')[0];
  const container = base.split('-')[0];
  if (!/^[PMA]\d{2}$/.test(container)) continue;
  if (!groups.has(container)) groups.set(container, []);
  groups.get(container).push({ uid: base, ...info });
}

const SCREEN_NAMES = {
  P00: '앱 셸', P01: '온보딩 · 프로필', P02: '홈 대시보드', P03: '인바디 사진 업로드',
  P04: '인바디 판독 검수', P05: '목표 설정', P06: '실현 강도 선택', P07: '플랜 결과',
  P08: '주간 체크인', P09: '진행 추적', P10: '측정 히스토리', P11: '스캔 상세',
  P12: '설정', P13: '고유번호 인덱스',
  P14: '계정', P15: '친구 (탭)', P16: '친구 한 사람',
  P17: '(회수됨 — 공유 설정은 M27/M28 모달)',
  P18: '식단 기록', P19: '음식 고르기', P20: '사진 식단 기록', P21: '식단 달성률'
};

/* 번호 재사용 검사 — 파싱 단계에서 모은 declared 로 판정합니다. */
{
  const clashes = [];
  for (const [uid, labels] of declared) {
    if (labels.size > 1) clashes.push([uid, labels]);
  }
  if (clashes.length) {
    console.error('번호가 두 가지 뜻으로 쓰이고 있습니다:\n');
    clashes.forEach(([uid, labels]) => {
      console.error('  ' + uid);
      for (const [label, file] of labels) console.error('    · ' + label + '   (' + file + ')');
    });
    console.error('\n빈 번호를 쓰세요. 번호를 재사용하면 그 번호에 달린');
    console.error('피드백 메모가 엉뚱한 요소를 가리킵니다.');
    process.exit(1);
  }
}

const containers = [...groups.keys()].sort();
const total = [...groups.values()].reduce((n, g) => n + g.length, 0);

const L = [];
L.push('# 고유번호 전체 목록');
L.push('');
L.push('> `node tools/uid-registry.js` 로 소스에서 생성됩니다. 손으로 고치지 마세요.');
L.push('');
L.push(`화면·팝업 ${containers.length}개 · 요소 ${total}개`);
L.push('');
L.push('## 번호 읽는 법');
L.push('');
L.push('```');
L.push('P06-B21');
L.push('│   │└─ 21번째 버튼');
L.push('└───┴── P06 = 실현 강도 선택 화면');
L.push('```');
L.push('');
L.push('| 접두 | 뜻 |');
L.push('|---|---|');
for (const [k, v] of Object.entries(KIND)) L.push(`| \`${k}\` | ${v} |`);
L.push('');
L.push('컨테이너(`P` 화면 · `M` 팝업 · `A` 토스트)는 앱 전체에서 유일한 번호이고,');
L.push('그 안의 요소는 소속 화면 안에서만 번호가 매겨집니다. 항상 두 마디(`P06-B21`)이고 세 마디는 없습니다.');
L.push('리스트 행처럼 개수가 변하는 것은 화면이 `#1`, `#2` 를 덧붙입니다 — 목록에는 대표 번호만 있습니다.');
L.push('');
L.push('## 화면');
L.push('');
for (const c of containers.filter(x => x[0] === 'P')) {
  const rows = groups.get(c).sort((a, b) => a.uid.localeCompare(b.uid));
  const self = rows.find(r => r.uid === c);
  L.push(`### ${c} · ${SCREEN_NAMES[c] || (self && self.label) || ''}`);
  L.push('');
  L.push('| 번호 | 종류 | 이름 |');
  L.push('|---|---|---|');
  for (const r of rows) {
    const leaf = r.uid.split('-')[1];
    const kind = KIND[leaf ? leaf[0] : r.uid[0]] || '';
    L.push(`| \`${r.uid}\` | ${kind} | ${r.label || '—'} |`);
  }
  L.push('');
}
L.push('## 팝업 · 토스트');
L.push('');
L.push('팝업은 여러 화면에서 열리므로 화면에 종속시키지 않고 전역 번호를 씁니다.');
L.push('');
for (const c of containers.filter(x => x[0] !== 'P')) {
  const rows = groups.get(c).sort((a, b) => a.uid.localeCompare(b.uid));
  const self = rows.find(r => r.uid === c);
  L.push(`### ${c} · ${(self && self.label) || ''}`);
  L.push('');
  L.push('| 번호 | 종류 | 이름 |');
  L.push('|---|---|---|');
  for (const r of rows) {
    const leaf = r.uid.split('-')[1];
    const kind = KIND[leaf ? leaf[0] : r.uid[0]] || '';
    L.push(`| \`${r.uid}\` | ${kind} | ${r.label || '—'} |`);
  }
  L.push('');
}

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, L.join('\n'));
console.log(`${OUT} — 컨테이너 ${containers.length}개, 요소 ${total}개`);
