/* P12 — 설정 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var THEMES = [['auto', '자동'], ['light', '라이트'], ['dark', '다크']];
  var BADGE_SIZES = [[9, '9px'], [10, '10px'], [11, '11px']];
  var CHECKIN_WEEKS = [[1, '1주'], [2, '2주']];
  /* 배포본에 "프로토타입 · 검증용" 이라고 적혀 있으면, 받은 사람은
     미완성을 쓰고 있다고 읽습니다. 배포본에는 빌드가 박아 둔 버전을
     적습니다 — 문제가 생겼을 때 "어느 판인지" 를 물어볼 수 있는
     번호이기도 합니다. */
  function versionLine() {
    var B = global.MB_BUILD;
    if (!B || !B.release) return 'Mybody 프로토타입 v0.1 · 검증용';
    return 'Mybody · ' + (B.version || '?') +
           (B.builtAt ? ' · ' + String(B.builtAt).slice(0, 10) : '');
  }

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
              /* 예전 문구는 "기기를 바꿔도 기록이 남고" 였습니다. 거짓입니다.
                 서버로 올라가는 것은 친구에게 보일 주간 요약과 친구 관계뿐이고,
                 측정 기록 · 프로필 · 목표 · 계획 · 식단은 한 번도 안 올라갑니다.
                 기기를 바꾸면 그대로 사라집니다. 백업은 "내보내기(JSON)" 입니다.
                 이걸 백업이라고 믿게 두면, 정말 필요한 순간에 없습니다. */
              : '친구와 함께 할 수 있습니다. 기록 백업은 아니에요 — 아래 내보내기를 쓰세요.' }),
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
              ? '켜면 사진이 ' + (sync.baseUrl || '내 서버') + ' 를 거쳐 외부 판독 서비스로 가고, ' +
                '숫자 초안을 만들어 돌려줍니다. 꺼져 있어도 사진을 보면서 직접 넣을 수 있습니다.'
              : '로그인해야 켤 수 있습니다. 사진은 내 계정으로만 올라갑니다.'));

          if (shots) {
            card.appendChild(h('button.btn.btn--sm', {
              text: '저장된 사진 모두 지우기', uid: 'P12-B14', uidLabel: '사진 모두 지우기',
              style: { marginTop: '4px' },
              onClick: function () {
                global.MB_MODALS.confirmClear({
                  title: '사진을 모두 지울까요?',
                  warn: '이 기기에 저장된 결과지 사진 ' + shots + '장이 사라지고 되돌릴 수 없습니다.',
                  keep: '측정 숫자는 그대로 남습니다. 사라지는 것은 나중에 원본과 대조할 사진뿐입니다.',
                  onConfirm: function () {
                    global.MB_PHOTO.clearAll();
                    global.MB_UID.toast('사진 ' + shots + '장을 지웠습니다 — 숫자 기록은 그대로입니다');
                    A.refresh();
                  }
                });
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
          /* 배지 크기 조절은 개발 빌드 전용입니다. 배포본에는 배지가
             아예 없어서(uid.css 와 배지 생성이 다 빠집니다) 이 칸을
             아무리 움직여도 화면이 안 바뀝니다 — 쓰는 사람에게는
             고장 난 설정으로 보입니다. */
          global.MB_BUILD.tools
            ? chipField('P12-F02', '번호 배지 크기', BADGE_SIZES, badgeSize, function (v) {
                applyBadgeSize(v);
                patch({ badgeSize: v });
              }, '화면 곳곳의 고유번호 배지 글자 크기입니다. i 키로 배지를 끌 수 있습니다.')
            : null,
          /* 스트릭을 끄는 스위치.
             연속 숫자는 매몰비용을 만듭니다 — 87일을 지킨 사람은 무릎이
             아파도 88일을 하러 갑니다. 이 앱은 그래서 보상을 하나도 안
             답니다(배지·불꽃·레벨·최고기록 없음). 그래도 숫자 자체가
             부담인 사람이 있고, 그 사람에게는 출구가 있어야 합니다.
             끄면 셈을 멈추는 게 아니라 안 보이게 합니다 — 기록은 그대로라
             다시 켜면 그 자리에 있습니다. */
          chipField('P12-F07', '스트릭 보기',
            [[false, '보임'], [true, '숨김']], !!set.hideStreaks, function (v) {
              patch({ hideStreaks: v });
            }, '연속 일수가 부담이면 숨길 수 있습니다. 기록은 그대로 남고, 다시 켜면 이어집니다.')
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

        /* ===== C04 데이터 ==============================================
           머리말이 "전부 이 기기 안에만 저장됩니다" 로 고정돼 있었습니다.
           로그인하면 거짓입니다 — 저장할 때마다 주간 요약(체중 · 골격근 ·
           체지방 · 체지방률 절대값 포함)이 서버로 올라갑니다.
           상태를 읽어서 사실대로 적습니다. */
        var syncSt = global.MB_SYNC ? global.MB_SYNC.status() : { signedIn: false };
        body.appendChild(h('div.card', { uid: 'P12-C04', uidLabel: '데이터 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '데이터' }),
            h('div.card__sub', { text: syncSt.signedIn
              ? '기기에 저장되고, 주간 요약만 서버로 올라갑니다'
              : '전부 이 기기 안에만 저장됩니다' })
          ]),
          syncSt.signedIn ? h('div.muted', { style: { marginBottom: '8px' },
            text: '측정 기록 · 프로필 · 목표 · 계획 · 식단은 올라가지 않습니다. ' +
                  '기기를 바꾸면 사라지니, 옮기려면 아래 내보내기를 쓰세요.' }) : null,
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
            /* 시드 주입은 개발 빌드 전용입니다.
             *
             * 이 버튼은 "내 실제 인바디로 채우기" 라고 적혀 있습니다. 앱을
             * 만드는 사람에게는 맞는 말이지만, 앱을 받은 사람에게는
             * "내가 방금 넣은 내 인바디로 채워 준다" 로 읽힙니다. 실제로
             * 하는 일은 그 반대입니다 — 지금 저장된 것을 전부 지우고 이
             * 앱을 만든 사람의 몸 숫자를 넣습니다. 확인 창도 없었습니다.
             *
             * 한 번 누르면 그 사람의 측정·프로필·목표·계획·식단이 사라지고,
             * 돌이킬 방법은 안 해 뒀을 내보내기 파일뿐입니다. 동시에 남의
             * 체중 히스토리가 그 사람 폰에 들어앉습니다. 배포본에 있을
             * 이유가 없습니다.
             *
             * 개발 빌드에도 확인을 답니다. 데이터를 지우는 버튼은 옆의
             * 전체 초기화와 같은 규칙을 따라야 합니다. */
            global.MB_BUILD.tools ? h('button.btn.btn--block', {
              text: '내 실제 인바디로 채우기 (개발용)',
              uid: 'P12-B05', uidLabel: '실제 인바디 시드 주입',
              onClick: function () {
                global.MB_MODALS.confirmClear({
                  title: '지금 저장된 것을 전부 덮어쓸까요?',
                  warn: '측정 · 프로필 · 목표 · 계획 · 식단이 모두 지워지고, ' +
                        '이 앱을 만들 때 쓴 인바디 3건이 대신 들어갑니다. 되돌릴 수 없습니다.',
                  confirmLabel: '덮어쓰기',
                  onConfirm: function () {
                    S.seed();
                    global.MB_UID.toast('실제 인바디 3건을 불러왔습니다');
                    A.go('P02');
                  }
                });
              }
            }) : null,
            h('button.btn.btn--danger.btn--block', {
              text: '전체 초기화', uid: 'P12-B06', uidLabel: '전체 초기화',
              onClick: function () { global.MB_MODALS.resetAll(); }
            })
          ]),
          h('div.note', { style: { marginTop: '10px' },
            text: '"전체 초기화" 는 지금 저장된 내용을 지웁니다. 먼저 내보내기로 챙겨 두세요.' })
        ]));

        /* ===== C05 프로토타입 도구 ======================================
           고유번호 배지 · 피드백 메모 · ID 목록은 이 앱을 만드는 동안
           쓰는 것들입니다. 배포 빌드에는 통째로 들어가지 않습니다. */
        var noteCount = (global.MB_UID && global.MB_UID.notes) ? global.MB_UID.notes.length : 0;
        if (global.MB_BUILD.tools) body.appendChild(h('div.card', { uid: 'P12-C05', uidLabel: '프로토타입 도구 카드' }, [
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
              onClick: function () {
                global.MB_MODALS.confirmClear({
                  title: '메모를 모두 지울까요?',
                  warn: '화면에 남긴 메모 ' + noteCount + '개가 전부 사라지고 되돌릴 수 없습니다.',
                  keep: '측정 기록과 계획은 그대로 남습니다.',
                  onConfirm: function () {
                    global.MB_UID.clearAll();
                    global.MB_UID.toast('메모 ' + noteCount + '개를 지웠습니다');
                    A.refresh();
                  }
                });
              }
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
            }),
            /* 방침은 앱 화면이 아니라 따로 열리는 문서입니다.
               로그인하지 않아도, 자바스크립트가 꺼져 있어도 읽혀야
               하기 때문입니다 — 읽을 수 없는 방침은 없는 것과 같습니다.
               그래서 button 이 아니라 a 입니다. */
            h('a.btn.btn--block', {
              text: '개인정보처리방침', href: './privacy.html', target: '_blank',
              rel: 'noopener', uid: 'P12-B15', uidLabel: '개인정보처리방침' })
          ]),
          h('hr.sep'),
          installRow(),
          h('div.muted', { text: versionLine() }),
          h('div.muted', { text: '이 화면의 숫자는 참고용입니다. 진단이나 처방이 아닙니다.' }),
          /* http 로 열면(같은 와이파이에서 192.168.x.x 같은 주소) 브라우저가
             앱 설치·오프라인·복사를 통째로 막습니다. 앱은 그대로 돌아서
             사용자는 "왜 설치가 안 뜨지" 를 혼자 한참 찾습니다.
             무엇이 왜 안 되는지 여기서 말해 줍니다. */
          !UI.isSecure() ? h('div.note.note--warn', { style: { marginTop: '10px' },
            uid: 'P12-S02', uidLabel: '보안 연결 안내',
            text: '지금 주소는 https 가 아닙니다. 그래서 폰에 앱처럼 깔기 · 오프라인으로 열기 · ' +
                  '버튼으로 복사하기가 안 됩니다 (브라우저가 막습니다). 앱의 나머지는 그대로 됩니다. ' +
                  '이 셋이 필요하면 서버를 https 로 여세요 — docs/DEPLOY.md 의 "밖에서 접속하게".' }) : null
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

  /* --- 폰에 앱처럼 깔기 ---------------------------------------------------
   *
   * 앱이 "안 된다" 고만 말하고 있었습니다 (P12-S02). 될 때 도와주지는
   * 않았습니다 — 그런데 이게 지금 당장, 공짜로, 심사 없이 폰에 아이콘을
   * 만드는 유일한 길입니다.
   *
   * 브라우저마다 방식이 다릅니다.
   *   안드로이드/크롬 — beforeinstallprompt 를 잡아 뒀다가 버튼으로 띄웁니다.
   *   아이폰/사파리   — 그런 이벤트가 없습니다. 손으로 하는 순서를 적어 줍니다.
   *                     (그리고 **아이폰은 홈 화면에 추가해야 알림이 됩니다.**)
   *   이미 깔림      — 아무것도 안 보여 줍니다. 깐 사람에게 깔라고 하면 안 됩니다.
   * ---------------------------------------------------------------------- */
  function installed() {
    try {
      return (global.matchMedia && global.matchMedia('(display-mode: standalone)').matches) ||
             global.navigator.standalone === true;
    } catch (e) { return false; }
  }
  function isIos() {
    try {
      var ua = global.navigator.userAgent || '';
      /* 아이패드는 최근 iOS 에서 맥인 척합니다. 터치가 있는 맥은 없습니다. */
      return /iPhone|iPad|iPod/.test(ua) ||
             (/Macintosh/.test(ua) && global.navigator.maxTouchPoints > 1);
    } catch (e) { return false; }
  }

  function installRow() {
    if (installed()) {
      return h('div.muted', { uid: 'P12-S03', uidLabel: '설치됨',
        text: '홈 화면에서 실행 중입니다.' });
    }
    if (!UI.isSecure()) return null;      // 왜 안 되는지는 아래 P12-S02 가 말합니다

    var prompt = global.MB_INSTALL && global.MB_INSTALL.prompt;
    if (prompt) {
      return h('div', { style: { marginTop: '10px' } }, [
        h('button.btn.btn--sm.btn--block', { text: '폰에 앱처럼 깔기',
          uid: 'P12-B16', uidLabel: '앱 설치',
          onClick: function () {
            prompt.prompt();
            prompt.userChoice.then(function (r) {
              if (r && r.outcome === 'accepted') global.MB_UID.toast('깔았습니다');
              global.MB_INSTALL.prompt = null;
              A.refresh();
            }).catch(function () {});
          } }),
        h('div.field__hint', { text: '주소창 없이 앱처럼 열리고, 오프라인에서도 켜집니다.' })
      ]);
    }
    if (isIos()) {
      return h('div.note', { style: { marginTop: '10px' },
        uid: 'P12-S04', uidLabel: '아이폰 설치 안내' }, [
        h('b', { text: '폰에 앱처럼 깔기' }),
        h('div', { style: { marginTop: '4px' },
          text: '사파리 아래쪽 공유 버튼 → "홈 화면에 추가".' }),
        h('div.muted', { style: { marginTop: '4px' },
          text: '아이폰은 이렇게 깔아야 폰 알림도 받을 수 있습니다 (사파리 규칙).' })
      ]);
    }

    /* 여기까지 왔으면 이 브라우저가 아직 설치 신호를 안 줬다는 뜻입니다.
     *
     * 예전에는 여기서 null 을 돌려줬습니다 — "없는 버튼을 만들지 않는다"
     * 는 맞는 원칙인데, 그 결과가 **아무것도 없는 화면**이었습니다.
     * 주인이 폰으로 앱을 열어 놓고 "앱 받는 버튼 암만 봐도 없음" 이라고
     * 했습니다. 설정 맨 아래에 있다고 적어 뒀는데 그 자리가 비어 있었습니다.
     *
     * 없는 버튼을 만들지 않는 것과, 왜 없는지 말하지 않는 것은 다릅니다.
     * 못 깔 이유가 여럿이고 **할 일이 각각 다릅니다** — 그래서 뭉뚱그리지
     * 않고 실제로 확인해서 그 중 어느 것인지 말합니다. */
    var ua = '';
    try { ua = global.navigator.userAgent || ''; } catch (e) {}
    var isFirefox = /Firefox\//.test(ua);
    var isDesktop = !/Android|iPhone|iPad|iPod|Mobile/i.test(ua);

    var how = isFirefox
      ? '파이어폭스는 앱 설치를 지원하지 않습니다. 크롬 · 엣지 · 사파리로 이 주소를 열면 깔 수 있습니다.'
      : isDesktop
        ? '주소창 오른쪽의 설치 아이콘(⊕ 또는 모니터 모양)을 누르거나, 브라우저 메뉴 → "Mybody 설치".'
        : '브라우저 메뉴(⋮) → "앱 설치" 또는 "홈 화면에 추가".';

    var note = h('div.note', { style: { marginTop: '10px' },
      uid: 'P12-S05', uidLabel: '설치 방법 안내' }, [
      h('b', { text: '앱처럼 깔기' }),
      h('div', { style: { marginTop: '4px' }, text: how })
    ]);

    /* 개발 빌드로 띄우면 매니페스트도 서비스워커도 아예 없습니다.
       어떤 브라우저도 설치를 안 내줍니다 — 이건 진짜 고장입니다. */
    if (global.MB_BUILD && global.MB_BUILD.release === false) {
      note.appendChild(h('div.note--warn', { style: { marginTop: '6px' },
        text: '지금 열린 것은 개발 빌드입니다 — 설치에 필요한 파일이 안 들어 있습니다. ' +
              '서버를 배포 빌드(release)로 띄워야 깔 수 있습니다.' }));
      return note;
    }

    /* 임시 터널 주소(trycloudflare)는 **크롬이 설치를 막습니다.**
     *
     * 도메인이 아무나 즉석에서 받아 쓰는 공용이라 평판이 나쁘고,
     * 이 앱에는 비밀번호 칸이 있습니다 — 구글 Safe Browsing 의 두 신호가
     * 다 켜집니다. 주소창에 빨간 표시가 뜨고, 그 상태에서는 크롬이
     * 설치 버튼을 아예 안 내줍니다. 브라우저가 "덜 써 봐서" 가 아니라
     * **이 주소이기 때문에** 안 되는 것이라, 기다려도 안 바뀝니다.
     * 여기서 말 안 하면 사람이 메뉴를 몇 번이고 다시 뒤집니다. */
    var host = '';
    try { host = global.location.hostname || ''; } catch (e) {}
    if (/\.trycloudflare\.com$/i.test(host)) {
      note.appendChild(h('div.note--warn', { style: { marginTop: '6px' },
        text: '지금 주소는 임시 터널(trycloudflare.com)입니다. 이 도메인은 아무나 즉석에서 ' +
              '받아 쓰는 공용이라 크롬이 위험 사이트로 표시하고, 그 상태에서는 ' +
              '**앱 설치를 아예 안 내줍니다** — 기다려도 안 나옵니다. ' +
              '주소창에 빨간 표시가 있으면 그 이유입니다.' }));
      note.appendChild(h('div.muted', { style: { marginTop: '6px' },
        text: '앱은 그대로 쓸 수 있습니다. 깔려면 서버에 내 도메인을 붙여야 합니다 — ' +
              '그러면 주소도 더는 안 바뀝니다.' }));
      return note;
    }

    note.appendChild(h('div.muted', { style: { marginTop: '6px' },
      text: '여기 버튼이 안 보이는 것은 대개 고장이 아닙니다 — 크롬은 몇 번 써 본 뒤에야 ' +
            '설치 버튼을 내줍니다. 그 전에도 위 방법으로는 깔립니다.' }));

    /* 그래도 안 되면 무엇이 빠졌는지 직접 확인해 줍니다.
       비동기라 자리를 먼저 만들고 나중에 채웁니다 — 화면은 동기로 그립니다. */
    var diag = h('div.muted', { style: { marginTop: '6px', fontSize: '12px' },
      text: '설치 조건을 확인하는 중…' });
    note.appendChild(diag);
    checkInstallable(function (r) {
      if (!diag.isConnected) return;
      var bad = [];
      if (!r.secure) bad.push('https 가 아닙니다');
      if (!r.sw) bad.push('서비스워커가 등록되지 않았습니다');
      if (!r.manifest) bad.push('매니페스트를 못 읽었습니다');
      diag.textContent = bad.length
        ? '확인: ' + bad.join(' · ') + '. 이게 없으면 어떤 브라우저도 설치를 안 내줍니다.'
        : '확인: https · 서비스워커 · 매니페스트 모두 정상입니다. ' +
          '설치 조건은 갖춰졌으니 위 방법으로 깔면 됩니다.';
    });
    return note;
  }

  /** 설치에 필요한 세 가지가 실제로 갖춰졌는가. 화면이 짐작하지 않게. */
  function checkInstallable(cb) {
    var r = { secure: false, sw: false, manifest: false };
    try { r.secure = global.isSecureContext !== false; } catch (e) {}
    var steps = [];
    try {
      if (global.navigator && global.navigator.serviceWorker) {
        steps.push(global.navigator.serviceWorker.getRegistration()
          .then(function (reg) { r.sw = !!reg; })
          .catch(function () {}));
      }
    } catch (e) {}
    try {
      var link = document.querySelector('link[rel="manifest"]');
      if (link && global.fetch) {
        steps.push(global.fetch(link.href).then(function (res) {
          if (!res.ok) return null;
          return res.json().then(function (j) { r.manifest = !!(j && j.icons && j.icons.length); });
        }).catch(function () {}));
      }
    } catch (e) {}
    Promise.all(steps).then(function () { cb(r); }).catch(function () { cb(r); });
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
