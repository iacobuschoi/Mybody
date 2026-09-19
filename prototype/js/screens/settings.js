/* P12 — 설정 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var THEMES = [['auto', '자동'], ['light', '라이트'], ['dark', '다크']];
  var BADGE_SIZES = [[9, '9px'], [10, '10px'], [11, '11px']];
  var CHECKIN_WEEKS = [[1, '1주'], [2, '2주']];
  var VERSION_LINE = 'Mybody 프로토타입 v0.1 · 검증용';

  A.register('P12', {
    title: '설정', label: '설정',
    render: function (wrap, ctx) {
      var body = h('div');
      wrap.appendChild(body);
      draw();

      /* --- 저장 -------------------------------------------------------- */
      function patch(p) {
        var cur = S.get().settings || {};
        S.set({ settings: Object.assign({}, cur, p) });
        draw();
      }

      function draw() {
        UI.clear(body);
        var st = S.get();
        var set = st.settings || {};

        // 저장된 표시 설정을 화면에 먼저 반영한다 (새로고침 후에도 유지)
        applyTheme(set.theme);
        applyBadgeSize(set.badgeSize);

        /* ===== C01 프로필 ============================================== */
        var c01 = h('div.card', { uid: 'P12-C01', uidLabel: '프로필 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '프로필' }),
            h('div.card__sub', { text: '모든 계산의 기준값' })
          ])
        ]);
        if (st.profile) {
          var p = st.profile;
          c01.appendChild(h('div', [
            kv('성별 · 나이 · 키',
              (p.sex === 'female' ? '여' : '남') + ' · ' +
              (p.age != null ? p.age + '세' : '—') + ' · ' +
              (p.heightCm != null ? UI.n1(p.heightCm) + 'cm' : '—')),
            kv('활동 수준', (E.PAL[p.activityLevel] || {}).label || '—'),
            kv('운동 경력', (E.MUSCLE_BASE[p.trainingAge] || {}).label || '—'),
            kv('주 운동', (p.daysPerWeek ? p.daysPerWeek + '회' : '—') +
              (p.sessionMinutes ? ' · 회당 ' + p.sessionMinutes + '분' : ''))
          ]));
          c01.appendChild(h('button.btn.btn--sm.btn--block', {
            text: '프로필 수정', uid: 'P12-B01', uidLabel: '프로필 수정',
            style: { marginTop: '10px' },
            onClick: function () { A.go('P01'); }
          }));
        } else {
          c01.appendChild(h('div.empty', { uid: 'P12-S01', uidLabel: '프로필 없음 빈 상태' }, [
            h('div.empty__ico', { text: '👤' }),
            h('div.empty__t', { text: '아직 프로필이 없습니다' }),
            h('div.empty__d', { text: '성별 · 나이 · 키 · 활동 수준이 없으면 칼로리와 근육 증가 한계를 계산할 수 없습니다.' }),
            h('button.btn.btn--primary', {
              text: '프로필 입력하기', uid: 'P12-B01', uidLabel: '프로필 수정',
              onClick: function () { A.go('P01'); }
            })
          ]));
        }
        body.appendChild(c01);

        /* ===== C07 계정 ================================================= */
        (function () {
          var me = global.MB_BACKEND ? global.MB_BACKEND.currentUser() : null;
          var fr = me ? global.MB_BACKEND.listFriends() : null;
          body.appendChild(h('div.card', { uid: 'P12-C07', uidLabel: '계정' }, [
            h('div.card__head', [
              h('div.card__title', { text: '계정' }),
              h('span.badge' + (me ? '.badge--ok' : ''), { text: me ? me.displayName : '로그인 안 함' })
            ]),
            h('div.muted', { text: me
              ? '친구 ' + fr.accepted.length + '명' +
                (fr.incoming.length ? ' · 받은 요청 ' + fr.incoming.length + '건' : '')
              : '기기를 바꿔도 기록이 남고, 친구와 함께 할 수 있습니다.' }),
            // 친구는 이제 하단 탭입니다. 여기서 또 들어가는 문을 두면
            // 같은 곳으로 가는 길이 둘이 되고, 설정이 다시 친구의 관문처럼 읽힙니다.
            h('div.btn-row', { style: { marginTop: '10px' } }, [
              h('button.btn.btn--sm', { text: '계정', uid: 'P12-B13', uidLabel: '계정 화면',
                onClick: function () { A.go('P14'); } })
            ])
          ]));
        })();

        /* ===== C08 사진 · 자동 판독 ======================================
           결과지 사진과, 그 사진을 서버로 보낼지 말지. 건강 데이터를
           기기 밖으로 내보내는 일이라 기본은 꺼짐이고, 켜는 것도 끄는
           것도 여기 한 곳에서만 합니다. */
        (function () {
          var sync = global.MB_SYNC ? global.MB_SYNC.status() : { signedIn: false, configured: false };
          var ocrOn = global.MB_SYNC && global.MB_SYNC.canOcr && global.MB_SYNC.canOcr();
          var shots = global.MB_PHOTO ? Object.keys(global.MB_PHOTO.list()).length : 0;
          var kb = global.MB_PHOTO ? Math.round(global.MB_PHOTO.usedBytes() / 1024) : 0;

          var card = h('div.card', { uid: 'P12-C08', uidLabel: '사진 · 자동 판독' }, [
            h('div.card__head', [
              h('div.card__title', { text: '결과지 사진' }),
              h('span.badge' + (ocrOn ? '.badge--accent' : ''),
                { text: ocrOn ? '자동 판독 켜짐' : '이 기기에만' })
            ]),
            h('div.muted', { text: shots
              ? '이 기기에 ' + shots + '장 · ' + kb + 'KB. 최근 ' +
                (global.MB_PHOTO ? global.MB_PHOTO.KEEP : 6) + '장까지만 남깁니다.'
              : '저장된 사진이 없습니다.' })
          ]);

          card.appendChild(chipField('P12-F06', '자동 판독',
            [['off', '끄기 (직접 입력)'], ['on', '켜기 (서버로 보냄)']],
            ocrOn ? 'on' : 'off',
            function (v) {
              if (v === 'on' && !sync.signedIn) {
                global.MB_UID.toast('먼저 로그인해야 합니다 — 사진은 내 계정으로만 올라갑니다');
                return;
              }
              if (v === 'on') {
                global.MB_MODALS.enableOcr(function () {
                  global.MB_SYNC.setOcr(true);
                  A.refresh();
                });
                return;
              }
              global.MB_SYNC.setOcr(false);
              A.refresh();
            },
            sync.signedIn
              ? '켜면 사진이 ' + (sync.baseUrl || '내 서버') + ' 로 올라가 숫자 초안을 만들어 돌려줍니다. ' +
                '꺼져 있어도 사진을 보면서 직접 넣을 수 있습니다.'
              : '로그인해야 켤 수 있습니다. 사진은 내 계정으로만 올라갑니다.'));

          if (shots) {
            card.appendChild(h('button.btn.btn--sm', {
              text: '저장된 사진 모두 지우기', uid: 'P12-B14', uidLabel: '사진 모두 지우기',
              style: { marginTop: '4px' },
              onClick: function () {
                global.MB_PHOTO.clearAll();
                global.MB_UID.toast('사진을 모두 지웠습니다 — 숫자 기록은 그대로입니다');
                A.refresh();
              }
            }));
          }
          body.appendChild(card);
        })();

        /* ===== C02 표시 ================================================ */
        var theme = set.theme || 'auto';
        var badgeSize = set.badgeSize || currentBadgeSize();
        body.appendChild(h('div.card', { uid: 'P12-C02', uidLabel: '표시 설정 카드' }, [
          h('div.card__head', [h('div.card__title', { text: '표시' })]),
          chipField('P12-F01', '테마', THEMES, theme, function (v) {
            applyTheme(v);
            patch({ theme: v });
          }, theme === 'auto' ? '기기 설정(다크 모드)을 따라갑니다.' : null),
          chipField('P12-F02', '번호 배지 크기', BADGE_SIZES, badgeSize, function (v) {
            applyBadgeSize(v);
            patch({ badgeSize: v });
          }, '화면 곳곳의 고유번호 배지 글자 크기입니다. i 키로 배지를 끌 수 있습니다.')
        ]));

        /* ===== C03 플랜 기본값 ========================================== */
        var levelOpts = (E.LEVEL_SPEC || []).map(function (s) { return [s.key, s.label]; });
        var defLevel = set.defaultLevel || 'mid';
        var defSpec = null;
        (E.LEVEL_SPEC || []).forEach(function (s) { if (s.key === defLevel) defSpec = s; });
        body.appendChild(h('div.card', { uid: 'P12-C03', uidLabel: '플랜 기본값 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '플랜 기본값' }),
            h('div.card__sub', { text: '새 플랜을 만들 때 미리 선택됩니다' })
          ]),
          chipField('P12-F03', '기본 강도', levelOpts, defLevel, function (v) {
            patch({ defaultLevel: v });
          }, defSpec ? defSpec.title + ' · ' + defSpec.blurb : null),
          chipField('P12-F04', '체크인 주기', CHECKIN_WEEKS, set.checkinEveryWeeks || 1, function (v) {
            patch({ checkinEveryWeeks: v });
          }, '같은 요일 · 같은 시간에 재는 편이 수분 변동에 덜 속습니다.'),
          h('button.btn.btn--sm.btn--block', {
            text: '체크인 알림 설정', uid: 'P12-B02', uidLabel: '체크인 알림',
            onClick: function () { global.MB_MODALS.reminder(); }
          })
        ]));

        /* ===== C04 데이터 ============================================== */
        body.appendChild(h('div.card', { uid: 'P12-C04', uidLabel: '데이터 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '데이터' }),
            h('div.card__sub', { text: '전부 이 기기 안에만 저장됩니다' })
          ]),
          h('div.kv', [
            h('span.kv__k', { text: '저장된 측정' }),
            h('span.kv__v', { text: (st.scans ? st.scans.length : 0) + '건' })
          ]),
          h('div.kv', [
            h('span.kv__k', { text: '체크인 기록' }),
            h('span.kv__v', { text: (st.checkins ? st.checkins.length : 0) + '건' })
          ]),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '10px' } }, [
            h('button.btn.btn--block', {
              text: '내보내기 (JSON)', uid: 'P12-B03', uidLabel: '데이터 내보내기',
              onClick: function () { global.MB_MODALS.exportData(); }
            }),
            h('button.btn.btn--block', {
              text: '가져오기 (JSON)', uid: 'P12-B04', uidLabel: '데이터 가져오기',
              onClick: openImport
            }),
            h('button.btn.btn--block', {
              text: '내 실제 인바디로 채우기', uid: 'P12-B05', uidLabel: '실제 인바디 시드 주입',
              onClick: function () {
                S.seed();
                global.MB_UID.toast('실제 인바디 3건을 불러왔습니다');
                A.go('P02');
              }
            }),
            h('button.btn.btn--danger.btn--block', {
              text: '전체 초기화', uid: 'P12-B06', uidLabel: '전체 초기화',
              onClick: function () { global.MB_MODALS.resetAll(); }
            })
          ]),
          h('div.note', { style: { marginTop: '10px' },
            text: '"내 실제 인바디로 채우기"와 "전체 초기화"는 지금 저장된 내용을 덮어씁니다.' })
        ]));

        /* ===== C05 프로토타입 도구 ====================================== */
        var noteCount = (global.MB_UID && global.MB_UID.notes) ? global.MB_UID.notes.length : 0;
        body.appendChild(h('div.card', { uid: 'P12-C05', uidLabel: '프로토타입 도구 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '프로토타입 도구' }),
            h('span.badge' + (noteCount ? '.badge--accent' : ''), { text: '피드백 ' + noteCount + '건' })
          ]),
          h('div.card__sub', { text: '배지를 Shift+클릭하면 그 요소에 메모가 달립니다.' }),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '10px' } }, [
            h('button.btn.btn--block', {
              text: 'ID 목록 보기', uid: 'P12-B07', uidLabel: 'ID 목록 보기',
              onClick: function () { A.go('P13'); }
            }),
            h('button.btn.btn--block', {
              text: '피드백 전체 복사', uid: 'P12-B08', uidLabel: '피드백 전체 복사',
              disabled: noteCount === 0,
              onClick: function () { global.MB_UID.exportAll(); }
            }),
            h('button.btn.btn--block', {
              text: '피드백 모두 지우기', uid: 'P12-B09', uidLabel: '피드백 모두 지우기',
              disabled: noteCount === 0,
              onClick: function () { global.MB_UID.clearAll(); A.refresh(); }
            }),
            h('button.btn.btn--ghost.btn--block', {
              text: '단축키 도움말', uid: 'P12-B10', uidLabel: '단축키 도움말',
              onClick: function () { global.MB_UID.showHelp(); }
            })
          ])
        ]));

        /* ===== C06 정보 ================================================ */
        body.appendChild(h('div.card', { uid: 'P12-C06', uidLabel: '정보 카드' }, [
          h('div.card__head', [h('div.card__title', { text: '정보' })]),
          h('div.btn-row.btn-row--stack', [
            h('button.btn.btn--block', {
              text: '의학적 고지', uid: 'P12-B11', uidLabel: '의학적 고지',
              // 설정에서는 일부러 다시 보는 것이므로 수락 여부와 무관하게 띄웁니다
              onClick: function () { global.MB_MODALS.disclaimer(true); }
            }),
            h('button.btn.btn--block', {
              text: '용어 사전', uid: 'P12-B12', uidLabel: '용어 사전',
              onClick: function () { global.MB_MODALS.glossary(); }
            })
          ]),
          h('hr.sep'),
          h('div.muted', { text: VERSION_LINE }),
          h('div.muted', { text: '이 화면의 숫자는 참고용입니다. 진단이나 처방이 아닙니다.' })
        ]));
      }

      /* --- 가져오기 모달 (M20) ------------------------------------------ */
      function openImport() {
        var ta = h('textarea.textarea', {
          rows: 10, placeholder: '내보내기로 복사한 JSON을 여기에 붙여넣으세요',
          uid: 'M20-F01', uidLabel: '가져오기 JSON 입력'
        });
        var err = h('div.field__err', { style: { display: 'none' } });
        UI.openModal({
          uid: 'M44', title: '데이터 가져오기',
          sub: '지금 저장된 내용은 덮어씌워집니다',
          body: [
            h('p', { text: '다른 기기에서 내보낸 JSON을 붙여넣으면 측정 기록 · 목표 · 플랜이 그대로 복원됩니다.' }),
            ta, err
          ],
          actions: [
            { label: '취소', kind: 'ghost' },
            { label: '가져오기', kind: 'primary', onClick: function () {
                var text = ta.value.trim();
                if (!text) {
                  err.style.display = '';
                  err.textContent = '붙여넣은 내용이 없습니다.';
                  return true;              // 닫지 않음
                }
                try {
                  S.importJSON(text);
                } catch (e) {
                  err.style.display = '';
                  err.textContent = '읽을 수 없습니다 · ' + (e && e.message ? e.message : '형식 오류');
                  return true;              // 닫지 않음
                }
                global.MB_UID.toast('데이터를 가져왔습니다');
                A.refresh();
              } }
          ]
        });
      }
    }
  });

  /* --- 공통 헬퍼 ------------------------------------------------------- */
  function kv(k, v) {
    return h('div.kv', [h('span.kv__k', { text: k }), h('span.kv__v', { text: v })]);
  }

  function chipField(uid, label, options, current, onPick, hint) {
    return h('div.field', [
      h('div.field__label', { text: label }),
      h('div.chips', { uid: uid, uidLabel: label + ' 선택' }, options.map(function (o) {
        return h('button.chip' + (o[0] === current ? '.is-on' : ''), {
          text: o[1],
          onClick: function () { onPick(o[0]); }
        });
      })),
      hint ? h('div.field__hint', { text: hint }) : null
    ]);
  }

  function applyTheme(theme) {
    var root = document.documentElement;
    root.dataset.theme = (theme === 'light' || theme === 'dark') ? theme : '';
  }

  function currentBadgeSize() {
    var prefs = (global.MB_UID && global.MB_UID.state) ? global.MB_UID.state.prefs : null;
    return (prefs && prefs.badgeSize) || 9;
  }

  function applyBadgeSize(px) {
    var v = px || currentBadgeSize();
    document.documentElement.style.setProperty('--uid-badge-fs', v + 'px');
    // uid.js 는 화면을 다시 그릴 때마다 prefs 값으로 이 변수를 덮어쓴다 → 같이 맞춰둔다
    try {
      if (global.MB_UID && global.MB_UID.state && global.MB_UID.state.prefs) {
        global.MB_UID.state.prefs.badgeSize = v;
      }
    } catch (e) {}
  }
})(window);
