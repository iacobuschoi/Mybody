/* =============================================================================
 * tools/workspaces.js — 판독 키의 워크스페이스를 찾아서 넣어 줍니다
 *
 *   node tools/workspaces.js              쓸 수 있는 워크스페이스를 보여줍니다
 *   node tools/workspaces.js --set        그중 하나를 골라 서버 설정에 넣습니다
 *   node tools/workspaces.js --set=wrkspc_...   번호를 직접 넣습니다
 *   node tools/workspaces.js --create=이름      워크스페이스를 만들고 바로 넣습니다
 *   node tools/workspaces.js --clear      워크스페이스 설정을 비웁니다
 *
 * 왜 있나
 *   주인이 만든 판독 키가 어느 워크스페이스에도 안 묶여 있으면, 앤트로픽은
 *   요청마다 "어느 워크스페이스로 청구할지" 를 헤더로 말해 달라고 합니다.
 *   안 보내면 400 입니다. 주인이 실제로 여기서 막혔습니다:
 *
 *     "This API key is not scoped to a workspace, so this request must
 *      include the anthropic-workspace-id header with the ID of the
 *      workspace to use."
 *
 *   그 번호(wrkspc_...)는 콘솔의 Settings > Workspaces 목록에 있습니다.
 *   하지만 눈으로 찾아 복사하는 일은 오타가 납니다 — 그리고 오타가 나면
 *   404 가 와서 또 한 바퀴 돕니다. 그래서 여기서 직접 물어봅니다.
 *
 * 어떻게 물어보나
 *   묘하게도, **이 문제를 겪는 키만** 물어볼 수 있습니다. 앤트로픽 문서
 *   (platform.claude.com/docs/en/manage-claude/admin-api) 가 관리 API 의
 *   인증 수단 중 하나를 이렇게 적어 둡니다:
 *
 *     "A personal key or service account key that isn't scoped to a
 *      specific workspace, sent in the x-api-key header."
 *
 *   즉 워크스페이스에 안 묶인 키 — 지금 막혀 있는 바로 그 키 — 가 관리
 *   API 를 쓸 수 있는 키입니다. 워크스페이스에 묶인 키라면 애초에 이
 *   도구가 필요 없습니다.
 *
 *   다만 같은 문서가 "The Admin API is unavailable for individual accounts"
 *   라고도 적어 둡니다. 개인 계정이면 막힐 수 있습니다 — 그때는 막혔다고
 *   말하고 콘솔에서 찾는 길을 알려 줍니다. 조용히 실패하지 않습니다.
 *
 * 기본 워크스페이스는 목록에 안 나옵니다
 *   문서 그대로입니다: "List Workspaces omits the Default Workspace".
 *   목록이 비어 있다는 건 "만든 워크스페이스가 없다" 는 뜻이지 고장이
 *   아닙니다. 그리고 기본 워크스페이스는 어차피 답이 아닙니다 —
 *   "You cannot set limits on the Default Workspace" 라서 월 지출 한도를
 *   못 겁니다. 판독은 사진 한 장마다 돈이 나가는 기능입니다.
 *
 * 의존성은 없습니다. 노드 기본 기능만 씁니다.
 * ========================================================================== */
'use strict';
const readline = require('node:readline');
const CONFIG = require('./config.js');
const OCR = require('../server/ocr.js');

const API = (process.env.ANTHROPIC_API_BASE || 'https://api.anthropic.com').replace(/\/+$/, '');
const VERSION = '2023-06-01';

const argv = process.argv.slice(2);
function flag(name) {
  const hit = argv.find(a => a === '--' + name || a.indexOf('--' + name + '=') === 0);
  if (!hit) return null;
  const eq = hit.indexOf('=');
  return eq === -1 ? true : hit.slice(eq + 1);
}

/* wrkspc_ 로 시작하는 값이어야 합니다. 문서가 그렇게 적어 두었고,
   아니면 앤트로픽이 400 "must be a valid workspace ID" 를 줍니다.
   여기서 먼저 막으면 그 한 바퀴를 안 돕니다. */
function looksLikeId(v) { return /^wrkspc_[A-Za-z0-9]+$/.test(String(v || '').trim()); }

async function callAdmin(key, path, init) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 15000);
  try {
    const r = await fetch(API + path, Object.assign({
      signal: ctrl.signal,
      headers: Object.assign({
        'x-api-key': key,
        'anthropic-version': VERSION
      }, (init && init.body) ? { 'content-type': 'application/json' } : {})
    }, init || {}));
    clearTimeout(timer);
    let j = null;
    try { j = await r.json(); } catch (e) { j = null; }
    return { status: r.status, ok: r.ok, body: j };
  } catch (e) {
    clearTimeout(timer);
    return { status: 0, ok: false, body: null,
             netError: e && e.name === 'AbortError'
               ? '앤트로픽에 닿는 데 시간이 너무 걸립니다'
               : '앤트로픽에 닿지 못했습니다 — 이 컴퓨터에서 api.anthropic.com 이 막혀 있는지 보세요' };
  }
}

/* 관리 API 가 막혔을 때 **왜** 막혔는지 나눠서 말합니다.
   "안 됩니다" 하나로 뭉치면 키를 새로 만들어야 하는 사람과 콘솔에서
   복사해 오면 되는 사람이 같은 말을 듣습니다. */
function adminTrouble(res) {
  if (res.netError) return res.netError;
  const e = (res.body && res.body.error) || {};
  const msg = String(e.message || '');
  if (res.status === 401) {
    return '판독 키가 거부되었습니다 — 지워졌거나, 틀렸거나, 유효기간이 지났습니다.\n' +
           '   키를 새로 만들어서 node tools/serve.js --setup --key 로 넣어 주세요.';
  }
  if (res.status === 403 || res.status === 404) {
    return '이 키로는 워크스페이스 목록을 볼 수 없습니다.\n' +
           '   개인 계정이거나(문서: "The Admin API is unavailable for individual\n' +
           '   accounts"), 키가 이미 한 워크스페이스에 묶여 있으면 이렇게 됩니다.\n' +
           '   → 콘솔의 Settings > Workspaces 목록 ID 칸에서 wrkspc_ 로 시작하는\n' +
           '     값을 복사해서:  node tools/workspaces.js --set=wrkspc_...\n' +
           (msg ? '   앤트로픽이 한 말: ' + msg + '\n' : '');
  }
  return '워크스페이스 목록을 못 받았습니다 (' + (res.status || '?') + ')' +
         (msg ? '\n   앤트로픽이 한 말: ' + msg : '');
}

async function listWorkspaces(key) {
  const res = await callAdmin(key, '/v1/organizations/workspaces?limit=100&include_archived=false');
  if (!res.ok) return { ok: false, why: adminTrouble(res) };
  const data = (res.body && res.body.data) || [];
  return { ok: true, items: data.filter(w => w && w.id) };
}

async function createWorkspace(key, name) {
  const res = await callAdmin(key, '/v1/organizations/workspaces',
    { method: 'POST', body: JSON.stringify({ name: String(name) }) });
  if (!res.ok) return { ok: false, why: adminTrouble(res) };
  const w = res.body || {};
  if (!looksLikeId(w.id)) return { ok: false, why: '만들어졌는데 번호를 못 읽었습니다' };
  return { ok: true, item: w };
}

/* 넣고 끝내지 않습니다. 넣은 값으로 **실제로 한 번 물어봅니다.**
   안 그러면 주인은 폰에서 사진을 올려 보고서야 틀린 걸 압니다. */
async function verify(key, workspace, model) {
  const r = await OCR.checkKey(key, model || null, { timeoutMs: 10000, workspace: workspace });
  return r;
}

function save(cfg, value) {
  cfg.anthropicWorkspace = value;
  CONFIG.save(cfg);
}

async function main() {
  const { cfg, from } = CONFIG.load();
  const key = cfg.anthropicKey;

  if (flag('clear') !== null) {
    save(cfg, '');
    console.log('워크스페이스 설정을 비웠습니다.');
    console.log('워크스페이스 안에서 만든 키라면 이게 맞습니다 — 그런 키는 헤더가 필요 없습니다.');
    return 0;
  }

  if (!key) {
    console.log('판독 키가 없습니다. 먼저 넣어 주세요:');
    console.log('  node tools/serve.js --setup --key');
    return 1;
  }

  const direct = flag('set');
  if (typeof direct === 'string' && direct) {
    if (!looksLikeId(direct)) {
      console.log('그 값은 워크스페이스 번호처럼 생기지 않았습니다.');
      console.log('  wrkspc_ 로 시작해야 합니다. 예: wrkspc_01JwQvzr7rXLA5AGx3HKfFUJ');
      return 1;
    }
    save(cfg, direct);
    console.log('넣었습니다: ' + direct);
    const v = await verify(key, direct, process.env.OCR_MODEL);
    console.log(v.ok ? '✓ 이 번호로 판독이 됩니다 — ' + v.reason
                     : '✗ ' + v.reason + (v.raw ? '\n   앤트로픽이 한 말: ' + v.raw : ''));
    return v.ok ? 0 : 1;
  }

  const create = flag('create');
  if (typeof create === 'string' && create) {
    console.log('워크스페이스를 만듭니다: ' + create);
    const made = await createWorkspace(key, create);
    if (!made.ok) { console.log('✗ ' + made.why); return 1; }
    save(cfg, made.item.id);
    console.log('✓ 만들고 서버 설정에 넣었습니다: ' + made.item.id);
    console.log('');
    console.log('  월 지출 한도는 콘솔에서만 걸 수 있습니다 —');
    console.log('  Settings > Workspaces > ' + create + ' > Spend limits');
    console.log('  (기본 워크스페이스에는 한도를 못 겁니다. 그래서 따로 만든 것입니다.)');
    console.log('');
    const v = await verify(key, made.item.id, process.env.OCR_MODEL);
    console.log(v.ok ? '✓ 판독이 됩니다 — ' + v.reason
                     : '✗ ' + v.reason + (v.raw ? '\n   앤트로픽이 한 말: ' + v.raw : ''));
    return v.ok ? 0 : 1;
  }

  const list = await listWorkspaces(key);
  if (!list.ok) { console.log('✗ ' + list.why); return 1; }

  if (cfg.anthropicWorkspace) {
    console.log('지금 서버가 쓰는 값: ' + cfg.anthropicWorkspace +
                (from.anthropicWorkspace ? '  (' + from.anthropicWorkspace + ')' : ''));
    console.log('');
  }

  if (!list.items.length) {
    console.log('만들어 둔 워크스페이스가 없습니다.');
    console.log('(기본 워크스페이스는 목록에 안 나옵니다 — 앤트로픽이 그렇게 만들어 뒀습니다.');
    console.log(' 그리고 기본 워크스페이스에는 월 지출 한도를 못 겁니다.)');
    console.log('');
    console.log('하나 만들까요? 한 줄이면 됩니다:');
    console.log('  node tools/workspaces.js --create=mybody');
    return 1;
  }

  console.log('쓸 수 있는 워크스페이스:');
  list.items.forEach((w, i) => {
    const mine = w.id === cfg.anthropicWorkspace ? '  ← 지금 이것' : '';
    console.log('  ' + (i + 1) + ') ' + (w.name || '(이름 없음)') + '  ' + w.id + mine);
  });
  console.log('');

  if (flag('set') === null) {
    console.log('하나를 서버에 넣으려면:  node tools/workspaces.js --set');
    return 0;
  }

  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const pick = await new Promise(res => rl.question('몇 번을 쓸까요? ', a => res((a || '').trim())));
  rl.close();
  const n = Number(pick);
  if (!(n >= 1 && n <= list.items.length)) { console.log('그 번호는 목록에 없습니다.'); return 1; }

  const chosen = list.items[n - 1];
  save(cfg, chosen.id);
  console.log('넣었습니다: ' + (chosen.name || '') + ' ' + chosen.id);
  const v = await verify(key, chosen.id, process.env.OCR_MODEL);
  console.log(v.ok ? '✓ 이 번호로 판독이 됩니다 — ' + v.reason
                   : '✗ ' + v.reason + (v.raw ? '\n   앤트로픽이 한 말: ' + v.raw : ''));
  return v.ok ? 0 : 1;
}

if (require.main === module) {
  main().then(c => process.exit(c || 0))
        .catch(e => { console.error('워크스페이스 확인 중 오류: ' + (e && e.message || e)); process.exit(1); });
}
module.exports = { looksLikeId, adminTrouble, listWorkspaces, createWorkspace };
