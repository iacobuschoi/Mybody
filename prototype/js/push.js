/* =============================================================================
 * push.js — 폰 알림 켜기 · 끄기
 *
 * 사용자 요청: "운동 해서 체크하면 친구한테 알림가게".
 * 앱 안 소식(news.js)은 앱을 열어야 보입니다. 이건 앱을 안 열어도
 * 잠금화면에 뜹니다 — 원래 요청에 더 가까운 쪽입니다.
 *
 * **되는 조건이 까다롭고, 그걸 숨기지 않습니다.**
 *   · https 여야 합니다. 같은 와이파이의 http://192.168.x.x 에서는
 *     navigator.serviceWorker 자체가 없습니다 (실측 확인).
 *   · 서버에 알림 열쇠가 있어야 합니다 (node tools/push-keys.js).
 *   · 브라우저가 권한을 줘야 합니다. 한 번 거절하면 브라우저 설정에서
 *     직접 풀어야 하고, 앱이 다시 물을 수 없습니다 — 그래서 묻기 전에
 *     무엇을 받게 되는지 먼저 보여 줍니다.
 *   · 아이폰은 홈 화면에 추가한 뒤에만 됩니다 (Safari 16.4+).
 *
 * state() 가 돌려주는 값이 화면의 전부입니다. "안 됨" 을 하나로 뭉치지
 * 않고 이유를 나눠서 돌려줍니다 — 이유가 다르면 할 일도 다릅니다.
 * ========================================================================== */
(function (global) {
  'use strict';

  var KEY = 'mybody.push.v1';     // 이 기기의 구독 endpoint 만 기억합니다

  function saved() {
    try { return JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { return null; }
  }
  function remember(ep) {
    try {
      if (ep) localStorage.setItem(KEY, JSON.stringify({ endpoint: ep }));
      else localStorage.removeItem(KEY);
    } catch (e) {}
  }

  function b64uToBytes(s) {
    var pad = '='.repeat((4 - s.length % 4) % 4);
    var raw = atob((s + pad).replace(/-/g, '+').replace(/_/g, '/'));
    var out = new Uint8Array(raw.length);
    for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }
  function bytesToB64u(buf) {
    var b = new Uint8Array(buf), s = '';
    for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }

  /**
   * 지금 이 기기에서 알림이 어떤 상태인가.
   *   can        켤 수 있는가
   *   why        못 켜는 이유 (can 이 false 일 때만)
   *   on         지금 켜져 있는가
   *   permission 브라우저 권한 ('granted'|'denied'|'default')
   */
  function state() {
    var S = global.MB_SYNC;
    var out = { can: false, why: '', on: false, permission: 'default' };

    if (typeof Notification !== 'undefined') out.permission = Notification.permission;
    out.on = !!saved();

    if (typeof navigator === 'undefined' || !('serviceWorker' in navigator)) {
      out.why = (global.isSecureContext === false)
        ? 'https 로 열었을 때만 됩니다. 지금은 같은 와이파이 주소(http)라 ' +
          '브라우저가 알림 자체를 막습니다 — 터널 주소로 열어 주세요.'
        : '이 브라우저는 알림을 지원하지 않습니다.';
      return out;
    }
    if (!('PushManager' in global)) { out.why = '이 브라우저는 알림을 지원하지 않습니다.'; return out; }
    if (typeof Notification === 'undefined') { out.why = '이 브라우저는 알림을 지원하지 않습니다.'; return out; }
    if (!S || !S.status().signedIn) { out.why = '로그인해야 친구 소식을 받습니다.'; return out; }
    if (Notification.permission === 'denied') {
      out.why = '이 브라우저에서 알림을 거절해 뒀습니다. 주소창 옆 자물쇠 → ' +
                '알림 에서 직접 허용해야 합니다 (앱이 다시 물어볼 수 없습니다).';
      return out;
    }
    out.can = true;
    return out;
  }

  /** 서버의 공개 열쇠. 없으면 이 서버는 알림을 안 켠 것입니다. */
  function serverKey() {
    var S = global.MB_SYNC;
    if (!S) return Promise.resolve(null);
    return S._api('/push/key').then(function (r) { return (r && r.key) || null; })
      .catch(function () { return null; });
  }

  /**
   * 알림을 켭니다. 실패하면 **왜** 실패했는지 말합니다.
   * 성공/실패 모두 문자열 이유를 담아 돌려주고, 화면은 그걸 그대로 씁니다.
   */
  function enable() {
    var st = state();
    if (!st.can) return Promise.resolve({ ok: false, reason: st.why });

    return serverKey().then(function (key) {
      if (!key) {
        return { ok: false, reason: '이 서버에는 알림 열쇠가 없습니다. ' +
                 '서버를 띄운 사람이 node tools/push-keys.js 를 한 번 돌려야 합니다.' };
      }
      return Notification.requestPermission().then(function (perm) {
        if (perm !== 'granted') {
          return { ok: false, reason: perm === 'denied'
            ? '알림을 거절했습니다. 브라우저 설정에서만 다시 켤 수 있습니다.'
            : '알림을 허용하지 않았습니다.' };
        }
        return navigator.serviceWorker.ready.then(function (reg) {
          return reg.pushManager.subscribe({
            userVisibleOnly: true,               // 조용한 푸시는 안 씁니다
            applicationServerKey: b64uToBytes(key)
          });
        }).then(function (sub) {
          var j = sub.toJSON ? sub.toJSON() : null;
          var keys = (j && j.keys) || {};
          var body = {
            endpoint: sub.endpoint,
            p256dh: keys.p256dh || bytesToB64u(sub.getKey('p256dh')),
            auth: keys.auth || bytesToB64u(sub.getKey('auth'))
          };
          return global.MB_SYNC._api('/push/subscribe', { method: 'POST', body: body })
            .then(function (r) {
              if (!r || !r.ok) {
                /* 서버가 거절했으면 브라우저 구독도 물립니다 — 안 그러면
                   이 기기는 "구독했는데 서버는 모르는" 상태로 남습니다. */
                sub.unsubscribe().catch(function () {});
                return { ok: false, reason: (r && r.reason) || '서버가 구독을 거절했습니다.' };
              }
              remember(sub.endpoint);
              return { ok: true };
            });
        });
      });
    }).catch(function (e) {
      return { ok: false, reason: String(e && e.message || e) };
    });
  }

  /** 알림을 끕니다. 브라우저 쪽과 서버 쪽을 **둘 다** 풉니다. */
  function disable() {
    var ep = (saved() || {}).endpoint || null;
    var S = global.MB_SYNC;
    var steps = [];

    if (typeof navigator !== 'undefined' && navigator.serviceWorker) {
      steps.push(navigator.serviceWorker.ready
        .then(function (reg) { return reg.pushManager.getSubscription(); })
        .then(function (sub) {
          if (!sub) return null;
          if (!ep) ep = sub.endpoint;
          return sub.unsubscribe();
        }).catch(function () { return null; }));
    }
    return Promise.all(steps).then(function () {
      remember(null);
      /* 서버에도 말합니다. 브라우저에서만 풀면 서버는 죽은 주소로 계속
         보내고, 그건 푸시 서비스가 404 를 줄 때까지 이어집니다. */
      if (ep && S && S.status().signedIn) {
        return S._api('/push/unsubscribe', { method: 'POST', body: { endpoint: ep } })
          .catch(function () { return null; });
      }
      return null;
    }).then(function () { return { ok: true }; });
  }

  global.MB_PUSH = { state: state, enable: enable, disable: disable, serverKey: serverKey };
})(window);
