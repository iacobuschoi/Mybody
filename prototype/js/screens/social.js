/* P14 계정 · P15 친구(탭) · P16 친구 한 사람 — P17 은 회수됐습니다 (공유 설정은 M27/M28 모달) */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;
  function B() { return global.MB_BACKEND; }

  /* --- 남의 주(week)를 몇 주 전이라고 부를 것인가 --------------------------
   *
   * 스냅샷은 친구가 **자기 앱에서 저장할 때만** 올라갑니다. 그래서 새 주가
   * 시작되고 친구가 아직 앱을 안 열었으면 그 주의 행이 아예 없고, rows[0]
   * 은 지난주가 됩니다. 월요일 아침의 기본 상태입니다.
   *
   * 그걸 "이번 주" 라고 부르면 남의 지난주 성적을 이번 주라고 말하는
   * 것이 됩니다. 같은 화면이 위에서는 "마지막 소식 · 1주 전" 이라고
   * 적으면서 바로 아래 카드는 같은 행을 "이번 주 일정" 이라 부르고
   * 있었습니다 — 화면이 자기 자신과 어긋나 있었습니다.
   *
   * 그래서 행의 weekStart 를 지금 주와 견줘서 이름을 붙입니다.
   * ---------------------------------------------------------------------- */

  /** 두 주 시작일 사이가 몇 주인가. 모르면 null.
   *  일수 반올림이 아니라 주 시작일끼리 빼서 셉니다 — 그래야
   *  "6일 23시간" 이 0주로, "7일 1분" 이 1주로 정확히 갈립니다. */
  function weeksAgo(weekStart) {
    if (!weekStart) return null;
    var a = S.weekStartOf(weekStart), b = S.weekStartOf();
    if (!a || !b) return null;
    var pa = a.split('-'), pb = b.split('-');
    var ta = Date.UTC(+pa[0], +pa[1] - 1, +pa[2]);
    var tb = Date.UTC(+pb[0], +pb[1] - 1, +pb[2]);
    return Math.round((tb - ta) / (7 * 86400000));
  }

  /** '이번 주' · '지난주' · 'N주 전'. 모르면 빈 문자열(붙이지 않습니다). */
  function weekLabel(weekStart) {
    var n = weeksAgo(weekStart);
    if (n == null) return '';
    if (n <= 0) return '이번 주';
    if (n === 1) return '지난주';
    return n + '주 전';
  }

  /** 이 행이 지금 주의 것인가 */
  function isThisWeek(row) { return !!row && weeksAgo(row.weekStart) === 0; }

  /* ===================== P14 계정 ===================== */
  A.register('P14', {
    title: '계정', label: '계정',
    render: function (wrap, ctx) {
      var me = B().currentUser();

      if (!me) {
        /* 로그인했었는데 토큰이 죽은 경우 (만료 · 다른 기기에서 전체
           로그아웃 · 서버 DB 교체 · 탈퇴). api() 가 조용히 로그아웃하는데,
           그 뒤로 이 기기에서 하는 일은 서버에 안 갑니다 — 특히 공유 끄기가
           그렇습니다. "로그인 / 가입" 만 보여 주면 사용자는 그냥 새 계정을
           만들 수도 있습니다. 무슨 일이 있었는지 먼저 말합니다. */
        if (global.MB_SYNC && global.MB_SYNC.status().disconnected) {
          wrap.appendChild(h('div.note.note--bad', { uid: 'P14-C08', uidLabel: '끊김 안내',
            text: '이 기기가 서버에서 끊겼습니다 — 로그인이 만료됐거나 다른 기기에서 ' +
                  '전체 로그아웃을 했습니다. 다시 로그인하기 전에는 여기서 바꾼 것이 ' +
                  '서버에 반영되지 않습니다. 공유를 껐다면 아직 안 껐다고 보세요.' }));
        }
        wrap.appendChild(h('div.card', { uid: 'P14-C06', uidLabel: '로그인 카드' }, [
          h('div.card__title', { text: '로그인' }),
          /* "기기를 바꿔도 기록이 남습니다" 라고 적혀 있었습니다. 거짓입니다.
             서버로 가는 것은 친구에게 보일 주간 요약과 친구 관계뿐이고,
             측정 기록은 한 번도 안 올라갑니다. 로그인을 백업이라고 믿게
             두면 정작 필요한 순간에 없습니다. */
          h('div.muted', { style: { marginTop: '6px' },
            text: '친구와 함께 하려면 필요합니다. 기록 백업은 아니에요 — ' +
                  '측정 기록은 이 기기에만 남습니다.' }),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '14px' } }, [
            h('button.btn.btn--primary.btn--block', { text: '로그인 / 가입',
              uid: 'P14-B01', uidLabel: '로그인',
              onClick: function () { global.MB_MODALS.signIn(function () { A.refresh(); }); } }),
            h('button.btn.btn--ghost.btn--block', { text: '서버 주소 바꾸기',
              uid: 'P14-B02', uidLabel: '서버 주소',
              onClick: function () { global.MB_MODALS.serverAddress(function () { A.refresh(); }); } })
          ])
        ]));
        /* 예전 문구는 "프로토타입이라 실제 인증은 하지 않습니다. 누르면 바로
           계정이 생깁니다" 였습니다. 서버가 scrypt 로 진짜 인증을 하게 된
           뒤로 거짓이 됐습니다. 보안에 대해 실제보다 허술하게 말하는 것도
           실제보다 튼튼하게 말하는 것만큼 나쁩니다 — 둘 다 사용자가 자기
           위험을 잘못 재게 만듭니다. */
        wrap.appendChild(h('div.note', { uid: 'P14-C02', uidLabel: '계정 안내',
          text: '이 서버가 계정을 직접 관리합니다. ' +
                ((global.MB_SYNC && global.MB_SYNC.status().openSignup) === true
                  ? '가입은 누구나 할 수 있고, '
                  : '가입에는 서버 주인에게 받은 가입 코드가 필요하고, ') +
                '비밀번호는 해시로만 저장됩니다. 메일은 보내지 않습니다 — 대신 가입할 때 복구 코드를 ' +
                '한 번 보여주니, 비밀번호를 잊으면 그 코드로 돌아옵니다.' }));
        // 예전 문구는 "자동으로 보이지 않습니다"였는데 blankShare() 가 streak: true 로
        // 시작하므로 거짓이었습니다. 프라이버시 앱에서 프라이버시 문구가 틀리면
        // 나머지 설명도 전부 못 믿게 됩니다.
        wrap.appendChild(h('div.note', { uid: 'P14-C03', uidLabel: '개인정보 안내' }, [
          h('div', { text: '체성분은 민감한 정보입니다. 친구를 맺으면 행동에 대한 셋만 기본으로 나가고(이번 주에 기록을 했는지, 계획한 날과 지킨 날의 개수, 오늘 식단), 체중·골격근·체지방은 친구마다 직접 켜야 나갑니다.' }),
          h('a', { text: '개인정보처리방침 보기', href: './privacy.html',
                   target: '_blank', rel: 'noopener',
                   uid: 'P14-B09', uidLabel: '개인정보처리방침',
                   style: { display: 'inline-block', marginTop: '8px',
                            fontSize: '13px', fontWeight: '700' } })
        ]));
        return;
      }

      wrap.appendChild(h('div.card', { uid: 'P14-C01', uidLabel: '내 계정' }, [
        h('div.card__head', [
          h('div', { style: { display: 'flex', alignItems: 'center', gap: '10px', minWidth: '0' } }, [
            UI.avatar(me, 44),
            h('div', { style: { minWidth: '0' } }, [
              h('div.card__sub', { text: ({ kakao: '카카오', apple: 'Apple', email: '이메일' })[me.provider] || me.provider }),
              h('div', { style: { fontSize: '18px', fontWeight: '800' }, text: me.displayName })
            ])
          ]),
          h('span.badge.badge--ok', { text: '로그인됨' })
        ]),
        avatarField(me),
        h('div.field', { style: { marginTop: '10px' } }, [
          h('div.field__label', { text: '표시 이름' }),
          nameInput(me)
        ]),
        h('div.kv', [h('span.kv__k', { text: '내 초대 코드' }),
                     h('span.kv__v', { style: { fontFamily: 'ui-monospace, monospace' }, text: me.inviteCode })]),
        h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--sm', { text: '로그아웃', uid: 'P14-B04', uidLabel: '로그아웃',
            onClick: function () {
              var S2 = global.MB_SYNC;
              var done = (S2 && S2.status().signedIn) ? S2.signOut() : Promise.resolve(B().signOut());
              done.then(function (r) {
                /* 못 보낸 것이 있으면 그렇다고 말합니다. 공유 끄기가
                   거기 섞여 있을 수 있고, 그건 껐다고 믿은 채로
                   계속 나간다는 뜻입니다. */
                if (r && r.unsent) {
                  global.MB_UID.toast('로그아웃했습니다 — 서버에 못 보낸 변경 ' +
                                      r.unsent + '건은 사라졌습니다. 다시 로그인해 확인하세요');
                } else {
                  global.MB_UID.toast('로그아웃했습니다');
                }
                A.refresh();
              });
            } }),
          h('button.btn.btn--sm', { text: '비밀번호 변경', uid: 'P14-B07', uidLabel: '비밀번호 변경',
            onClick: function () { global.MB_MODALS.changePassword(); } }),
          /* 서버에 로그인한 계정에만 복구 코드가 있습니다. 서버 없이
             이 기기에만 있는 계정에는 되찾을 것이 없습니다 — 버튼을
             보여 주면 눌렀을 때 "로그인이 필요합니다" 만 나옵니다. */
          serverSignedIn() ? h('button.btn.btn--sm', { text: '복구 코드 새로 받기',
            uid: 'P14-B08', uidLabel: '복구 코드 새로 받기',
            onClick: function () { global.MB_MODALS.newRecoveryCode(); } }) : null,
          /* 폰을 잃어버렸을 때 쓰는 버튼입니다. 서버는 이 기능을
             "토큰이 샜을 때의 유일한 복구 수단" 이라고 적어 뒀는데,
             그 유일한 수단에 누를 곳이 없었습니다. */
          serverSignedIn() ? h('button.btn.btn--sm', { text: '모든 기기에서 로그아웃',
            uid: 'P14-B12', uidLabel: '모든 기기에서 로그아웃',
            onClick: function () { global.MB_MODALS.signOutEverywhere(function () { A.refresh(); }); } }) : null
        ])
      ]));

      if (serverSignedIn()) {
        wrap.appendChild(h('div.note', { uid: 'P14-C07', uidLabel: '복구 코드 안내',
          text: '비밀번호를 잊었을 때 돌아올 길은 가입할 때 받은 복구 코드뿐입니다. ' +
                '적어 둔 곳이 기억나지 않으면 지금 새로 받아 두세요 — 옛 코드는 그때 못 쓰게 됩니다.' }));
      }

      wrap.appendChild(h('div.card', { uid: 'P14-C04', uidLabel: '동기화 상태' }, [
        h('div.card__title', { text: '동기화' }),
        h('div.muted', { style: { marginTop: '6px' },
          text: '측정 기록은 이 기기에 먼저 저장되고, 그다음 계정으로 올라갑니다. 인터넷이 없어도 앱은 그대로 동작합니다.' }),
        h('div.kv', { style: { marginTop: '8px' } },
          [h('span.kv__k', { text: '이 기기 기록' }),
           h('span.kv__v', { text: S.get().scans.length + '건' })]),
        /* 예전 문구는 "프로토타입에서는 실제로 올라가지 않습니다" 였습니다.
           sync.js 가 들어오면서 거짓이 됐고, 같은 카드 네 줄 위의 "그다음
           계정으로 올라갑니다" 와 정면으로 모순이었습니다. 프라이버시 문구가
           스스로 모순되면 나머지 설명도 전부 못 믿게 됩니다. */
        syncLine()
      ]));

      /** 지금 이 기기가 서버와 어떤 상태인지 — 짐작이 아니라 실제 상태를 읽습니다. */
      function syncLine() {
        var st = global.MB_SYNC ? global.MB_SYNC.status() : null;
        if (!st || !st.configured) {
          return h('div.note.note--warn', { style: { marginTop: '10px' },
            text: '서버 주소가 설정되지 않아 아직 아무것도 올라가지 않았습니다. 기록은 이 기기에만 있습니다.' });
        }
        if (st.reachable === false) {
          return h('div.note.note--bad', { style: { marginTop: '10px' },
            text: st.baseUrl + ' 에 닿지 않습니다. 서버가 꺼져 있거나 주소가 바뀌었습니다 — ' +
                  '그동안 바뀐 것은 이 기기에 쌓여 있다가 다시 닿으면 올라갑니다.' });
        }
        if (st.pending) {
          return h('div.note.note--warn', { style: { marginTop: '10px' },
            text: '아직 못 올린 변경이 ' + st.pending + '건 있습니다' +
                  (st.online ? ' — 곧 다시 보냅니다.' : ' — 인터넷이 연결되면 올라갑니다.') +
                  ' 공유를 끈 것도 여기에 들어 있으면, 서버에는 아직 안 닿았습니다.' });
        }
        /* 서버가 거절해서 버린 작업이 있었으면 말해 줍니다.
           예전엔 sync.js 안의 lastError 를 아무도 안 읽었습니다 —
           작업이 사라졌다는 사실 자체가 화면 어디에도 안 나왔습니다. */
        if (st.lastError) {
          return h('div.note.note--bad', { style: { marginTop: '10px' },
            text: '마지막 동기화에서 문제가 있었습니다 — ' + st.lastError +
                  '. 공유 설정을 바꿨다면 한 번 더 확인해 주세요.' });
        }
        /* 언제 맞춰 온 값인지.
           노트북이 자고 있으면 앱은 받아올 게 없는데, 화면은 아무 말
           없이 예전 값을 보여 줬습니다. 틀린 말을 확신을 갖고 하는
           것보다, 언제 것인지 같이 말하는 편이 낫습니다. */
        if (!st.lastPullAt) {
          return h('div.note.note--warn', { style: { marginTop: '10px' },
            text: '아직 서버에서 받아온 적이 없습니다. 아래 숫자는 이 기기에 있던 것입니다.' });
        }
        var ago = Math.round((Date.now() - Date.parse(st.lastPullAt)) / 60000);
        if (ago > 30) {
          return h('div.note.note--warn', { style: { marginTop: '10px' },
            text: '서버에서 마지막으로 받아온 지 ' +
                  (ago > 1440 ? Math.round(ago / 1440) + '일' : Math.round(ago / 60) + '시간') +
                  ' 됐습니다. 아래 친구 숫자는 그때 것입니다 — 서버가 꺼져 있을 수 있습니다.' });
        }
        return h('div.note.note--ok', { style: { marginTop: '10px' },
          text: '측정 기록이 ' + st.baseUrl + ' 로 올라가 있습니다. 사진은 올라가지 않습니다 — ' +
                '설정에서 자동 판독을 켜고 판독을 누를 때만 나갑니다.' });
      }

      wrap.appendChild(h('div.card', { uid: 'P14-C05', uidLabel: '계정 삭제' }, [
        h('div.card__title', { text: '계정 삭제' }),
        h('div.muted', { style: { marginTop: '6px' },
          text: '친구 관계와 공유한 내용이 모두 지워집니다. 이 기기의 기록은 남습니다.' }),
        h('button.btn.btn--danger.btn--sm', { text: '계정 삭제', style: { marginTop: '10px' },
          uid: 'P14-B06', uidLabel: '계정 삭제',
          onClick: function () { global.MB_MODALS.deleteAccount(function () { A.refresh(); }); } })
      ]));

      /** 목(mock) 계정이 아니라 진짜 서버에 로그인해 있는가 */
      function serverSignedIn() {
        var st = global.MB_SYNC ? global.MB_SYNC.status() : null;
        return !!(st && st.signedIn);
      }

      /* 프로필 사진 고르기.
         사진은 서버로 갑니다 — 친구가 봐야 하니까요. 그래서 여기서
         두 가지를 반드시 말합니다: 어디로 가는지, 그리고 위치정보가
         지워진다는 것. 폰 사진에는 대개 찍은 위치가 들어 있고,
         그게 프로필 사진에 붙어 친구의 서버로 가면 안 됩니다.
         photo.js 가 캔버스로 다시 그리면서 EXIF 를 통째로 버립니다. */
      function avatarField(user) {
        var msg = h('div.field__err', { style: { display: 'none' } });
        var input = h('input', { type: 'file', accept: 'image/*',
          uid: 'P14-F02', uidLabel: '프로필 사진 고르기',
          style: { display: 'none' },
          onChange: function () {
            var f = input.files && input.files[0];
            input.value = '';
            if (!f) return;
            msg.style.display = 'none';
            global.MB_PHOTO.avatarFromFile(f, function (err, out) {
              if (err) { msg.textContent = err.message; msg.style.display = ''; return; }
              save(out.dataUrl, '프로필 사진을 바꿨습니다');
            });
          } });

        function save(dataUrl, okMsg) {
          try {
            B().updateProfile({ avatar: dataUrl });
            global.MB_UID.toast(okMsg);
            A.refresh();
          } catch (e) {
            msg.textContent = e && e.message || '사진을 저장하지 못했습니다';
            msg.style.display = '';
          }
        }

        /* 사진을 또 그리지 않습니다 — 바로 위 카드 머리에 이미 있습니다.
           같은 얼굴이 한 화면에 두 번 있으면 둘 중 하나는 다른 것을
           뜻한다고 읽히고, 실제로는 아무 뜻도 없습니다. */
        return h('div.field', { style: { marginTop: '10px' } }, [
          h('div.field__label', { text: '프로필 사진' }),
          h('div.btn-row', [
            h('button.btn.btn--sm', {
              text: user.avatar ? '사진 바꾸기' : '사진 고르기',
              uid: 'P14-B10', uidLabel: '프로필 사진 고르기',
              onClick: function () { input.click(); } }),
            user.avatar ? h('button.btn.btn--sm', { text: '지우기',
              uid: 'P14-B11', uidLabel: '프로필 사진 지우기',
              onClick: function () { save(null, '프로필 사진을 지웠습니다'); } }) : null
          ]),
          input, msg,
          h('div.field__hint', { style: { marginTop: '6px' },
            text: '친구 목록에 보입니다. 서버에 저장됩니다 — ' +
            '192×192 로 줄이고 위치정보(EXIF)는 지운 뒤 보냅니다.' })
        ]);
      }

      function nameInput(user) {
        var i = h('input.input', { value: user.displayName, maxlength: '20',
          uid: 'P14-F01', uidLabel: '표시 이름',
          onChange: function () {
            B().updateProfile({ displayName: i.value.trim() || user.displayName });
            global.MB_UID.toast('이름을 바꿨습니다');
            A.refresh();
          } });
        return i;
      }

    }
  });

  /* --- 폰 알림 (P15-C27) -------------------------------------------------
   * 앱 안 소식(P15-C25)은 앱을 열어야 보입니다. 이건 잠금화면에 뜹니다.
   *
   * 못 켜는 이유를 하나로 뭉치지 않습니다 — https 가 아니라서인지,
   * 서버에 열쇠가 없어서인지, 브라우저에서 거절해 둬서인지에 따라
   * 할 일이 전혀 다릅니다. "알림을 켤 수 없습니다" 한 줄은 아무에게도
   * 도움이 안 됩니다.
   * -------------------------------------------------------------------- */
  function pushCard(wrap) {
    var P = global.MB_PUSH;
    if (!P) return;
    var st = P.state();

    /* 로그인도 안 한 사람에게 알림 이야기를 꺼내지 않습니다 —
       지금 할 일은 로그인이고, 그건 다른 카드가 말합니다. */
    if (!st.on && /로그인/.test(st.why || '')) return;

    var card = h('div.card', { uid: 'P15-C27', uidLabel: '폰 알림' }, [
      h('div.card__head', [
        h('div.card__title', { text: '폰 알림' }),
        h('div.card__sub', { text: st.on ? '켜짐' : '꺼짐' })
      ])
    ]);

    if (st.on) {
      card.appendChild(h('div.muted', {
        text: '친구가 운동을 체크하면 이 기기에 알림이 옵니다. ' +
              '안 한 것은 알림이 오지 않습니다 — 그렇게 만들어 뒀습니다.' }));
      card.appendChild(h('button.btn.btn--sm', { text: '알림 끄기',
        style: { marginTop: '10px' },
        uid: 'P15-B33', uidLabel: '알림 끄기',
        onClick: function () {
          P.disable().then(function () {
            global.MB_UID.toast('알림을 껐습니다');
            A.refresh();
          });
        } }));
    } else if (st.can) {
      card.appendChild(h('div.muted', {
        text: '친구가 운동을 체크하면 앱을 안 열어도 알림이 옵니다. ' +
              '오는 것은 "누가 운동했다" 뿐이고, 안 한 것은 오지 않습니다.' }));
      var err = h('div.field__err', { style: { display: 'none', marginTop: '8px' } });
      card.appendChild(h('button.btn.btn--sm.btn--primary', { text: '알림 켜기',
        style: { marginTop: '10px' },
        uid: 'P15-B34', uidLabel: '알림 켜기',
        onClick: function (e) {
          var btn = e.currentTarget;
          btn.disabled = true; err.style.display = 'none';
          P.enable().then(function (r) {
            btn.disabled = false;
            if (r.ok) { global.MB_UID.toast('알림을 켰습니다'); A.refresh(); }
            else { err.textContent = r.reason; err.style.display = ''; }
          });
        } }));
      card.appendChild(err);
    } else {
      /* 왜 안 되는지 그대로 적습니다. */
      card.appendChild(h('div.muted', { text: st.why }));
    }
    wrap.appendChild(card);
  }

  /* --- 친구 소식 카드 (P15-C25) ------------------------------------------
   * 소식은 기기 안에서 계산됩니다 (news.js). 서버에 소식 테이블 같은 것은
   * 없고, 이 카드 때문에 새로 나가는 정보도 없습니다 — 이미 공유 설정으로
   * 걸러져 온 "지킴 일수" 가 지난번보다 늘었는지만 봅니다.
   * -------------------------------------------------------------------- */
  function newsCard(wrap) {
    var N = global.MB_NEWS;
    if (!N) return;
    var items = N.list(8);
    if (!items.length) return;          // 소식이 없으면 빈 카드를 두지 않습니다

    /* 이름과 사진은 지금 친구 목록에서 찾습니다. 소식 줄에 박아 두면
       친구가 이름을 바꾼 뒤에도 옛 이름이 남습니다. */
    var who = {};
    try {
      B().listFriends().accepted.forEach(function (f) { who[f.id] = f; });
    } catch (e) {}

    var card = h('div.card', { uid: 'P15-C25', uidLabel: '친구 소식' }, [
      h('div.card__title', { text: '친구 소식' })
    ]);
    items.forEach(function (it, i) {
      card.appendChild(h('div', {
        uid: 'P15-L04#' + (i + 1), uidLabel: '소식 ' + (i + 1),
        style: { display: 'flex', alignItems: 'center', gap: '9px',
                 padding: '8px 0', borderBottom: '1px solid var(--border)' } }, [
        UI.avatar({ id: it.friendId,
                    displayName: (who[it.friendId] || {}).displayName || '친구',
                    avatar: (who[it.friendId] || {}).avatar || null }, 30),
        h('div', { style: { flex: '1', minWidth: '0' } }, [
          h('div', { style: { fontSize: '13px', fontWeight: '700' },
            text: ((who[it.friendId] || {}).displayName || '친구') + '님이 운동했습니다' }),
          /* 소식은 21일까지 남습니다. 그 줄에 "이번 주" 를 붙이면
             3주 전 운동이 방금 일어난 것처럼 읽힙니다. */
          h('div.muted', { text: (weekLabel(it.weekStart) || '그 주') + ' ' + it.keptDays + '일째' +
            (it.plannedDays ? ' · 계획 ' + it.plannedDays + '일' : '') })
        ]),
        h('div.muted', { style: { flex: 'none' }, text: ago(it.at) })
      ]));
    });
    /* 시각을 정직하게 적습니다. 친구가 언제 운동했는지는 모릅니다 —
       스냅샷에 그 시각이 없습니다. 아는 건 내가 언제 알게 됐는가뿐입니다. */
    card.appendChild(h('div.muted', { style: { marginTop: '10px' },
      text: '내 앱이 받아온 시각입니다. 친구가 언제 운동했는지는 앱이 모릅니다. ' +
            '폰 알림은 가지 않습니다 — 앱을 열 때 여기 쌓입니다.' }));
    wrap.appendChild(card);
    N.markRead();
  }

  function ago(iso) {
    var ms = Date.now() - new Date(iso).getTime();
    if (!isFinite(ms) || ms < 0) return '방금';
    var m = Math.floor(ms / 60000);
    if (m < 1) return '방금';
    if (m < 60) return m + '분 전';
    var hr = Math.floor(m / 60);
    if (hr < 24) return hr + '시간 전';
    return Math.floor(hr / 24) + '일 전';
  }

  /* =====================================================================
   * 공유 헬퍼 — P15 행 · P16 카드가 같은 함수를 씁니다.
   * 여기 버그가 나면 두 곳이 같이 틀리므로 한 군데만 있어야 합니다.
   * =================================================================== */

  /** allowed 에서 "켜진 공유 항목" 키만. updatedAt 같은 필드가 섞이므로 반드시 걸러야 합니다. */
  function allowedKeys(allowed) {
    if (!allowed) return [];
    return B().SHARE_FIELDS.filter(function (x) { return allowed[x.key]; }).map(function (x) { return x.key; });
  }

  /** 한 행에서 읽을 수 있는 값 조각들. 행에 실제로 있는 키만 씁니다. */
  function eventPieces(row) {
    if (!row) return [];
    var out = [];
    if (row.dBfmKg != null) out.push('체지방 ' + UI.sign(row.dBfmKg) + 'kg');
    if (row.dSmmKg != null) out.push('골격근 ' + UI.sign(row.dSmmKg) + 'kg');
    if (row.dWeightKg != null) out.push('체중 ' + UI.sign(row.dWeightKg) + 'kg');
    if (row.progressPct != null) out.push('목표 ' + row.progressPct + '%');
    return out;
  }

  /** 이 주 기록에 보여 줄 것이 하나라도 있는가.
   *
   * 예전엔 eventPieces() 의 길이로만 판정했습니다. 그 함수는 몸 숫자만
   * 읽어서, 일정만 공유하는 친구는 "아직 소식이 없습니다" 뒤에 영원히
   * 가려졌습니다 — 켜 둔 항목이 화면에 못 닿는 종류의 버그입니다. */
  function hasNews(row) {
    if (!row) return false;
    if (eventPieces(row).length) return true;
    if (row.plannedDays != null) return true;
    if (row.checkedIn != null) return true;
    return false;
  }

  /**
   * 체크인 점 스트립. 친구가 된 뒤의 주만 그립니다 —
   * 친구가 되기도 전의 주를 꺼진 점으로 채우면 그 친구가 빼먹은 주로 읽힙니다.
   */
  function dotStrip(rows, sinceISO, max) {
    var since = sinceISO ? new Date(sinceISO) : null;
    var use = (rows || []).filter(function (r) {
      if (r.checkedIn == null) return false;
      return !since || new Date(r.weekStart) >= new Date(since.getTime() - 7 * 86400000);
    });
    use = use.slice(-(max || 12));
    if (use.length < 2) return null;
    var box = h('div', { style: { display: 'flex', gap: '4px', marginTop: '6px' } });
    use.forEach(function (r) {
      box.appendChild(h('span', { style: {
        width: '6px', height: '6px', borderRadius: '50%',
        background: r.checkedIn ? 'var(--accent)' : 'var(--border)' } }));
    });
    return { el: box, total: use.length, on: use.filter(function (r) { return r.checkedIn; }).length };
  }

  /** 내가 이 친구에게 실제로 보내는 값. 켠 항목만 읽습니다 — 꺼진 항목은 쳐다보지도 않습니다. */
  function myOutgoingValues(me, fid) {
    var cur = B().getShare(me.id, fid);
    var on = B().SHARE_FIELDS.filter(function (x) { return cur[x.key]; });
    if (!on.length) return [];
    // weeklySnapshot() 은 절대 수치를 무조건 담고 있습니다. on 게이트를 빼고
    // snap 을 직접 훑으면 "상대가 보는 화면"이라는 라벨 아래 상대가 못 보는 kg 이 찍힙니다.
    var snap = S.weeklySnapshot();
    var out = [];
    on.forEach(function (x) {
      var v;
      if (x.key === 'streak') v = snap.checkedIn ? '이번 주 기록함' : '이번 주 아직';
      else if (x.key === 'schedule') v = snap.plannedDays == null ? '이번 주 정한 날 없음'
        : '계획 ' + snap.plannedDays + '일 · 지킴 ' + snap.keptDays + '일';
      else if (x.key === 'planProgress') v = snap.progressPct == null ? '아직 값 없음' : snap.progressPct + '%';
      else if (x.key === 'diet') v = snap.today && snap.today.logged ? '오늘 ' + snap.today.kcal + ' kcal' : '오늘 기록 없음';
      else if (x.key === 'absolute') {
        var bits = [];
        if (cur.weightTrend && snap.weightKg != null) bits.push('체중 ' + UI.n1(snap.weightKg) + 'kg');
        if (cur.smmTrend && snap.smmKg != null) bits.push('골격근 ' + UI.n1(snap.smmKg) + 'kg');
        if (cur.bfmTrend && snap.bfmKg != null) bits.push('체지방 ' + UI.n1(snap.bfmKg) + 'kg');
        v = bits.length ? bits.join(' · ') : '아직 값 없음';
      } else {
        var map = { weightTrend: 'dWeightKg', smmTrend: 'dSmmKg', bfmTrend: 'dBfmKg' };
        var d = snap[map[x.key]];
        v = d == null ? '아직 값 없음' : UI.sign(d) + 'kg';
      }
      out.push({ key: x.key, label: x.label, value: v });
    });
    return out;
  }

  /* ===================== P15 친구 (탭 루트) ===================== */
  A.register('P15', {
    title: '친구', label: '친구',
    render: function (wrap, ctx) {
      var me = B().currentUser();
      if (!me) return loggedOut(wrap);

      var f = B().listFriends();

      /* --- C25 친구 소식 -------------------------------------------------
         "운동 해서 체크하면 친구한테 알림" 의 받는 쪽입니다.

         여기 흐르는 것은 **늘어난 것뿐**입니다 (news.js). "안 했다" 는
         구조적으로 이 목록에 들어올 수 없습니다 — 못 만든 게 아니라
         만들 수 없게 만들어 뒀습니다. 그래서 이 카드는 열어 볼 때
         마음이 무거워지지 않습니다.

         읽으면 탭 점이 꺼집니다. 개수는 어디에도 안 씁니다 — 숫자를
         붙이는 순간 내가 이번 주에 몇 번 갔는지와 나란히 놓입니다. */
      newsCard(wrap);
      pushCard(wrap);

      /* --- C21 새로 맺어진 친구 — 내가 이 관계의 공유를 한 번도 안 건드렸을 때 --- */
      f.accepted.filter(function (r) {
        return r.iShare.settings.updatedAt == null;
      }).slice(0, 3).forEach(function (r, i) {
        var n = i + 1;
        wrap.appendChild(h('div.card.card--accent', { uid: 'P15-C21#' + n, uidLabel: '새 친구 안내 ' + n }, [
          h('div.card__title', { text: r.displayName + '님과 친구가 되었습니다' }),
          /* 본문을 고정 문구로 두면 언젠가 기본값과 어긋납니다 —
             실제로 켜져 있는 것을 읽어서 씁니다. 이 카드가 뜨는 조건이
             "아직 아무것도 안 골랐다" 라서 지금은 기본값과 같지만,
             기본값이 바뀌는 날 이 문장만 옛말을 하고 있게 둘 수는 없습니다. */
          h('div.muted', { style: { marginTop: '6px' },
            text: (function () {
              /* 라벨 문자열로 분류하지 않습니다 — 라벨은 문구라서 바뀝니다.
                 kind 로 나눕니다: streak · schedule 이 행동, 나머지가 몸. */
              var set = r.iShare.settings || {};
              var onF = B().SHARE_FIELDS.filter(function (x) { return set[x.key] === true; });
              if (!onF.length) {
                return '지금 ' + r.displayName + '님 화면에 보이는 것은 없습니다. ' +
                       '보여주고 싶은 것이 있으면 직접 켜세요.';
              }
              var bodyF = onF.filter(function (x) {
                return x.kind !== 'streak' && x.kind !== 'schedule';
              });
              return '지금 ' + r.displayName + '님 화면에 보이는 것은 ' +
                     onF.map(function (x) { return x.label; }).join(' · ') + ' 입니다. ' +
                     (bodyF.length
                       ? '몸에 대한 숫자(' + bodyF.map(function (x) { return x.label; }).join(' · ') +
                         ')가 켜져 있습니다.'
                       : '몸에 대한 숫자는 켜기 전까지 안 보입니다.');
            })() }),
          // 세 버튼은 같은 크기·같은 무게입니다. 아무것도 안 켜는 것이
          // 손해가 아니라는 걸 버튼 생김새로 말합니다.
          h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
            h('button.btn.btn--sm', { text: '보낼 것 고르기',
              uid: 'P15-B25#' + n, uidLabel: '보낼 것 고르기 ' + n,
              onClick: function () {
                B().setShare(r.id, {});            // 모달을 그냥 닫아도 카드가 다시 안 뜨게
                global.MB_MODALS.shareWith(r, function () { A.refresh(); });
              } }),
            h('button.btn.btn--sm', { text: '그 둘도 끄기',
              uid: 'P15-B26#' + n, uidLabel: '기본 항목도 끄기 ' + n,
              onClick: function () {
                B().setShare(r.id, { streak: false, schedule: false });
                A.refresh();
              } }),
            h('button.btn.btn--sm', { text: '이대로 두기',
              uid: 'P15-B27#' + n, uidLabel: '이대로 두기 ' + n,
              onClick: function () { B().setShare(r.id, {}); A.refresh(); } })
          ])
        ]));
      });

      /* --- L02 받은 요청 --- */
      if (f.incoming.length) {
        var inc = h('div.card', { uid: 'P15-L02', uidLabel: '받은 요청' }, [
          h('div.card__title', { text: '받은 요청 ' + f.incoming.length + '건' })
        ]);
        f.incoming.forEach(function (r, i) {
          inc.appendChild(h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px',
            padding: '8px 0', borderBottom: '1px solid var(--border)' } }, [
            h('div', { style: { flex: '1', fontWeight: '700' }, text: r.displayName }),
            h('button.btn.btn--sm.btn--primary', { text: '수락',
              uid: 'P15-B03#' + (i + 1), uidLabel: '요청 수락 ' + (i + 1),
              onClick: function () { B().accept(r.id); global.MB_UID.toast('친구가 되었습니다'); A.refresh(); } }),
            h('button.btn.btn--sm', { text: '거절',
              uid: 'P15-B04#' + (i + 1), uidLabel: '요청 거절 ' + (i + 1),
              onClick: function () { B().decline(r.id); A.refresh(); } })
          ]));
        });
        // 수락 전에 무엇이 기본으로 나가는지 말하는 자리가 지금까지 없었습니다.
        inc.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: '수락하면 행동에 대한 셋이 기본으로 나갑니다 — 이번 주에 기록을 했는지, ' +
                '이번 주 일정의 숫자 네 개(하기로 한 날 · 지킨 날 · 지나갔는데 ' +
                '체크가 없는 날 · 아직 남은 날), 그리고 오늘 식단(칼로리 · 탄단지). ' +
                '몸에 대한 숫자는 직접 켜야 나갑니다.' }));
        wrap.appendChild(inc);
      }

      /* --- C20 노출 바 — 지금 나가는 것 ---
         제목이 "내 몸에서 나가는 것" 이었는데, 이제 여기 운동 일정도
         들어옵니다. 일정은 몸이 아니라 행동입니다 — 제목이 항목보다
         좁으면 목록에 있는 것을 사람이 안 읽고 넘깁니다. */
      if (f.accepted.length) wrap.appendChild(exposureBar(f));

      /* --- L01 친구 목록 --- */
      var list = h('div', { uid: 'P15-L01', uidLabel: '친구 목록' });
      if (!f.accepted.length) {
        list.appendChild(h('div.empty', { uid: 'P15-S01', uidLabel: '친구 없음' }, [
          h('div.empty__ico', { text: '👥' }),
          h('div.empty__t', { text: '아직 친구가 없습니다' }),
          h('div.empty__d', { text: '초대 코드를 아는 사람만 추가됩니다. 아래 코드를 알려주거나, 받은 코드로 요청을 보내세요.' })
        ]));
      } else {
        list.appendChild(h('div.section-title', { text: '친구 ' + f.accepted.length + '명' }));
        f.accepted.forEach(function (r, i) { list.appendChild(friendRow(r, i + 1)); });
      }
      wrap.appendChild(list);

      /* --- C01 내 초대 코드 --- */
      var codeEl;   /* 복사가 막힌 자리(http 로 열었을 때)에서 값을 골라 줍니다 */
      wrap.appendChild(h('div.card.card--accent', { uid: 'P15-C01', uidLabel: '내 초대 코드' }, [
        h('div.card__sub', { text: '이 코드를 친구에게 알려주세요' }),
        codeEl = h('div', { style: { fontSize: '26px', fontWeight: '900', letterSpacing: '.12em',
                            fontFamily: 'ui-monospace, monospace', margin: '6px 0', userSelect: 'all' },
                   text: me.inviteCode }),
        h('div.btn-row', [
          h('button.btn.btn--sm', { text: '코드 복사', uid: 'P15-B01', uidLabel: '초대 코드 복사',
            onClick: function () {
              /* 예전엔 clipboard 가 없어도 "복사했습니다" 라고 했습니다.
                 친구를 추가하는 유일한 길인데, 복사된 줄 알고 카톡에
                 붙여넣으면 엉뚱한 게 갑니다. */
              UI.copyText(me.inviteCode, { el: codeEl });
            } }),
          h('button.btn.btn--sm.btn--primary', { text: '친구 추가', uid: 'P15-B02', uidLabel: '친구 추가',
            onClick: function () { global.MB_MODALS.addFriend(function () { A.refresh(); }); } })
        ]),
        h('div.muted', { style: { marginTop: '8px' },
          text: '전화번호나 이메일로는 찾을 수 없습니다. 코드를 직접 알려준 사람만 추가됩니다.' })
      ]));

      /* --- 데모 친구 (개발 빌드 전용) ---
         이 친구는 이 기기 안에만 있고 서버에는 없습니다. 화면이 어떻게
         보이는지 확인하려고 만든 것이라, 쓰는 사람 화면에 있으면 자기
         친구 목록에 진짜가 섞인 건지 알 방법이 없습니다. */
      if (!f.accepted.length && global.MB_BUILD.tools) {
        wrap.appendChild(h('div.note', { uid: 'P15-C26', uidLabel: '데모 친구 안내' }, [
          h('div', { text: '데모 친구를 만들어 친구 화면이 어떻게 보이는지 볼 수 있습니다. 실제 서버에는 없습니다.' }),
          h('button.btn.btn--ghost.btn--sm', { text: '데모 친구 만들기', style: { marginTop: '8px' },
            uid: 'P15-B23', uidLabel: '데모 친구 만들기',
            onClick: function () {
              if (makeDemoFriend()) { global.MB_UID.toast('데모 친구를 만들었습니다'); A.refresh(); }
            } })
        ]));
      }

      /* --- L03 보낸 요청 — 취소할 수 있어야 합니다 --- */
      if (f.outgoing.length) {
        var out = h('div.card.card--flat', { uid: 'P15-L03', uidLabel: '보낸 요청' }, [
          h('div.card__sub', { text: '보낸 요청 ' + f.outgoing.length + '건 · 수락을 기다리는 중' })
        ]);
        f.outgoing.forEach(function (r, i) {
          out.appendChild(h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px',
            padding: '8px 0', borderTop: '1px solid var(--border)' } }, [
            h('div', { style: { flex: '1' }, text: r.displayName }),
            h('button.btn.btn--sm', { text: '취소',
              uid: 'P15-B28#' + (i + 1), uidLabel: '요청 취소 ' + (i + 1),
              onClick: function () { B().decline(r.id); global.MB_UID.toast('요청을 취소했습니다'); A.refresh(); } })
          ]));
        });
        wrap.appendChild(out);
      }

      /* --- C02 공유 원칙 --- */
      wrap.appendChild(h('div.note', { uid: 'P15-C02', uidLabel: '공유 원칙',
        text: '친구를 맺으면 행동에 대한 셋만 기본으로 나갑니다 — 이번 주에 기록을 했는지, ' +
              '이번 주 일정의 숫자 네 개(하기로 한 날 · 지킨 날 · 지나갔는데 체크가 없는 날 · ' +
              '아직 남은 날), 오늘 식단(칼로리 · 탄단지). 체중·골격근·체지방·달성률은 친구마다 직접 켜야 나갑니다.' }));

      /* ---------------- 조각 ---------------- */

      function exposureBar(fr) {
        var counts = {}, withAny = 0;
        fr.accepted.forEach(function (r) {
          var s2 = r.iShare.settings, any = false;
          B().SHARE_FIELDS.forEach(function (fl) {
            if (s2[fl.key]) { counts[fl.key] = (counts[fl.key] || 0) + 1; any = true; }
          });
          if (any) withAny++;
        });
        var on = Object.keys(counts);
        if (!on.length) {
          return h('div.note', { uid: 'P15-C20', uidLabel: '노출 바',
            text: '🔒 지금 아무 친구에게도 아무것도 나가지 않습니다.' });
        }
        var chips = h('div.chips', on.map(function (k, i) {
          var fl = B().SHARE_FIELDS.filter(function (x) { return x.key === k; })[0];
          // P15 의 칩에는 ✕ 가 없습니다. 누르면 누가 보는지 열릴 뿐 아무것도 안 꺼집니다.
          // P16 의 칩에는 ✕ 가 있고 그 친구 하나만 끕니다. 생김새가 다르고 동작이 다릅니다.
          return h('button.chip.is-on', { text: fl.label + ' · ' + counts[k] + '명',
            uid: 'P15-B24#' + (i + 1), uidLabel: fl.label + ' 누가 보나',
            onClick: function () { global.MB_MODALS.whoSees(k, function () { A.refresh(); }); } });
        }));
        return h('div.card.card--accent', { uid: 'P15-C20', uidLabel: '노출 바' }, [
          h('div.card__head', [
            h('div.card__title', { text: '지금 나가는 것' }),
            h('div.card__sub', { text: '친구 ' + fr.accepted.length + '명 중 ' + withAny + '명에게' })
          ]),
          chips,
          h('div.muted', { style: { marginTop: '8px' },
            text: '칩을 누르면 누가 보고 있는지 보고, 거기서 끌 수 있습니다.' })
        ]);
      }

      function friendRow(r, n) {
        var res = B().getFriendSnapshots(r.id, 12);
        var rows = res.rows || [];
        var latest = rows.length ? rows[0] : null;   // getFriendSnapshots 는 최신순
        var onKeys = allowedKeys(res.allowed);

        // 2줄 — 받는 것
        var pieces = eventPieces(latest);
        var line2, extra = null;
        if (pieces.length) {
          line2 = '나에게 · ' + pieces.slice(0, 2).join(' · ');
        } else if (!onKeys.length) {
          line2 = '아직 보여주는 항목이 없습니다';
        } else if (!rows.length) {
          line2 = '아직 올라온 기록이 없습니다';
        } else {
          var strip = dotStrip(rows, r.since, 12);
          if (strip) {
            line2 = '최근 ' + strip.total + '주 중 ' + strip.on + '주 기록';
            extra = strip.el;
          } else {
            line2 = '친구가 된 지 얼마 안 됐습니다';
          }
        }

        /* 일정 줄. 공유가 꺼진 친구에게는 줄 자체가 없습니다 —
           "비공개" 같은 회색 표시를 두면 "이 사람은 숨기고 있다" 로
           읽힙니다. 안 켠 것과 숨기는 것은 다릅니다. */
        var schedLine = null;
        if (latest && latest.plannedDays != null) {
          /* 라벨은 그 행의 주에서 가져옵니다. 친구가 이번 주에 아직 앱을
             안 열었으면 이 행은 지난주 것이고, 그걸 "이번 주" 라고 부르면
             남의 지난주를 이번 주라고 말하는 것이 됩니다. */
          schedLine = (weekLabel(latest.weekStart) || '최근') +
                      ' 계획 ' + latest.plannedDays + '일 · 지킴 ' + (latest.keptDays || 0) + '일';
          /* 체크 없는 날을 여기까지 올립니다. 사용자가 요청한 "확인" 이
             친구를 한 명씩 열어 봐야만 되면, 확인하려는 사람은 결국
             매일 다섯 화면을 돌게 됩니다 — 그게 더 감시에 가깝습니다.
             숫자는 이미 와 있고, 한 조각 더 적는 것뿐입니다. */
          if (latest.missedDays) schedLine += ' · 체크 없는 날 ' + latest.missedDays + '일';
        }

        // 3줄 — 보내는 것. 개수 배지("내가 공유 2개")는 없앴습니다 —
        // 숫자 2 는 그 자체로 아무 뜻이 없고, 2줄과 형태가 달라 방향이 안 읽혔습니다.
        var line3 = r.iShare.count
          ? '내가 보내는 것 · ' + r.iShare.labels.slice(0, 2).join(', ') +
            (r.iShare.count > 2 ? ' 외 ' + (r.iShare.count - 2) : '')
          : '🔒 내가 보내는 것 없음';

        var isDemo = (S.get().settings || {}).demoFriendId === r.id;
        var card = h('div.card', {
          uid: 'P15-C22#' + n, uidLabel: '친구 ' + n,
          style: { cursor: 'pointer' },
          onClick: function () { A.go('P16', { friendId: r.id }); }
        }, [
          h('div', { style: { display: 'flex', alignItems: 'center', gap: '9px' } }, [
            UI.avatar(r, 36),
            h('div.card__title', { style: { flex: '1', minWidth: '0' }, text: r.displayName }),
            isDemo ? h('span.chip', { text: '데모' }) : null
          ]),
          h('div.muted', { style: { marginTop: '2px' }, text: line2 }),
          extra,
          schedLine ? h('div.muted', { style: { marginTop: '2px' }, text: schedLine }) : null,
          h('div.muted', { style: { marginTop: '2px' }, text: line3 })
        ]);
        if (isDemo) {
          card.appendChild(h('button.btn.btn--ghost.btn--sm', { text: '데모 지우기',
            style: { marginTop: '8px' }, uid: 'P15-B32', uidLabel: '데모 친구 지우기',
            onClick: function (e) {
              e.stopPropagation();
              B().removeFriend(r.id);
              S.set({ settings: Object.assign({}, S.get().settings, { demoFriendId: null }) });
              A.refresh();
            } }));
        }
        return card;
      }

      function loggedOut(w) {
        // 탭을 숨기거나 다른 화면으로 튕기지 않습니다. 왜 비었는지 여기서 설명합니다.
        w.appendChild(h('div.card', { uid: 'P15-S02', uidLabel: '로그인 안내' }, [
          h('div.card__title', { text: '🔑 친구 기능은 계정이 있어야 합니다' }),
          /* 여기는 동의를 받는 자리입니다. 원래 "로그인해도 몸에 대한
             숫자는 자동으로 나가지 않습니다" 라고 적혀 있었는데 거짓이었습니다 —
             로그인하면 친구가 하나도 없어도 가장 최근 측정의 절대값이
             서버에 저장됩니다. 친구별 스위치가 정하는 것은 "친구 화면에
             무엇이 보이는가" 이지 "서버에 무엇이 올라가는가" 가 아닙니다.
             설정 화면(P12-C04)은 이미 사실대로 적고 있었고, 하필 동의를
             받는 이 화면만 반대로 말하고 있었습니다. */
          h('div.muted', { style: { marginTop: '6px' },
            text: '로그인하면 내 기록(측정 · 목표 · 계획 · 식단)이 내 계정에도 저장됩니다. ' +
                  '친구에게 보이는 것은 친구마다 직접 켠 항목뿐이고, ' +
                  '기본으로 보이는 것은 행동에 대한 셋뿐입니다 — 이번 주에 기록을 했는지, ' +
                  '이번 주 일정의 숫자 네 개(하기로 한 날 · 지킨 날 · 지나갔는데 ' +
                  '체크가 없는 날 · 아직 남은 날), 오늘 식단(칼로리 · 탄단지).' }),
          h('div', { style: { marginTop: '6px' } }, [
            h('a', { text: '무엇이 어디로 가는지 자세히 (개인정보처리방침)',
                     href: './privacy.html', target: '_blank', rel: 'noopener',
                     uid: 'P15-B22', uidLabel: '개인정보처리방침',
                     style: { fontSize: '13px', fontWeight: '700' } })
          ]),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '14px' } }, [
            h('button.btn.btn--primary.btn--block', { text: '로그인 / 가입',
              uid: 'P15-B20', uidLabel: '로그인',
              onClick: function () { global.MB_MODALS.signIn(function () { A.refresh(); }); } }),
            h('button.btn.btn--ghost.btn--block', { text: '서버 주소 바꾸기',
              uid: 'P15-B21', uidLabel: '서버 주소',
              onClick: function () { global.MB_MODALS.serverAddress(function () { A.refresh(); }); } })
          ]),
          serverLine()
        ]));
        w.appendChild(h('div.card.card--flat', { uid: 'P15-C24', uidLabel: '보낼 수 있는 것' }, [
          h('div.card__title', { text: '친구에게 보낼 수 있는 것' }),
          h('div.chips', { style: { marginTop: '8px' } },
            B().SHARE_FIELDS.map(function (x) { return h('span.chip', { text: x.label }); })),
          h('div.muted', { style: { marginTop: '8px' },
            text: '기본으로 켜진 것은 행동에 대한 셋(이번 주 기록 여부 · 이번 주 일정 숫자 네 개 · 오늘 식단)뿐이고, ' +
                  '몸에 대한 항목은 친구마다 하나씩 직접 켭니다. 안 켠 항목은 상대 화면에 존재하지도 않습니다.' })
        ]));
        w.appendChild(h('div.note', { uid: 'P15-C02', uidLabel: '공유 원칙',
          text: '친구 찾기는 초대 코드로만 됩니다. 전화번호나 이메일로는 찾을 수 없습니다.' }));

        /** 지금 어느 서버를 보고 있는지 — 자가호스팅이라 이게 보여야 합니다. */
        function serverLine() {
          var st = global.MB_SYNC ? global.MB_SYNC.status() : { configured: false };
          /* 주소만 보고 "서버: ..." 라고 적으면, 미리보기 링크에서는
             claude.ai 가 내 서버인 것처럼 보입니다. 닿는지까지 봅니다. */
          if (!st.configured) {
            return h('div.muted', { style: { marginTop: '10px' },
              text: '서버가 설정되지 않았습니다. 이 기기에만 저장됩니다.' });
          }
          if (st.reachable === false) {
            return h('div.note.note--warn', { style: { marginTop: '10px' },
              text: (st.ownServer && st.serverKind === 'down')
                ? st.baseUrl + ' 에 닿지 않습니다. 컴퓨터가 꺼져 있거나 서버를 멈춘 것 같습니다. ' +
                  '주소는 그대로 두세요 — 바꾸면 그동안의 기록이 안 보이게 됩니다.'
                : st.baseUrl + ' 에 이 앱의 서버가 없습니다. 미리보기로 열었거나 ' +
                  '주소가 틀립니다 — 친구 기능은 서버가 있어야 됩니다.' });
          }
          return h('div.muted', { style: { marginTop: '10px' }, text: '서버: ' + st.baseUrl });
        }
      }
    }
  });

  /* ===================== P16 친구 한 사람 ===================== */
  A.register('P16', {
    label: '친구 상세',
    // 레지스트리 객체의 title 을 덮어쓰면 없는 친구로 들어갔을 때
    // 앱바에 이전 친구 이름이 남습니다. 함수로 둡니다.
    title: function (p) {
      try {
        var me = B().currentUser();
        if (!me || !p || !p.friendId) return '친구';
        var r = B().listFriends().accepted.filter(function (x) { return x.id === p.friendId; })[0];
        return r ? r.displayName : '친구';
      } catch (e) { return '친구'; }
    },
    render: function (wrap, ctx) {
      var me = B().currentUser();
      if (!me) {
        // 튕기지 않습니다. 왜 비었는지 여기서 설명하고 돌아갈 길만 줍니다.
        wrap.appendChild(h('div.empty', { uid: 'P16-S03', uidLabel: '로그인 필요' }, [
          h('div.empty__ico', { text: '🔑' }),
          h('div.empty__t', { text: '로그인이 필요합니다' }),
          h('div.empty__d', { text: '친구 기능은 계정이 있어야 씁니다.' }),
          h('button.btn.btn--primary', { text: '친구 탭으로', uid: 'P16-B03', uidLabel: '친구 탭으로',
            onClick: function () { A.go('P15'); } })
        ]));
        return;
      }
      var fid = ctx.params.friendId;
      var friend = B().listFriends().accepted.filter(function (r) { return r.id === fid; })[0];

      if (!friend) {
        wrap.appendChild(h('div.empty', { uid: 'P16-S01', uidLabel: '친구 없음' }, [
          h('div.empty__ico', { text: '👤' }),
          h('div.empty__t', { text: '이 친구는 목록에 없습니다' }),
          h('div.empty__d', { text: '끊겼거나 상대가 계정을 지웠을 수 있습니다.' }),
          h('button.btn.btn--primary', { text: '친구 목록', uid: 'P16-B04', uidLabel: '친구 목록으로',
            onClick: function () { A.go('P15'); } })
        ]));
        return;
      }

      var res = B().getFriendSnapshots(fid, 26);
      var rows = res.rows || [];
      var onKeys = allowedKeys(res.allowed);
      var latest = rows.length ? rows[0] : null;

      /* --- C01 헤더 --- */
      var lastNews = null;
      if (latest) {
        /* 경과 시간을 7로 나눠 반올림하면 주 경계와 어긋납니다 —
           월요일 아침의 지난주 행이 "0주" 로 반올림돼 "이번 주" 가 됐습니다.
           주 시작일끼리 견주면 그 경계가 정확합니다. */
        lastNews = '마지막 소식 · ' + (weekLabel(latest.weekStart) || '언제인지 모름');
      }
      wrap.appendChild(h('div.card', { uid: 'P16-C01', uidLabel: '친구 헤더' }, [
        h('div.card__head', [
          h('div', { style: { display: 'flex', alignItems: 'center', gap: '10px', minWidth: '0' } }, [
            UI.avatar(friend, 44),
            h('div', { style: { minWidth: '0' } }, [
              h('div', { style: { fontSize: '18px', fontWeight: '800' }, text: friend.displayName }),
              h('div.card__sub', { text: UI.dateK(friend.since) + ' 부터 친구' })
            ])
          ]),
          lastNews ? h('span.badge', { text: lastNews }) : null
        ])
      ]));

      /* --- C20 노출 바 (내가 → 이 친구) --- */
      var mine = myOutgoingValues(me, fid);
      if (!mine.length) {
        var note = h('div.note', { uid: 'P16-C20', uidLabel: '노출 바' }, [
          h('div', { text: '🔒 ' + friend.displayName + '님에게는 아무것도 나가지 않습니다.' }),
          h('button.btn.btn--sm', { text: '보낼 것 고르기', style: { marginTop: '8px' },
            uid: 'P16-B01', uidLabel: '보낼 것 고르기',
            onClick: function () { global.MB_MODALS.shareWith(friend, function () { A.refresh(); }); } })
        ]);
        wrap.appendChild(note);
      } else {
        var card = h('div.card.card--accent', { uid: 'P16-C20', uidLabel: '노출 바' }, [
          h('div.card__title', { text: friend.displayName + '님에게 지금 나가는 것' })
        ]);
        card.appendChild(h('div.chips', { style: { margin: '8px 0' } }, mine.map(function (m, i) {
          return h('button.chip.is-on', { text: m.label + ' ✕',
            uid: 'P16-B22#' + (i + 1), uidLabel: m.label + ' 끄기',
            onClick: function () {
              var before = B().getShare(me.id, fid);
              var o = {}; o[m.key] = false;
              B().setShare(fid, o);
              var after = B().getShare(me.id, fid);
              /* 완료형으로 단정하지 않습니다 — setShare 는 큐를 탈 뿐이고,
                 오프라인이면 아직 안 갔고 토큰이 죽었으면 영영 안 갑니다.
                 판단은 MB_SYNC 한 곳에서 합니다. */
              global.MB_UID.toast(m.label + '을 껐습니다 — ' +
                (global.MB_SYNC ? global.MB_SYNC.deliveryNote(friend.displayName)
                                : friend.displayName + '님 화면에서 사라졌습니다'));
              if (before.absolute && !after.absolute && m.key !== 'absolute') {
                global.MB_UID.toast('실제 수치까지도 함께 꺼졌습니다');
              }
              A.refresh();
            } });
        })));
        // .kv 줄이 곧 미리보기입니다. 상대가 보는 것과 같은 값이어야 합니다.
        mine.forEach(function (m) {
          card.appendChild(h('div.kv', [h('span.kv__k', { text: m.label }),
                                        h('span.kv__v', { text: m.value })]));
        });
        card.appendChild(h('button.btn.btn--sm', { text: '보낼 것 고르기', style: { marginTop: '10px' },
          uid: 'P16-B01', uidLabel: '보낼 것 고르기',
          onClick: function () { global.MB_MODALS.shareWith(friend, function () { A.refresh(); }); } }));
        wrap.appendChild(card);
      }

      /* --- 상대가 보여주는 것 --- */
      var weeksKnown = weeksAgo(friend.since);
      if (weeksKnown == null) weeksKnown = 0;
      if (!onKeys.length) {
        wrap.appendChild(h('div.empty', { uid: 'P16-S02', uidLabel: '상대가 항목 미선택' }, [
          h('div.empty__ico', { text: '🔒' }),
          h('div.empty__t', { text: friend.displayName + '님은 아직 보여줄 항목을 고르지 않았습니다' }),
          h('div.empty__d', { text: '무엇을 보여줄지는 각자가 정합니다.' })
        ]));
      } else if (!rows.length) {
        var labels = B().SHARE_FIELDS.filter(function (x) { return onKeys.indexOf(x.key) >= 0; })
          .map(function (x) { return x.label; }).join('·');
        wrap.appendChild(h('div.empty', { uid: 'P16-S20', uidLabel: '기록 없음' }, [
          h('div.empty__ico', { text: '⏳' }),
          h('div.empty__t', { text: friend.displayName + '님이 ' + labels + '을 보여주기로 했습니다' }),
          h('div.empty__d', { text: '아직 올라온 주 기록이 없습니다. ' + friend.displayName + '님이 앱에서 무언가를 기록하면 여기 나타납니다.' })
        ]));
      } else if (!hasNews(latest) && weeksKnown < 2) {
        wrap.appendChild(h('div.empty', { uid: 'P16-S21', uidLabel: '새 관계' }, [
          h('div.empty__t', { text: (weekLabel(friend.since) || '최근') + '에 친구가 되었습니다' }),
          h('div.empty__d', { text: '기록은 주마다 하나씩 쌓입니다.' })
        ]));
      } else {
        var keys = [
          { k: 'dBfmKg', label: '체지방', color: 'var(--fat)', abs: 'bfmKg' },
          { k: 'dSmmKg', label: '골격근', color: 'var(--muscle)', abs: 'smmKg' },
          { k: 'dWeightKg', label: '체중', color: 'var(--weight)', abs: 'weightKg' }
        ].filter(function (x) { return latest[x.k] != null; });

        if (keys.length) {
          wrap.appendChild(h('div.card', { uid: 'P16-C02', uidLabel: '최근 변화' }, [
            h('div.card__title', { text: '최근 변화' }),
            h('div.stats', { style: { marginTop: '8px' } }, keys.map(function (x) {
              return h('div.stat', [
                h('div.stat__k', { text: x.label }),
                h('div', [h('span.stat__v', { style: { color: x.color }, text: UI.sign(latest[x.k]) }),
                          h('span.stat__u', { text: 'kg' })]),
                latest[x.abs] != null
                  ? h('div.muted', { text: '지금 ' + UI.n1(latest[x.abs]) + 'kg' }) : null
              ]);
            })),
            // 이 한 줄이 필수입니다. 델타는 "직전 두 스캔의 차이"라서,
            // 3개월 간격 인바디면 그 값은 주간 변화가 아닙니다.
            h('div.muted', { style: { marginTop: '10px' },
              text: '마지막 두 측정 사이의 변화입니다. 주간 변화가 아닙니다.' })
          ]));
        }

        if (latest.progressPct != null) {
          wrap.appendChild(h('div.card', { uid: 'P16-C04', uidLabel: '친구 달성률' }, [
            h('div.card__title', { text: '목표 달성률' }),
            h('div', { style: { display: 'flex', gap: '14px', alignItems: 'center', marginTop: '8px' } }, [
              UI.donut(latest.progressPct, 'var(--accent)', 56),
              h('div.muted', { style: { flex: '1' },
                text: '각자 목표가 다르므로 달성률로만 비교합니다. 누가 더 말랐는지는 비교하지 않습니다.' })
            ])
          ]));
        }

        /* --- C06 이번 주 일정 ------------------------------------------
           사용자가 요청한 "친구가 운동하기로 했는데 안 했으면 확인할 수
           있게" 가 일어나는 유일한 자리입니다. 그리고 여기서 "확인" 은
           **보는 것**입니다 — 찌르기 · 응원 · 리마인드 버튼을 만들지
           않습니다. 이 카드 안에 누를 수 있는 것이 하나도 없다는 것이
           이 기능의 설계이고, 고칠 때 지켜야 할 불변식입니다.

           만들지 않은 것과 그 이유:
             · 퍼센트 — 분모를 숨깁니다. "1일 중 1일 = 100%" 가
               "4일 중 4일" 을 이기면 안 됩니다.
             · 색 — 지킨 날은 초록이 아니고 못 한 날은 빨강이 아닙니다.
               남의 한 주에 색을 칠하는 순간 점수표가 됩니다.
             · "미달성" 같은 단어와 경고 아이콘.
             · 홈 화면 노출 — 홈은 하루에 여러 번 봅니다. 거기에 남의
               수행도가 있으면 확인이 아니라 상시 감시가 됩니다.
               친구 탭으로 들어오는 한 번의 동작은 버그가 아니라 설계입니다. */
        if (latest.plannedDays != null) {
          var kept = latest.keptDays || 0;
          var missed = latest.missedDays || 0;
          var open = latest.openDays || 0;
          var thisWk = isThisWeek(latest);
          var second = [];
          if (missed) {
            second.push(thisWk ? '지나간 날 중 ' + missed + '일은 체크가 없습니다'
                               : '그 주에 체크가 없던 날이 ' + missed + '일입니다');
          }
          /* "N일이 남았습니다" 는 **지금 주에만** 참입니다. 끝난 주에
             대해 그렇게 쓰면 이미 지나간 날을 아직 기회가 있는 것처럼
             말하게 됩니다. 지난주라면 남은 날은 그냥 체크가 없던 날입니다. */
          if (open) {
            second.push(thisWk ? open + '일이 남았습니다'
                               : '체크 없이 지나간 날이 ' + open + '일 더 있습니다');
          }
          wrap.appendChild(h('div.card', { uid: 'P16-C06', uidLabel: '친구 주간 일정' }, [
            h('div.card__title', { text: (weekLabel(latest.weekStart) || '최근') + ' 일정' }),
            h('div', { style: { fontSize: '20px', fontWeight: '800', marginTop: '6px' },
              text: '계획 ' + latest.plannedDays + '일 · 지킴 ' + kept + '일' }),
            second.length ? h('div.muted', { style: { marginTop: '4px' },
              text: second.join(', ') + '.' }) : null,
            /* 이 두 줄을 빼면 안 됩니다. 앱이 아는 것은 "체크를 눌렀는가"
               이지 "운동을 했는가" 가 아닙니다. 그 차이를 안 적으면
               화면이 모르는 것을 안다고 말하게 됩니다. */
            h('div.muted', { style: { marginTop: '10px' },
              text: '본인이 앱에 적은 기록입니다. 갔는데 체크를 안 눌렀을 수도 있습니다.' })
          ]));
        } else if (onKeys.indexOf('schedule') >= 0) {
          /* 공유는 켜 뒀는데 그 주에 적은 계획이 없는 경우.
             "계획 0일 · 지킴 0일" 이라고 쓰면 앱이 모르는 것을 0점이라고
             말하는 것이 됩니다 — 운동을 안 했다는 뜻이 아니라 앱에
             적지 않았다는 뜻입니다. 이건 서로 다른 말입니다. */
          wrap.appendChild(h('div.card.card--flat', { uid: 'P16-S22', uidLabel: '친구 일정 없음' }, [
            h('div.card__title', { text: '이번 주 일정' }),
            h('div.muted', { style: { marginTop: '4px' },
              /* "적은 일정이 없다" 와 "이번 주 것이 아직 안 올라왔다" 는
                 다른 말입니다. 스냅샷은 친구가 앱을 열어야 올라가므로,
                 주 초에는 뒤쪽이 정상입니다. 앞엣말로 뭉개면 앱을 아직
                 안 연 사람을 "아무 계획도 안 세운 사람" 으로 만듭니다. */
              text: isThisWeek(latest)
                ? friend.displayName + '님이 이번 주에 적은 일정이 없습니다. ' +
                  '운동을 안 했다는 뜻이 아니라, 앱에 적지 않았다는 뜻입니다.'
                : friend.displayName + '님의 이번 주 기록이 아직 안 올라왔습니다. ' +
                  '친구가 앱을 열면 올라옵니다.' })
          ]));
        }

        var strip = dotStrip(rows.slice().reverse(), friend.since, 12);
        if (strip) {
          wrap.appendChild(h('div.card.card--flat', { uid: 'P16-C05', uidLabel: '친구 체크인' }, [
            h('div.card__title', { text: '체크인' }),
            h('div.muted', { text: '최근 ' + strip.total + '주 중 ' + strip.on + '주 기록했습니다.' }),
            strip.el
          ]));
        }
      }

      /* --- C23 관계 --- */
      wrap.appendChild(h('div.card', { uid: 'P16-C23', uidLabel: '관계' }, [
        h('div.card__title', { text: '관계' }),
        h('div.btn-row', { style: { marginTop: '10px' } }, [
          h('button.btn.btn--sm.btn--danger', { text: '친구 끊기', uid: 'P16-B02', uidLabel: '친구 끊기',
            onClick: function () {
              global.MB_MODALS.removeFriend(friend, function () {
                B().removeFriend(fid);
                global.MB_UID.toast('친구를 끊었습니다');
                // {replace:true} 는 이미 쌓인 history 를 빼지 않습니다.
                // back() 이 정확히 P15 로 돌려보냅니다.
                A.back();
              });
            } })
        ])
      ]));
    }
  });

  /* =====================================================================
   * 데모 친구 (프로토타입 전용)
   *
   * 한 기기 localStorage 안에는 제공자당 한 계정씩만 있어서, 실제로는
   * 친구 관계에 도달하는 경로가 없습니다. 이게 없으면 새 UI 도 똑같이
   * 검증 불가 상태로 남습니다. smoke.js 도 이 함수를 씁니다.
   * =================================================================== */
  function makeDemoFriend() {
    var BE = B(), me = BE.currentUser();
    if (!me) return null;
    var saved = me.id, demo = null;
    try {
      demo = BE.signIn({ provider: 'demo', handle: 'demo:1', displayName: '데모친구' });
      BE.sendRequest(me.inviteCode);
      BE._setSession(saved);
      BE.accept(demo.id);
      BE._setSession(demo.id);
      BE.setShare(saved, { smmTrend: true, bfmTrend: true, planProgress: true, streak: true });
      for (var i = 11; i >= 0; i--) BE.publishSnapshot(weekAgoISO(i), demoPayload(i));
    } finally {
      // 무슨 일이 있어도 원래 세션으로. 이게 없으면 중간에 던졌을 때
      // 앱이 데모 계정으로 로그인된 채 남습니다.
      BE._setSession(saved);
    }
    // 🚨 S.set 은 반드시 finally 뒤에. save() 가 publishWeekly() 를 부르므로,
    // 세션이 데모인 구간에서 저장하면 내 체성분이 데모 계정 소유로 올라갑니다.
    S.set({ settings: Object.assign({}, S.get().settings, { demoFriendId: demo && demo.id }) });
    S.publishWeekly();
    return demo;
  }

  function weekAgoISO(n) {
    var d = new Date();
    d.setDate(d.getDate() - n * 7);
    return S.weekStartOf(d);
  }

  /** 정직하게 성깁니다 — 스캔은 6주에 한 번만 있는 것으로 둡니다.
   *  조밀한 가짜 데이터가 아니라 실제로 만날 성긴 데이터에 대고 화면을 검증하기 위해서입니다. */
  function demoPayload(i) {
    var p = { checkedIn: (i % 3) !== 1 };
    if (i % 6 === 0) { p.dSmmKg = 0.3; p.dBfmKg = -0.9; p.progressPct = Math.max(0, 70 - i * 4); }
    return p;
  }

  global.MB_SOCIAL = { makeDemoFriend: makeDemoFriend };
})(window);
