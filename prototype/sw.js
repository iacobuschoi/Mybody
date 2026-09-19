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
