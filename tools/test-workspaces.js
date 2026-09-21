/* =============================================================================
 * tools/test-workspaces.js — 워크스페이스 찾아 넣기 검증
 *
 *   node tools/test-workspaces.js
 *
 * 앤트로픽을 부르지 않습니다. 가짜 관리 API 를 띄워서, 그쪽이 무엇을
 * 돌려주든 우리가 **주인에게 무엇을 시키는지**만 봅니다.
 *
 * 여기서 봐야 하는 것은 목록을 받아오는 재주가 아니라, 안 될 때의
 * 처신입니다. 이 도구는 이미 한 번 막힌 사람이 쓰는 도구라서, 여기서
 * 또 "안 됩니다" 만 나오면 그 사람은 갈 데가 없습니다:
 *   - 키가 죽었으면 키를 가리키는가 (워크스페이스가 아니라)
 *   - 관리 API 가 막혔으면 콘솔에서 찾는 길을 알려 주는가
 *   - 오타 난 번호를 저장하기 **전에** 막는가
 *   - 넣고 나서 실제로 되는지 확인까지 하는가
 *   - 기본 워크스페이스는 목록에 안 나온다는 것을 고장으로 오해하지 않는가
 * ========================================================================== */
'use strict';
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');

const PORT = 8940 + Math.floor(Math.random() * 40);
const BASE = `http://127.0.0.1:${PORT}`;
const ROOT = path.join(__dirname, '..');

let pass = 0, fail = 0;
const ok = (n, c, d) => {
  if (c) { pass++; console.log('  ✓', n); }
  else { fail++; console.log('  ✗', n, d === undefined ? '' : JSON.stringify(d)); }
};

/* --- 가짜 관리 API -------------------------------------------------------- */
let mode = 'ok';          // ok | empty | forbidden | dead | weird
let lastCreate = null;
let lastAuth = null;
const fake = http.createServer((req, res) => {
  let body = '';
  req.on('data', c => { body += c; });
  req.on('end', () => {
    lastAuth = req.headers['x-api-key'] || null;
    const send = (code, obj) => {
      res.writeHead(code, { 'content-type': 'application/json' });
      res.end(JSON.stringify(obj));
    };
    /* 키 확인(checkKey)은 /v1/models/<이름> 으로 옵니다. */
    if (req.url.indexOf('/v1/models/') === 0) {
      if (mode === 'dead') return send(401, { error: { type: 'authentication_error', message: 'invalid x-api-key' } });
      return send(200, { id: 'm', type: 'model' });
    }
    if (req.url.indexOf('/v1/organizations/workspaces') === 0 && req.method === 'POST') {
      try { lastCreate = JSON.parse(body); } catch { lastCreate = null; }
      if (mode === 'forbidden') return send(403, { error: { type: 'permission_error', message: 'Admin API unavailable' } });
      return send(200, { id: 'wrkspc_01MADE0000000000000001', name: (lastCreate && lastCreate.name) || '' });
    }
    if (req.url.indexOf('/v1/organizations/workspaces') === 0) {
      if (mode === 'forbidden') return send(403, { error: { type: 'permission_error', message: 'Admin API unavailable' } });
      if (mode === 'dead') return send(401, { error: { type: 'authentication_error', message: 'invalid x-api-key' } });
      if (mode === 'weird') return send(500, { error: { type: 'api_error', message: 'boom' } });
      if (mode === 'empty') return send(200, { data: [] });
      return send(200, { data: [
        { id: 'wrkspc_01AAAAAAAAAAAAAAAAAAAA', name: '몸' },
        { id: 'wrkspc_01BBBBBBBBBBBBBBBBBBBB', name: 'Production' }
      ] });
    }
    send(404, { error: { type: 'not_found_error', message: 'nope' } });
  });
});

/* 진짜 설정 파일을 건드리면 안 됩니다. HOME 을 임시로 옮깁니다. */
const HOME = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-ws-'));

/* **spawnSync 를 쓰면 안 됩니다.**
   가짜 API 서버는 이 프로세스 안에서 돌아갑니다. spawnSync 는 이
   프로세스의 이벤트 루프를 통째로 막아 버려서, 자식이 보낸 요청을
   아무도 받지 못합니다 — 자식은 15초를 기다리다 "앤트로픽에 닿지
   못했습니다" 로 끝납니다. 가짜 서버를 안 거치고 끝나니 시험은
   초록불만 못 켤 뿐 아니라, **네트워크 실패 경로만 반복해서**
   확인하게 됩니다. 실제로 그렇게 23개가 한꺼번에 틀렸습니다. */
function run(args, extraEnv) {
  return new Promise(res => {
    const ch = spawn(process.execPath, [path.join(ROOT, 'tools', 'workspaces.js')].concat(args), {
      cwd: ROOT,
      env: Object.assign({}, process.env, {
        HOME: HOME, USERPROFILE: HOME,
        ANTHROPIC_API_BASE: BASE,
        OCR_API_URL: BASE + '/v1/messages',
        ANTHROPIC_API_KEY: '',           // 설정 파일만 보게 합니다
        NODE_NO_WARNINGS: '1'
      }, extraEnv || {})
    });
    let out = '';
    ch.stdout.on('data', c => { out += c; });
    ch.stderr.on('data', c => { out += c; });
    const kill = setTimeout(() => { try { ch.kill(); } catch (e) {} }, 25000);
    ch.on('close', code => { clearTimeout(kill); res({ out: out, code: code }); });
  });
}

function writeConfig(patch) {
  const dir = path.join(HOME, '.mybody');
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, 'config.json');
  let cur = {};
  try { cur = JSON.parse(fs.readFileSync(f, 'utf8')); } catch (e) { cur = {}; }
  fs.writeFileSync(f, JSON.stringify(Object.assign(cur, patch), null, 2));
}
function readConfig() {
  try { return JSON.parse(fs.readFileSync(path.join(HOME, '.mybody', 'config.json'), 'utf8')); }
  catch (e) { return {}; }
}

async function main() {
  const W = require('./workspaces.js');

  console.log('\n[1] 번호처럼 생겼는지 먼저 본다');
  ok('진짜 번호는 통과', W.looksLikeId('wrkspc_01JwQvzr7rXLA5AGx3HKfFUJ'));
  ok('접두사만 있으면 거부', !W.looksLikeId('wrkspc_'));
  /* 복사하다 잘린 값이 제일 흔한 오타입니다. 통과시키면 앤트로픽까지
     갔다가 400 을 받고 한 바퀴 더 돕니다. */
  ok('잘린 번호도 거부', !W.looksLikeId('wrkspc_01Jw'));
  ok('이름은 거부', !W.looksLikeId('mybody'));
  ok('빈 값은 거부', !W.looksLikeId(''));
  /* 공백이 붙은 값은 **통과시키되 다듬어서** 씁니다. 붙여넣기로 들어오는
     흔한 모양이라 거부하면 성가시고, 그대로 저장하면 헤더에 공백째로
     실려 나가 400 이 옵니다 — 그리고 그 공백은 화면에서 안 보입니다. */
  ok('앞뒤 공백이 붙어도 통과시킨다', W.looksLikeId('  wrkspc_01AAAAAAAAAAAAAAAAAAAA  ') === true);
  ok('다듬어서 돌려준다', W.normalizeId('  wrkspc_01AAAA  ') === 'wrkspc_01AAAA',
     JSON.stringify(W.normalizeId('  wrkspc_01AAAA  ')));

  console.log('\n[2] 키가 없으면 워크스페이스부터 찾지 않는다');
  {
    /* 키가 없는데 "워크스페이스를 고르세요" 라고 하면 순서가 뒤집힙니다. */
    const r = await run([]);
    ok('키부터 넣으라고 한다', /판독 키가 없습니다/.test(r.out), r.out);
    ok('그 명령까지 적어 준다', /--setup --key/.test(r.out), r.out);
  }

  writeConfig({ anthropicKey: 'sk-ant-test-key', anthropicWorkspace: '' });

  console.log('\n[3] 목록을 받아온다');
  mode = 'ok';
  {
    const r = await run([]);
    ok('둘 다 보여 준다', /몸/.test(r.out) && /Production/.test(r.out), r.out);
    ok('번호도 같이 보여 준다', /wrkspc_01AAAAAAAAAAAAAAAAAAAA/.test(r.out), r.out);
    ok('설정 키로 물어봤다', lastAuth === 'sk-ant-test-key', lastAuth);
    ok('아직 아무것도 안 바꿨다', !readConfig().anthropicWorkspace, readConfig());
    ok('넣는 법을 알려 준다', /--set/.test(r.out), r.out);
  }

  console.log('\n[4] 오타 난 번호는 저장 전에 막는다');
  {
    const r = await run(['--set=mybody']);
    ok('거부한다', r.code !== 0, r.code);
    ok('무엇이 틀렸는지 말한다', /wrkspc_ 로 시작/.test(r.out), r.out);
    ok('설정에 안 들어갔다', !readConfig().anthropicWorkspace, readConfig());
  }

  console.log('\n[4-2] 공백이 섞여 들어와도 깨끗하게 저장한다');
  {
    /* 공백째로 저장되면 serve --show 에는 멀쩡해 보이는데 헤더만 틀립니다.
       눈으로는 영영 못 찾습니다. */
    await run(['--set=  wrkspc_01AAAAAAAAAAAAAAAAAAAA  ']);
    ok('공백을 떼고 저장한다',
       readConfig().anthropicWorkspace === 'wrkspc_01AAAAAAAAAAAAAAAAAAAA', readConfig());
  }

  console.log('\n[5] 제대로 된 번호는 넣고, 넣은 걸로 확인까지 한다');
  {
    const r = await run(['--set=wrkspc_01AAAAAAAAAAAAAAAAAAAA']);
    ok('설정에 들어갔다', readConfig().anthropicWorkspace === 'wrkspc_01AAAAAAAAAAAAAAAAAAAA', readConfig());
    /* 넣고 끝내면 주인은 폰에서 사진을 올려 보고서야 틀린 걸 압니다. */
    ok('실제로 되는지 확인한다', /✓/.test(r.out), r.out);
    ok('성공으로 끝난다', r.code === 0, r.code);
  }

  console.log('\n[6] 넣었는데 키가 죽어 있으면 거기서 멈춘다');
  mode = 'dead';
  {
    const r = await run(['--set=wrkspc_01BBBBBBBBBBBBBBBBBBBB']);
    ok('실패로 끝난다', r.code !== 0, r.code);
    ok('키가 거부됐다고 말한다', /거부되었습니다/.test(r.out), r.out);
    ok('설정이 어떻게 됐는지도 말해 준다', /--clear/.test(r.out), r.out);
    /* 유효기간은 새로 생긴 함정입니다 — 키를 만들 때 3시간·1일·7일·30일
       중 하나를 고를 수 있고, 지나면 401 입니다. 살릴 수 없습니다. */
    ok('유효기간도 의심하게 해 준다', /유효기간/.test(r.out), r.out);
  }

  console.log('\n[7] 관리 API 가 막히면 콘솔 길을 알려 준다');
  mode = 'forbidden';
  {
    const r = await run([]);
    ok('막혔다고 말한다', /볼 수 없습니다/.test(r.out), r.out);
    ok('개인 계정일 수 있다고 알려 준다', /개인 계정/.test(r.out), r.out);
    ok('콘솔에서 찾는 길을 준다', /Settings > Workspaces/.test(r.out), r.out);
    ok('직접 넣는 명령도 준다', /--set=wrkspc_/.test(r.out), r.out);
    ok('앤트로픽이 한 말도 붙인다', /Admin API unavailable/.test(r.out), r.out);
  }

  console.log('\n[8] 목록이 비어 있는 것은 고장이 아니다');
  mode = 'empty';
  {
    /* 기본 워크스페이스는 목록에 안 나옵니다 — 앤트로픽 문서 그대로입니다
       ("List Workspaces omits the Default Workspace"). 이걸 고장으로
       말하면 주인은 멀쩡한 계정을 의심합니다. */
    const r = await run([]);
    ok('없다고만 말한다', /만들어 둔 워크스페이스가 없습니다/.test(r.out), r.out);
    ok('기본 워크스페이스 얘기를 해 준다', /기본 워크스페이스는 목록에 안 나옵니다/.test(r.out), r.out);
    ok('만드는 법을 알려 준다', /--create=/.test(r.out), r.out);
  }

  console.log('\n[9] 만들어 주고 바로 넣는다');
  mode = 'ok';
  {
    const r = await run(['--create=mybody']);
    ok('이름 그대로 만든다', lastCreate && lastCreate.name === 'mybody', lastCreate);
    ok('만든 번호를 넣는다', readConfig().anthropicWorkspace === 'wrkspc_01MADE0000000000000001', readConfig());
    /* 만들기만 하고 한도 얘기를 안 하면, 한도 없는 워크스페이스가
       하나 더 생긴 것뿐입니다. 판독은 장당 돈이 나갑니다. */
    ok('월 지출 한도 거는 곳을 알려 준다', /Spend limits/.test(r.out), r.out);
    ok('되돌릴 수 없다고 미리 말한다', /지울 수 없습니다/.test(r.out), r.out);
    ok('기본 워크스페이스엔 못 건다고 말해 준다', /기본 워크스페이스에는 한도를 못 겁니다/.test(r.out), r.out);
    ok('되는지 확인까지 한다', /✓/.test(r.out), r.out);
  }

  console.log('\n[10] 비우기');
  {
    const r = await run(['--clear']);
    ok('비워진다', readConfig().anthropicWorkspace === '', readConfig());
    ok('비우는 게 맞는 경우를 말해 준다', /헤더가 필요 없습니다/.test(r.out), r.out);
  }

  console.log('\n[11] 알 수 없는 실패는 상태를 그대로 보여 준다');
  mode = 'weird';
  {
    const r = await run([]);
    ok('상태 번호를 보여 준다', /500/.test(r.out), r.out);
    ok('앤트로픽이 한 말도 보여 준다', /boom/.test(r.out), r.out);
  }
}

fake.listen(PORT, '127.0.0.1', () => {
  main()
    .then(() => {
      console.log(`\n통과 ${pass} / 실패 ${fail}`);
      fake.close();
      try { fs.rmSync(HOME, { recursive: true, force: true }); } catch (e) {}
      process.exit(fail ? 1 : 0);
    })
    .catch(e => {
      console.error(e); fake.close();
      try { fs.rmSync(HOME, { recursive: true, force: true }); } catch (e2) {}
      process.exit(1);
    });
});
