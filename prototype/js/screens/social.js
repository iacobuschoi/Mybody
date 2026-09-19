/* P14 계정 · P15 친구 · P16 친구 상세 · P17 공유 설정 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;
  function B() { return global.MB_BACKEND; }

  /* ===================== P14 계정 ===================== */
  A.register('P14', {
    title: '계정', label: '계정',
    render: function (wrap, ctx) {
      var me = B().currentUser();

      if (!me) {
        wrap.appendChild(h('div.card', { uid: 'P14-C01', uidLabel: '로그인 카드' }, [
          h('div.card__title', { text: '로그인' }),
          h('div.muted', { style: { marginTop: '6px' },
            text: '기기를 바꿔도 기록이 남습니다. 친구와 함께 하려면 필요합니다.' }),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '14px' } }, [
            h('button.btn.btn--primary.btn--block', { text: '카카오로 시작',
              uid: 'P14-B01', uidLabel: '카카오 로그인',
              onClick: function () { doSignIn('kakao'); } }),
            h('button.btn.btn--block', { text: 'Apple로 시작',
              uid: 'P14-B02', uidLabel: '애플 로그인',
              onClick: function () { doSignIn('apple'); } }),
            h('button.btn.btn--ghost.btn--block', { text: '이메일로 시작',
              uid: 'P14-B03', uidLabel: '이메일 로그인',
              onClick: function () { doSignIn('email'); } })
          ])
        ]));
        wrap.appendChild(h('div.note', { uid: 'P14-C02', uidLabel: '프로토타입 안내',
          text: '프로토타입이라 실제 인증은 하지 않습니다. 누르면 바로 계정이 생깁니다.' }));
        wrap.appendChild(h('div.note', { uid: 'P14-C03', uidLabel: '개인정보 안내',
          text: '체성분은 민감한 정보입니다. 로그인해도 친구에게 자동으로 보이지 않습니다. 항목별로 직접 켜야 합니다.' }));
        return;
      }

      wrap.appendChild(h('div.card', { uid: 'P14-C01', uidLabel: '내 계정' }, [
        h('div.card__head', [
          h('div', [
            h('div.card__sub', { text: ({ kakao: '카카오', apple: 'Apple', email: '이메일' })[me.provider] || me.provider }),
            h('div', { style: { fontSize: '18px', fontWeight: '800' }, text: me.displayName })
          ]),
          h('span.badge.badge--ok', { text: '로그인됨' })
        ]),
        h('div.field', { style: { marginTop: '10px' } }, [
          h('div.field__label', { text: '표시 이름' }),
          nameInput(me)
        ]),
        h('div.kv', [h('span.kv__k', { text: '내 초대 코드' }),
                     h('span.kv__v', { style: { fontFamily: 'ui-monospace, monospace' }, text: me.inviteCode })]),
        h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--sm', { text: '친구', uid: 'P14-B05', uidLabel: '친구 화면으로',
            onClick: function () { A.go('P15'); } }),
          h('button.btn.btn--sm', { text: '로그아웃', uid: 'P14-B04', uidLabel: '로그아웃',
            onClick: function () { B().signOut(); global.MB_UID.toast('로그아웃했습니다'); A.refresh(); } })
        ])
      ]));

      wrap.appendChild(h('div.card', { uid: 'P14-C04', uidLabel: '동기화 상태' }, [
        h('div.card__title', { text: '동기화' }),
        h('div.muted', { style: { marginTop: '6px' },
          text: '측정 기록은 이 기기에 먼저 저장되고, 그다음 계정으로 올라갑니다. 인터넷이 없어도 앱은 그대로 동작합니다.' }),
        h('div.kv', { style: { marginTop: '8px' } },
          [h('span.kv__k', { text: '이 기기 기록' }),
           h('span.kv__v', { text: S.get().scans.length + '건' })]),
        h('div.note', { style: { marginTop: '10px' },
          text: '프로토타입에서는 실제로 올라가지 않습니다. 화면과 권한 규칙만 진짜입니다.' })
      ]));

      wrap.appendChild(h('div.card', { uid: 'P14-C05', uidLabel: '계정 삭제' }, [
        h('div.card__title', { text: '계정 삭제' }),
        h('div.muted', { style: { marginTop: '6px' },
          text: '친구 관계와 공유한 내용이 모두 지워집니다. 이 기기의 기록은 남습니다.' }),
        h('button.btn.btn--danger.btn--sm', { text: '계정 삭제', style: { marginTop: '10px' },
          uid: 'P14-B06', uidLabel: '계정 삭제',
          onClick: function () { global.MB_MODALS.deleteAccount(function () { A.refresh(); }); } })
      ]));

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
      function doSignIn(provider) {
        var u = B().signIn({ provider: provider });
        global.MB_UID.toast(u.displayName + '으로 로그인했습니다');
        A.refresh();
      }
    }
  });

  /* ===================== P15 친구 ===================== */
  A.register('P15', {
    title: '친구', label: '친구',
    render: function (wrap, ctx) {
      var me = B().currentUser();
      if (!me) return needLogin(wrap, 'P15');
      var f = B().listFriends();

      wrap.appendChild(h('div.card.card--accent', { uid: 'P15-C01', uidLabel: '내 초대 코드' }, [
        h('div.card__sub', { text: '이 코드를 친구에게 알려주세요' }),
        h('div', { style: { fontSize: '26px', fontWeight: '900', letterSpacing: '.12em',
                            fontFamily: 'ui-monospace, monospace', margin: '6px 0' },
                   text: me.inviteCode }),
        h('div.btn-row', [
          h('button.btn.btn--sm', { text: '코드 복사', uid: 'P15-B01', uidLabel: '초대 코드 복사',
            onClick: function () {
              if (navigator.clipboard) navigator.clipboard.writeText(me.inviteCode);
              global.MB_UID.toast('복사했습니다');
            } }),
          h('button.btn.btn--sm.btn--primary', { text: '친구 추가', uid: 'P15-B02', uidLabel: '친구 추가',
            onClick: function () { global.MB_MODALS.addFriend(function () { A.refresh(); }); } })
        ]),
        h('div.muted', { style: { marginTop: '8px' },
          text: '전화번호나 이메일로는 찾을 수 없습니다. 코드를 직접 알려준 사람만 추가됩니다.' })
      ]));

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
        wrap.appendChild(inc);
      }

      if (!f.accepted.length) {
        wrap.appendChild(h('div.empty', { uid: 'P15-S01', uidLabel: '친구 없음' }, [
          h('div.empty__ico', { text: '👥' }),
          h('div.empty__t', { text: '아직 친구가 없습니다' }),
          h('div.empty__d', { text: '같이 하는 사람이 있으면 더 오래 합니다.' })
        ]));
      } else {
        var list = h('div', { uid: 'P15-L01', uidLabel: '친구 목록' });
        list.appendChild(h('div.section-title', { text: '친구 ' + f.accepted.length + '명' }));
        f.accepted.forEach(function (r, i) {
          list.appendChild(h('div.card', {
            style: { cursor: 'pointer' },
            onClick: function () { A.go('P16', { friendId: r.id }); }
          }, [
            h('div.card__head', [
              h('div', [
                h('div.card__title', { text: r.displayName }),
                h('div.card__sub', { text: r.theyShare.count
                  ? '나에게 ' + r.theyShare.labels.slice(0, 2).join('·') + (r.theyShare.count > 2 ? ' 외' : '') + ' 공유'
                  : '나에게 공유하는 항목 없음' })
              ]),
              h('span.badge' + (r.iShare.count ? '.badge--accent' : ''),
                { text: '내가 공유 ' + r.iShare.count + '개' })
            ])
          ]));
        });
        wrap.appendChild(list);
      }

      if (f.outgoing.length) {
        wrap.appendChild(h('div.card.card--flat', { uid: 'P15-L03', uidLabel: '보낸 요청' }, [
          h('div.card__sub', { text: '보낸 요청 ' + f.outgoing.length + '건 · 수락을 기다리는 중' }),
          h('div.chips', { style: { marginTop: '6px' } },
            f.outgoing.map(function (r) { return h('span.chip', { text: r.displayName }); }))
        ]));
      }

      wrap.appendChild(h('div.note', { uid: 'P15-C02', uidLabel: '공유 원칙',
        text: '친구를 맺어도 아무것도 공개되지 않습니다. 항목별로 직접 켜야 보입니다.' }));
    }
  });

  /* ===================== P16 친구 상세 ===================== */
  A.register('P16', {
    title: '친구', label: '친구 상세',
    render: function (wrap, ctx) {
      var me = B().currentUser();
      if (!me) return needLogin(wrap, 'P16');
      var fid = ctx.params.friendId;
      var f = B().listFriends();
      var friend = f.accepted.filter(function (r) { return r.id === fid; })[0];
      if (!friend) {
        wrap.appendChild(h('div.empty', { uid: 'P16-S01', uidLabel: '친구 없음' }, [
          h('div.empty__t', { text: '친구를 찾을 수 없습니다' }),
          h('button.btn.btn--primary', { text: '친구 목록', uid: 'P16-B03', uidLabel: '친구 목록으로',
            onClick: function () { A.go('P15'); } })
        ]));
        return;
      }
      this.title = friend.displayName;

      var res = B().getFriendSnapshots(fid, 26);
      var rows = (res.rows || []).slice().reverse();

      wrap.appendChild(h('div.card', { uid: 'P16-C01', uidLabel: '친구 헤더' }, [
        h('div.card__head', [
          h('div', [
            h('div', { style: { fontSize: '18px', fontWeight: '800' }, text: friend.displayName }),
            h('div.card__sub', { text: UI.dateK(friend.since) + ' 부터 친구' })
          ]),
          h('span.badge', { text: rows.length + '주 기록' })
        ])
      ]));

      if (!rows.length) {
        wrap.appendChild(h('div.empty', { uid: 'P16-S02', uidLabel: '공유 없음' }, [
          h('div.empty__ico', { text: '🔒' }),
          h('div.empty__t', { text: friend.displayName + '님이 아직 공유한 게 없습니다' }),
          h('div.empty__d', { text: '무엇을 보여줄지는 각자가 정합니다.' })
        ]));
      } else {
        var latest = rows[rows.length - 1];
        var keys = [
          { k: 'dBfmKg', label: '체지방', color: 'var(--fat)', unit: 'kg', good: -1 },
          { k: 'dSmmKg', label: '골격근', color: 'var(--muscle)', unit: 'kg', good: 1 },
          { k: 'dWeightKg', label: '체중', color: 'var(--weight)', unit: 'kg', good: 0 }
        ].filter(function (x) { return latest[x.k] != null; });

        if (keys.length) {
          wrap.appendChild(h('div.card', { uid: 'P16-C02', uidLabel: '친구 변화' }, [
            h('div.card__head', [h('div.card__title', { text: '최근 한 주' }),
                                 h('div.card__sub', { text: UI.dateShort(latest.weekStart) + ' 주' })]),
            h('div.stats', keys.map(function (x) {
              return h('div.stat', [
                h('div.stat__k', { text: x.label }),
                h('div', [h('span.stat__v', { style: { color: x.color }, text: UI.sign(latest[x.k]) }),
                          h('span.stat__u', { text: x.unit })])
              ]);
            }))
          ]));

          var series = keys.map(function (x) {
            return { key: x.k, label: x.label, color: x.color, dots: rows.length <= 14,
                     points: rows.map(function (r, i) { return { x: i, y: cum(rows, x.k, i) }; }) };
          });
          wrap.appendChild(h('div.card', { uid: 'P16-C03', uidLabel: '친구 추이' }, [
            h('div.card__head', [h('div.card__title', { text: '누적 변화' }),
                                 h('div.card__sub', { text: '공유된 항목만' })]),
            UI.lineChart({ uid: 'P16-G01', label: '친구 누적 변화', height: 150,
              series: series, xTickFmt: function (v) { return Math.round(v) + '주'; } })
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

        var streaks = rows.filter(function (r) { return r.checkedIn; }).length;
        if (rows.some(function (r) { return r.checkedIn != null; })) {
          wrap.appendChild(h('div.card.card--flat', { uid: 'P16-C05', uidLabel: '친구 체크인' }, [
            h('div.card__title', { text: '체크인' }),
            h('div.muted', { text: '최근 ' + rows.length + '주 중 ' + streaks + '주 기록했습니다.' }),
            h('div.chips', { style: { marginTop: '8px' } }, rows.slice(-12).map(function (r) {
              return h('span.chip' + (r.checkedIn ? '.is-on' : ''), { text: UI.dateShort(r.weekStart) });
            }))
          ]));
        }
      }

      wrap.appendChild(h('div.card', { uid: 'P16-C06', uidLabel: '내가 공유하는 것' }, [
        h('div.card__head', [
          h('div.card__title', { text: '내가 공유하는 것' }),
          h('span.badge' + (friend.iShare.count ? '.badge--accent' : ''),
            { text: friend.iShare.count + '개' })
        ]),
        h('div.muted', { text: friend.iShare.count
          ? friend.iShare.labels.join(' · ')
          : '아무것도 공유하지 않고 있습니다.' }),
        h('div.btn-row', { style: { marginTop: '10px' } }, [
          h('button.btn.btn--sm.btn--primary', { text: '공유 설정', uid: 'P16-B01', uidLabel: '공유 설정',
            onClick: function () { A.go('P17', { friendId: fid }); } }),
          h('button.btn.btn--sm.btn--danger', { text: '친구 끊기', uid: 'P16-B02', uidLabel: '친구 끊기',
            onClick: function () {
              global.MB_MODALS.removeFriend(friend, function () {
                B().removeFriend(fid); global.MB_UID.toast('친구를 끊었습니다'); A.go('P15');
              });
            } })
        ])
      ]));

      function cum(list, key, upto) {
        var t = 0;
        for (var i = 0; i <= upto; i++) t += (list[i][key] || 0);
        return Math.round(t * 100) / 100;
      }
    }
  });

  /* ===================== P17 공유 설정 ===================== */
  A.register('P17', {
    title: '공유 설정', label: '공유 설정',
    render: function (wrap, ctx) {
      var me = B().currentUser();
      if (!me) return needLogin(wrap, 'P17');
      var fid = ctx.params.friendId;
      var f = B().listFriends();
      var friend = f.accepted.filter(function (r) { return r.id === fid; })[0];
      if (!friend) { A.go('P15'); return; }

      var cur = B().getShare(me.id, fid);

      wrap.appendChild(h('div.card.card--flat', { uid: 'P17-C01', uidLabel: '공유 대상' }, [
        h('div.card__sub', { text: '이 설정은' }),
        h('div', { style: { fontSize: '17px', fontWeight: '800' }, text: friend.displayName + '님에게만 적용됩니다' }),
        h('div.muted', { style: { marginTop: '4px' },
          text: '친구마다 따로 정할 수 있습니다.' })
      ]));

      var fields = B().SHARE_FIELDS;
      var list = h('div.radio-cards', { uid: 'P17-C02', uidLabel: '공유 항목' });
      fields.forEach(function (fld, i) {
        var on = !!cur[fld.key];
        var desc = ({
          weightTrend: '주마다 체중이 얼마나 변했는지',
          smmTrend: '주마다 골격근이 얼마나 변했는지',
          bfmTrend: '주마다 체지방이 얼마나 변했는지',
          planProgress: '내 목표까지 몇 퍼센트 왔는지',
          streak: '이번 주에 기록을 했는지 여부',
          absolute: '변화량이 아니라 지금 실제 수치까지'
        })[fld.key];
        list.appendChild(h('label.radio-card' + (on ? '.is-on' : ''), {
          uid: 'P17-F0' + (i + 1), uidLabel: fld.label + ' 공유',
          onClick: function () {
            var patch = {}; patch[fld.key] = !on;
            var r = B().setShare(fid, patch);
            if (!r.ok) { global.MB_UID.toast(r.reason); return; }
            A.refresh();
          }
        }, [
          h('span', { text: on ? '✓' : '·', style: { width: '14px', fontWeight: '800',
                                                     color: on ? 'var(--accent)' : 'var(--text-3)' } }),
          h('div', [
            h('div.radio-card__t', { text: fld.label }),
            h('div.radio-card__d', { text: desc })
          ])
        ]));
      });
      wrap.appendChild(list);

      if (cur.absolute) {
        wrap.appendChild(h('div.note.note--warn', { uid: 'P17-S01', uidLabel: '실제 수치 경고',
          text: '실제 수치는 변화량보다 민감합니다. 출발점이 다른 사람끼리 숫자를 비교하면 잘하고 있어도 못하는 것처럼 느낍니다.' }));
      }

      /* 지금 이 친구가 실제로 보는 것 */
      var preview = previewFor(me, fid);
      wrap.appendChild(h('div.card', { uid: 'P17-C03', uidLabel: '상대가 보는 화면 미리보기' }, [
        h('div.card__head', [h('div.card__title', { text: friend.displayName + '님이 보는 것' }),
                             h('div.card__sub', { text: '지금 설정 기준' })]),
        preview
      ]));

      wrap.appendChild(h('div.btn-row', [
        h('button.btn', { text: '전부 끄기', uid: 'P17-B02', uidLabel: '공유 전부 끄기',
          onClick: function () {
            global.MB_MODALS.stopSharing(friend, function () {
              var off = {};
              B().SHARE_FIELDS.forEach(function (x) { off[x.key] = false; });
              B().setShare(fid, off);
              global.MB_UID.toast('공유를 모두 껐습니다');
              A.refresh();
            });
          } }),
        h('button.btn.btn--primary', { text: '완료', uid: 'P17-B01', uidLabel: '공유 설정 완료',
          onClick: function () { A.go('P16', { friendId: fid }); } })
      ]));

      wrap.appendChild(h('div.muted', { style: { marginTop: '10px', textAlign: 'center' },
        text: '끄면 상대 화면에서 바로 사라집니다.' }));
    }
  });

  /* --- 조각 --- */
  function needLogin(wrap, uidPrefix) {
    wrap.appendChild(h('div.empty', { uid: uidPrefix + '-S90', uidLabel: '로그인 필요' }, [
      h('div.empty__ico', { text: '🔑' }),
      h('div.empty__t', { text: '로그인이 필요합니다' }),
      h('div.empty__d', { text: '친구 기능은 계정이 있어야 씁니다.' }),
      h('button.btn.btn--primary', { text: '로그인하러 가기',
        uid: uidPrefix + '-B90', uidLabel: '로그인하러 가기',
        onClick: function () { A.go('P14'); } })
    ]));
  }

  function previewFor(me, fid) {
    var allowed = B().getShare(me.id, fid);
    var on = B().SHARE_FIELDS.filter(function (f) { return allowed[f.key]; });
    if (!on.length) {
      return h('div.muted', { text: '아무것도 보이지 않습니다. 이름만 보입니다.' });
    }
    var st = S.get();
    var scans = S.sortedScans();
    var box = h('div');
    var sample = sampleSnapshot(st, scans);
    on.forEach(function (f) {
      var line;
      if (f.key === 'weightTrend') line = '체중 ' + UI.sign(sample.dWeightKg) + 'kg';
      else if (f.key === 'smmTrend') line = '골격근 ' + UI.sign(sample.dSmmKg) + 'kg';
      else if (f.key === 'bfmTrend') line = '체지방 ' + UI.sign(sample.dBfmKg) + 'kg';
      else if (f.key === 'planProgress') line = '목표 달성률 ' + (sample.progressPct == null ? '—' : sample.progressPct + '%');
      else if (f.key === 'streak') line = '이번 주 기록 ' + (sample.checkedIn ? '함' : '안 함');
      else if (f.key === 'absolute') line = '실제 수치 — 체중 ' + UI.n1(sample.weightKg) + 'kg · 체지방 ' + UI.n1(sample.bfmKg) + 'kg';
      box.appendChild(h('div.kv', [h('span.kv__k', { text: f.label }), h('span.kv__v', { text: line })]));
    });
    return box;
  }

  /** 이번 주 스냅샷 — 친구에게 올릴 값이자 미리보기 값 */
  function sampleSnapshot(st, scans) {
    var prof = st.profile || global.MB_DATA.SEED_PROFILE;
    var out = { dWeightKg: 0, dSmmKg: 0, dBfmKg: 0, progressPct: null, checkedIn: false };
    if (scans.length >= 2) {
      var a = E.derive(scans[scans.length - 2], prof), b = E.derive(scans[scans.length - 1], prof);
      out.dWeightKg = Math.round((b.weightKg - a.weightKg) * 10) / 10;
      out.dSmmKg = Math.round((b.smmKg - a.smmKg) * 100) / 100;
      out.dBfmKg = Math.round((b.bfmKg - a.bfmKg) * 100) / 100;
    }
    if (scans.length) {
      var last = E.derive(scans[scans.length - 1], prof);
      out.weightKg = last.weightKg; out.smmKg = last.smmKg;
      out.bfmKg = last.bfmKg; out.pbfPct = last.pbfPct;
    }
    if (st.plan && st.goal && scans.length) {
      var cur = E.derive(scans[scans.length - 1], prof);
      var s0 = st.plan.trajectory[0].bfmKg, t0 = st.goal.bfmKg;
      if (Math.abs(s0 - t0) > 0.01) {
        out.progressPct = Math.max(0, Math.min(100, Math.round((s0 - cur.bfmKg) / (s0 - t0) * 100)));
      }
    }
    out.checkedIn = !!(st.checkins && st.checkins.length);
    return out;
  }

  global.MB_SOCIAL = { sampleSnapshot: sampleSnapshot };
})(window);
