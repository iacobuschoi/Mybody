/* =============================================================================
 * sw.js — 오프라인으로 열리게 하는 것만 합니다
 *
 * 이 앱은 원래 오프라인에서 돕니다 — 계산도 저장도 전부 기기 안에서
 * 일어나고, 서버는 친구 기능과 자동 판독에만 씁니다. 그런데 서비스워커가
 * 없으면 "앱을 여는 것" 자체가 네트워크를 탑니다. 헬스장 지하에서 앱이
 * 안 열리면 그 안이 오프라인으로 돌든 말든 의미가 없습니다.
 *
 * 전략: 앱 껍데기는 미리 받아 두고(precache), 열 때는 캐시부터 봅니다.
 * 대신 백그라운드로 새 버전을 받아 다음 실행에 씁니다(stale-while-revalidate).
 * 파일이 서른 개 넘는 <script> 태그라, 하나라도 옛 버전이 섞이면 앱이
 * 이상하게 동작합니다. 그래서 버전이 바뀌면 캐시를 통째로 버립니다.
 *
 * /api 는 절대 캐시하지 않습니다. 친구의 최근 기록이나 판독 결과가
 * 캐시에서 나오면 그건 틀린 정보입니다.
 * ========================================================================== */
'use strict';

const VERSION = 'mybody-v__BUILD_VERSION__';
const SHELL = __SHELL_FILES__;

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(VERSION)
      // 한 파일이라도 실패하면 설치를 접습니다. 반쯤 받아 둔 캐시가
      // 제일 나쁩니다 — 열리기는 하는데 화면 하나가 없는 앱이 됩니다.
      .then(c => c.addAll(SHELL))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  /* 서버 이야기는 캐시하지 않습니다 — 오래된 답이 새 답인 척하면 안 됩니다.
     /health 를 빼놓지 않았던 동안 이 줄이 거짓말을 만들고 있었습니다:
     앱은 "서버가 살아 있나" 를 /health 로 물어보는데, 그것이 /api 가
     아니라 캐시된 뒤로는 서버를 꺼도 영원히 "닿습니다" 가 나왔습니다.
     그러면 "컴퓨터가 꺼져 있는 것 같습니다" 가 배포본에서 한 번도 안 뜹니다
     — 서비스워커는 배포본에만 등록되므로 prototype 에서는 안 보였습니다.
     Cache Storage 는 no-store 를 무시하므로 요청 쪽 옵션으로는 못 막습니다. */
  if (url.pathname.startsWith('/api') || url.pathname === '/health') return;
  // 다른 출처(글꼴 등)는 브라우저 기본 처리에 맡깁니다.
  if (url.origin !== self.location.origin) return;

  /* ignoreSearch: 물음표 뒤를 빼고 찾습니다.
   *
   * 매니페스트의 start_url 이 "./?app=1" 입니다 — 홈 화면 아이콘으로
   * 열면 그 주소로 들어옵니다. 그런데 캐시에 담긴 것은 "./" 라서,
   * 물음표까지 따지면 **깔아 둔 앱이 오프라인에서 안 열립니다.**
   * 온라인일 때는 네트워크가 받아 주니 아무 증상이 없다가, 지하철에서
   * 처음 드러납니다. 오프라인 검사가 이걸 잡았습니다. */
  e.respondWith(
    caches.match(req, { ignoreSearch: true }).then(hit => {
      const net = fetch(req).then(res => {
        if (res && res.ok && res.type === 'basic') {
          const copy = res.clone();
          caches.open(VERSION).then(c => c.put(req, copy)).catch(() => {});
        }
        return res;
      }).catch(() => hit);        // 오프라인이면 캐시가 답입니다
      return hit || net;
    })
  );
});

/* --- 폰 알림 --------------------------------------------------------------
 *
 * 서버가 보낸 한 줄을 잠금화면에 띄웁니다. 들어오는 것은 언제나
 * "누가 운동했다" 뿐입니다 — 안 한 것은 서버가 보내지 않습니다.
 *
 * 본문이 깨져 있거나 비어 있어도 아무것도 안 띄웁니다. 제목 없는 알림을
 * 띄우느니 안 띄우는 게 낫습니다. (브라우저에 따라 payload 없는 푸시를
 * 보낼 수 있는데, 그때 "새 알림" 같은 빈 껍데기를 띄우면 열어 봐도
 * 아무것도 없습니다.)
 * -------------------------------------------------------------------------- */
self.addEventListener('push', e => {
  let d = null;
  try { d = e.data ? e.data.json() : null; } catch (err) { d = null; }

  /* 본문이 없거나 깨졌어도 **반드시 하나는 띄웁니다.**
   *
   * 예전엔 여기서 조용히 돌아갔습니다. 그게 "조용한 푸시"인데,
   * 구독할 때 userVisibleOnly: true 로 약속해 놓고 안 띄우는 것이라
   * 브라우저가 약속을 깬 것으로 봅니다.
   *   · 크롬은 대신 "이 사이트가 백그라운드에서 업데이트되었습니다"
   *     같은 제 문구를 띄웁니다 — 우리 앱 이름으로 남의 문장이 나갑니다.
   *   · 사파리는 더 세게 나옵니다. 조용한 푸시가 반복되면 **알림 권한을
   *     회수합니다.** 한 번 회수되면 앱이 다시 물어볼 수 없고, 친구가
   *     iOS 설정에서 직접 풀어야 합니다 — 그걸 알아낼 방법이 없습니다.
   *
   * 그래서 못 읽었을 때도 띄울 말을 정해 둡니다. 내용이 없는 알림보다
   * 나쁜 것은, 알림이 영영 안 오게 되는 것입니다. */
  const title = (d && d.t) || 'Mybody';
  const body = (d && d.b) || '친구 소식이 있습니다. 앱을 열어 확인하세요.';

  e.waitUntil(self.registration.showNotification(title, {
    body: body,
    tag: 'mybody-news',          // 여러 건이 쌓이면 최신 하나로 접힙니다
    renotify: false,
    icon: './assets/icon-192.png',
    badge: './assets/icon-192.png',
    data: { url: (d && d.u) || '/' }
  }));
});

/* 브라우저가 구독을 갈아 끼울 때.
 *
 * 열쇠 회전 · 앱 업데이트 · 푸시 서비스 사정으로 endpoint 가 바뀝니다.
 * 이 핸들러가 없으면 **그 순간부터 알림이 영영 안 옵니다** — 서버는 죽은
 * 주소로 계속 보내고, 사용자는 "켜 뒀는데 안 온다" 만 겪습니다. 아무
 * 화면에도 안 나타나는 고장입니다.
 *
 * 서비스워커는 로그인 토큰을 못 읽어서(localStorage 가 없습니다) 서버에
 * 직접 말할 수가 없습니다. 그래서 여기서는 **구독만 되살려 두고**,
 * 앱이 다음에 열릴 때 push.js 의 resync() 가 서버에 알립니다. */
self.addEventListener('pushsubscriptionchange', e => {
  e.waitUntil((async () => {
    try {
      const old = e.oldSubscription || await self.registration.pushManager.getSubscription();
      const key = old && old.options && old.options.applicationServerKey;
      if (!key) return;
      await self.registration.pushManager.subscribe({
        userVisibleOnly: true, applicationServerKey: key
      });
    } catch (err) { /* 되살리지 못하면 앱이 열릴 때 다시 구독합니다 */ }
  })());
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const want = (e.notification.data && e.notification.data.url) || '/';
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
      /* 이미 열려 있는 탭이 있으면 그걸 씁니다. 누를 때마다 새 탭이
         쌓이면 그 자체가 짜증입니다. */
      for (const c of list) {
        if (c.url.indexOf(self.location.origin) === 0 && 'focus' in c) {
          c.navigate(want).catch(() => {});
          return c.focus();
        }
      }
      return self.clients.openWindow(want);
    })
  );
});
