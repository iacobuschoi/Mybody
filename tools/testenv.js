/* =============================================================================
 * tools/testenv.js — 시험을 **주인의 컴퓨터로부터 떼어 놓습니다**
 *
 *   require('./testenv.js');      // 시험 파일 맨 위에서 한 줄
 *
 * 왜 필요한가
 *   서버가 ~/.mybody/config.json 을 읽게 고쳤습니다. 그래야 `node
 *   server/server.js` 로 띄운 사람의 판독 키가 안 사라집니다 — 문서와
 *   서버 자신이 그 명령을 알려 주고 있으니까요.
 *
 *   그런데 그 순간 시험들이 **검사하는 사람의 집을 들여다보게** 됐습니다.
 *   실제로 이런 일이 났습니다:
 *     · "가입 코드 없으면 401" → 집 설정에 openSignup:true 가 있어서 통과
 *     · "열쇠 없는 서버는 알림 구독을 거절한다" → 집에 VAPID 열쇠가 있어서 실패
 *     · "알림은 안 간다" → 같은 이유로 알림이 갔습니다
 *
 *   검사하는 사람의 홈 디렉터리에 따라 결과가 달라지는 시험은 시험이
 *   아닙니다. 어떤 컴퓨터에서는 초록이고 다른 데서는 빨간데, 둘 다
 *   제품에 대해서는 아무 말도 안 해 줍니다.
 *
 *   그래서 시험 프로세스의 HOME 을 빈 임시 폴더로 옮깁니다. 여기서
 *   띄우는 자식 서버들이 그걸 그대로 물려받으므로, spawn 하는 자리를
 *   하나하나 고칠 필요가 없습니다.
 *
 *   설정 파일을 **일부러** 읽히고 싶은 시험은(예: test-selfhost 의
 *   "server.js 를 직접 띄워도 설정을 읽는다") 자기 HOME 을 따로 만들어
 *   넘기면 됩니다 — 그쪽이 명시적이라 읽기도 낫습니다.
 * ========================================================================== */
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mybody-home-'));
process.env.HOME = dir;
process.env.USERPROFILE = dir;      // 윈도우

process.on('exit', () => {
  try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) {}
});

module.exports = { home: dir };
