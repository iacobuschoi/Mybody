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
  // 서버 이야기는 캐시하지 않습니다 — 오래된 답이 새 답인 척하면 안 됩니다.
  if (url.pathname.startsWith('/api')) return;
  // 다른 출처(글꼴 등)는 브라우저 기본 처리에 맡깁니다.
  if (url.origin !== self.location.origin) return;

  e.respondWith(
    caches.match(req).then(hit => {
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
  if (!d || !d.t) return;
  e.waitUntil(self.registration.showNotification(d.t, {
    body: d.b || '',
    tag: 'mybody-news',          // 여러 건이 쌓이면 최신 하나로 접힙니다
    renotify: false,
    icon: './assets/icon-192.png',
    badge: './assets/icon-192.png',
    data: { url: d.u || '/' }
  }));
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
