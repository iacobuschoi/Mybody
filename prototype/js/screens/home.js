/* P02 — 홈 대시보드 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  A.register('P02', {
    title: '홈', label: '홈 대시보드',
    render: function (wrap, ctx) {
      var st = S.get();
      var scans = S.sortedScans();
      var scan = S.latestScan();

      /* --- C20 이사 안내 ---
         설정이 탭에서 앱바 톱니로 옮겨갔습니다. 토스트로 알리면 놓쳤을 때
         다시 볼 방법이 없고, 하필 "설정이 사라졌다"고 느끼는 순간에 없습니다.
         닫을 수 있는 카드로 두고 3번 보면 스스로 사라집니다. */
      (function () {
        var se = st.settings || {};
        if (se.gearHintDismissed || (se.gearHintSeen || 0) >= 3) return;
        S.set({ settings: Object.assign({}, se, { gearHintSeen: (se.gearHintSeen || 0) + 1 }) });
        var note = h('div.note', { uid: 'P02-C20', uidLabel: '설정 이사 안내' }, [
          h('b', { text: '설정은 오른쪽 위 ⚙️ 로 옮겼습니다.' }),
          h('div', { style: { marginTop: '3px' }, text: '다섯 번째 탭은 이제 친구입니다.' }),
          h('button.btn.btn--ghost.btn--sm', { text: '알겠습니다', style: { marginTop: '8px' },
            uid: 'P02-B20', uidLabel: '안내 닫기',
            onClick: function () {
              S.set({ settings: Object.assign({}, S.get().settings, { gearHintDismissed: true }) });
              A.refresh();
            } })
        ]);
        wrap.appendChild(note);
      })();

      if (!scan) {
        wrap.appendChild(h('div.empty', { uid: 'P02-S01', uidLabel: '첫 인바디 유도 빈 상태' }, [
          h('div.empty__ico', { text: '📷' }),
          h('div.empty__t', { text: '인바디 결과지를 올려주세요' }),
          h('div.empty__d', { text: '사진 한 장이면 현재 상태를 읽고 계획을 만듭니다.' }),
          h('button.btn.btn--primary', { text: '인바디 올리기', uid: 'P02-B01',
            uidLabel: '인바디 올리기', onClick: function () { A.go('P03'); } }),
          h('div', { style: { marginTop: '10px' } }, [
            h('button.btn.btn--ghost.btn--sm', { text: '내 실제 데이터로 채우기 (프로토타입)',
              uid: 'P02-B02', uidLabel: '시드 데이터 주입',
              onClick: function () { S.seed(); global.MB_UID.toast('실제 인바디 3건을 불러왔습니다'); A.refresh(); } })
          ])
        ]));
        return;
      }

      var d = E.derive(scan, st.profile || global.MB_DATA.SEED_PROFILE);
      var prev = scans.length > 1 ? scans[scans.length - 2] : null;
      var pd = prev ? E.derive(prev, st.profile || global.MB_DATA.SEED_PROFILE) : null;

      /* --- C01 최신 인바디 요약 --- */
      var summary = h('div.card', { uid: 'P02-C01', uidLabel: '최신 인바디 요약' }, [
        h('div.card__head', [
          h('div.card__title', { text: '최신 인바디' }),
          h('div.card__sub', { text: UI.dateK(scan.measuredAt) + (scan.device ? ' · ' + scan.device : '') })
        ]),
        h('div.stats', [
          statBox('체중', d.weightKg, 'kg', pd ? d.weightKg - pd.weightKg : null, ''),
          statBox('골격근량', d.smmKg, 'kg', pd ? d.smmKg - pd.smmKg : null, 'muscle'),
          statBox('체지방량', d.bfmKg, 'kg', pd ? d.bfmKg - pd.bfmKg : null, 'fat'),
          statBox('체지방률', d.pbfPct, '%', pd ? d.pbfPct - pd.pbfPct : null, 'fat')
        ]),
        scan.inbodyScore ? h('div', { style: { marginTop: '12px' } }, [
          h('div.kv', [h('span.kv__k', { text: 'InBody 점수' }),
                       h('span.kv__v', { text: scan.inbodyScore + ' / 100' })]),
          h('div.kv', [h('span.kv__k', { text: '기초대사량' }),
                       h('span.kv__v', { text: d.bmrKcal + ' kcal' })]),
          h('div.kv', [h('span.kv__k', { text: '내장지방 레벨' }),
                       h('span.kv__v', { text: String(scan.visceralFatLevel || '—') })])
        ]) : null
      ]);
      wrap.appendChild(summary);

      /* --- 목표가 바뀐 채로 남은 플랜 --- */
      if (st.goal && st.plan && !S.planMatchesGoal()) {
        wrap.appendChild(h('div.note.note--warn', { uid: 'P02-C07', uidLabel: '목표 불일치 안내' }, [
          h('b', { text: '목표가 바뀌었습니다. ' }),
          '플랜을 다시 만들어야 아래 숫자가 맞습니다.',
          h('button.btn.btn--sm.btn--primary.btn--block', { text: '플랜 다시 만들기',
            style: { marginTop: '10px' }, uid: 'P02-B11', uidLabel: '플랜 다시 만들기',
            onClick: function () { A.go('P07'); } })
        ]));
      }

      /* --- C02 목표 진행 --- */
      if (st.goal && st.plan) {
        var plan = st.plan;
        var base = st.baselinePlan || plan;
        var drift = E.planDrift(plan, scans, st.profile || global.MB_DATA.SEED_PROFILE);
        var todayISO = E.toISODate(new Date());

        // 지금 예상 도착일 — 재계산에 실패하면 계획상 목표일을 그대로 쓴다
        var projected = (drift && drift.projectedDate) || plan.targetDate;
        var dday = E.daysUntil(projected);
        var baseDelta = E.daysUntil(base.targetDate, projected);   // 양수 = 원래보다 당겨짐

        var startBfm = plan.trajectory[0].bfmKg, targetBfm = st.goal.bfmKg;
        var doneFat = clamp((startBfm - d.bfmKg) / (startBfm - targetBfm) * 100);
        var startSmm = plan.trajectory[0].smmKg, targetSmm = st.goal.smmKg;
        var doneSmm = targetSmm > startSmm
          ? clamp((d.smmKg - startSmm) / (targetSmm - startSmm) * 100) : 100;
        var overall = Math.round((doneFat + doneSmm) / 2);

        var card = h('div.card.card--accent', { uid: 'P02-C02', uidLabel: '목표 진행 카드' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '목표까지' }),
          h('div', { style: { display: 'flex', gap: '4px' } }, [
            plan.mode ? h('span.badge', { text: plan.mode.nameKo }) : null,
            h('span.badge.badge--accent', { text: plan.label + ' 강도' })
          ])
        ]));

        card.appendChild(h('div', { style: { display: 'flex', gap: '14px', alignItems: 'center' } }, [
          UI.donut(overall, 'var(--accent)', 62),
          h('div', { style: { flex: '1', minWidth: '0' } }, [
            h('div', { style: { display: 'flex', alignItems: 'baseline', gap: '6px', flexWrap: 'wrap' } }, [
              h('span', { style: { fontSize: '22px', fontWeight: '800', letterSpacing: '-.02em' },
                text: dday > 0 ? 'D−' + dday : (dday === 0 ? 'D−DAY' : 'D+' + Math.abs(dday)) }),
              Math.abs(baseDelta) >= 3 ? h('span.badge' + (baseDelta > 0 ? '.badge--ok' : '.badge--warn'), {
                style: { fontSize: '10.5px' },
                text: (baseDelta > 0 ? '−' : '+') + Math.abs(baseDelta) + '일' }) : null
            ]),
            h('div.muted', { text: UI.dateK(projected) + ' 도착 예정' })
          ])
        ]));

        /* 원래 계획과 지금 계획을 한 축에 */
        var sameDate = Math.abs(baseDelta) < 1;
        card.appendChild(h('div', { style: { marginTop: '10px' } }, [
          UI.timeline({
            uid: 'P02-G04', label: '계획 대비 도착 예정일',
            start: base.startDate, today: todayISO,
            marks: [
              { date: base.targetDate, label: '원래 ' + UI.dateShort(base.targetDate),
                color: 'var(--text-3)', dashed: true },
              sameDate ? null : { date: projected, label: '지금 ' + UI.dateShort(projected),
                color: baseDelta > 0 ? 'var(--ok)' : 'var(--warn)', below: true }
            ].filter(Boolean)
          })
        ]));

        if (drift) {
          var cls = drift.status === 'ahead' ? '--ok'
                  : (drift.status === 'onTrack' ? '' : '--warn');
          card.appendChild(h('div.note.note' + cls, { style: { marginTop: '4px' } }, [
            h('b', { text: drift.headline }),
            drift.status !== 'onTrack'
              ? ' 계획상 오늘 체지방 ' + UI.n1(drift.expected.bfmKg) + 'kg, 실제 ' +
                UI.n1(drift.actual.bfmKg) + 'kg.'
              : ''
          ]));
          if (drift.recommendChange) {
            card.appendChild(h('div.btn-row', { style: { marginTop: '8px' } }, [
              h('button.btn.btn--sm.btn--primary', { text: '계획 다시 세우기',
                uid: 'P02-B12', uidLabel: '계획 재조정',
                onClick: function () { A.go('P07'); } }),
              h('button.btn.btn--sm', { text: '왜?', uid: 'P02-B13', uidLabel: '재조정 이유',
                onClick: function () { explainDrift(drift, base, plan, projected); } })
            ]));
          }
        }

        card.appendChild(h('hr.sep'));
        card.appendChild(progressRow('체지방', d.bfmKg, targetBfm, 'kg', doneFat, 'fat'));
        card.appendChild(progressRow('골격근', d.smmKg, targetSmm, 'kg', doneSmm, 'muscle'));
        card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--sm', { text: '플랜 보기', uid: 'P02-B03', uidLabel: '플랜 보기',
            onClick: function () { A.go('P07'); } }),
          h('button.btn.btn--sm', { text: '목표 변경', uid: 'P02-B04', uidLabel: '목표 변경',
            onClick: function () { A.go('P05'); } })
        ]));
        wrap.appendChild(card);
      } else {
        wrap.appendChild(h('div.card', { uid: 'P02-C03', uidLabel: '목표 미설정 안내' }, [
          h('div.empty', { style: { padding: '16px 0' } }, [
            h('div.empty__t', { text: '목표를 정하면 계획이 생성됩니다' }),
            h('div.empty__d', { text: '목표 체중 · 골격근량 · 체지방량을 입력하면 언제 달성 가능한지 계산해 드립니다.' }),
            h('button.btn.btn--primary', { text: '목표 설정하기', uid: 'P02-B05',
              uidLabel: '목표 설정하기', onClick: function () { A.go('P05'); } })
          ])
        ]));
      }

      /* --- C04 플랜 (오늘 / 이번주 / 한달) ---
         전체 플랜은 20주가 넘어서 홈에서 보기엔 너무 깁니다.
         지금 무엇을 할지(오늘), 이번 주에 뭘 끝내야 하는지(이번주),
         한 달 뒤 어디쯤인지(한달)로 나눠서 봅니다. */
      if (st.plan) wrap.appendChild(planScopeCard(st.plan));

      /* --- C05 추이 스파크라인 --- */
      if (scans.length >= 2) {
        var prof = st.profile || global.MB_DATA.SEED_PROFILE;
        var ws = scans.map(function (s) { return E.derive(s, prof).weightKg; });
        var ms = scans.map(function (s) { return E.derive(s, prof).smmKg; });
        var fs = scans.map(function (s) { return E.derive(s, prof).pbfPct; });
        wrap.appendChild(h('div.card', { uid: 'P02-C05', uidLabel: '추이 스파크라인' }, [
          h('div.card__head', [
            h('div.card__title', { text: '추이' }),
            h('button.btn.btn--ghost.btn--sm', { text: '자세히 ›', uid: 'P02-B07',
              uidLabel: '추이 자세히', onClick: function () { A.go('P09'); } })
          ]),
          h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: '10px' } }, [
            sparkBox('체중', ws, 'var(--weight)', 'kg', 'P02-G01'),
            sparkBox('골격근', ms, 'var(--muscle)', 'kg', 'P02-G02'),
            sparkBox('체지방률', fs, 'var(--fat)', '%', 'P02-G03')
          ]),
          h('div.muted', { style: { marginTop: '8px' },
            text: scans.length + '회 측정 · ' + UI.dateShort(scans[0].measuredAt) + ' ~ ' + UI.dateShort(scan.measuredAt) })
        ]));
      }

      /* --- C06 다음 행동 --- */
      wrap.appendChild(h('div.card', { uid: 'P02-C06', uidLabel: '다음 행동 배너' }, [
        h('div.card__title', { text: '다음에 할 일' }),
        h('div.btn-row.btn-row--stack', { style: { marginTop: '10px' } }, [
          h('button.btn.btn--block', { text: '📷 인바디 새로 올리기', uid: 'P02-B08',
            uidLabel: '인바디 새로 올리기', onClick: function () { A.go('P03'); } }),
          st.plan ? h('button.btn.btn--block', { text: '✅ 이번 주 체크인', uid: 'P02-B09',
            uidLabel: '이번 주 체크인', onClick: function () { A.go('P08'); } }) : null,
          h('button.btn.btn--block', { text: '🗂 측정 기록 보기', uid: 'P02-B10',
            uidLabel: '측정 기록 보기', onClick: function () { A.go('P10'); } })
        ])
      ]));
    }
  });

  function clamp(x) { return Math.max(0, Math.min(100, x)); }

  /** 왜 계획을 다시 세우라고 하는지 */
  function explainDrift(drift, base, plan, projected) {
    UI.openModal({
      uid: 'M36', title: '왜 다시 세우라고 하나요',
      sub: drift.headline,
      body: [
        h('div.kv', [h('span.kv__k', { text: '계획상 오늘' }),
                     h('span.kv__v', { text: '체지방 ' + UI.n1(drift.expected.bfmKg) + 'kg' })]),
        h('div.kv', [h('span.kv__k', { text: '실제' }),
                     h('span.kv__v', { text: '체지방 ' + UI.n1(drift.actual.bfmKg) + 'kg' })]),
        h('div.kv', [h('span.kv__k', { text: '원래 목표일' }),
                     h('span.kv__v', { text: UI.dateK(base.targetDate) })]),
        h('div.kv', [h('span.kv__k', { text: '지금 예상' }),
                     h('span.kv__v', { text: UI.dateK(projected) })]),
        h('div.note', { style: { marginTop: '12px' },
          text: drift.status === 'ahead'
            ? '앞서 있으면 지금 칼로리로도 충분하다는 뜻입니다. 다시 세우면 속도를 낮춰 근육을 더 지킬 수 있습니다.'
            : '뒤처져 있으면 계획이 지금 몸 상태와 안 맞습니다. 다시 세우면 남은 거리에 맞게 조정됩니다.' }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '다시 세워도 원래 계획은 그래프에 남습니다. 비교는 계속 됩니다.' })
      ],
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  }

  function statBox(label, val, unit, delta, mod) {
    var uidMap = { '체중': 'P02-C01', '골격근량': 'P02-C01', '체지방량': 'P02-C01', '체지방률': 'P02-C01' };
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(val) }), h('span.stat__u', { text: unit })]),
      delta != null && Math.abs(delta) >= 0.05
        ? h('div.stat__d' + (delta > 0 ? '.up' : '.down'), { text: UI.sign(delta) + unit })
        : h('div.stat__d', { text: ' ' })
    ]);
  }

  var DOW = ['월', '화', '수', '목', '금', '토', '일'];

  /** 오늘이 플랜의 몇 주차인지 (0부터) */
  function planWeek(plan) {
    var start = new Date(plan.startDate);
    var days = Math.floor((new Date() - start) / 86400000);
    return Math.max(0, Math.min((plan.trajectory || []).length - 1, Math.floor(days / 7)));
  }

  function planScopeCard(plan) {
    var scope = 'today';
    var card = h('div.card', { uid: 'P02-C04', uidLabel: '플랜 보기' });
    var body = h('div');
    var wk = planWeek(plan);
    var totalW = plan.weeks;

    var SCOPES = [
      { key: 'today', label: '오늘', uid: 'P02-B14' },
      { key: 'week',  label: '이번주', uid: 'P02-B15' },
      { key: 'month', label: '한달',  uid: 'P02-B16' }
    ];
    var tabs = h('div.chips', { style: { marginBottom: '10px' } },
      SCOPES.map(function (sc) {
        return h('button.chip' + (sc.key === scope ? '.is-on' : ''), {
          text: sc.label, uid: sc.uid, uidLabel: sc.label + ' 플랜',
          onClick: function () {
            scope = sc.key;
            tabs.querySelectorAll('.chip').forEach(function (x, i) {
              x.classList.toggle('is-on', SCOPES[i].key === scope);
            });
            render();
          } });
      }));

    card.appendChild(h('div.card__head', [
      h('div.card__title', { text: '플랜' }),
      h('div.card__sub', { text: (wk + 1) + '주차 / ' + totalW + '주' })
    ]));
    card.appendChild(tabs);
    card.appendChild(body);

    function render() {
      body.textContent = '';
      var m = plan.macros;
      var sessions = plan.workout.sessions || [];
      var todayIdx = new Date().getDay() === 0 ? 6 : new Date().getDay() - 1;

      if (scope === 'today') {
        var sess = sessions[todayIdx];
        body.appendChild(h('div.card__sub', { style: { marginBottom: '6px' },
          text: DOW[todayIdx] + '요일' }));
        body.appendChild(kv('운동', sess ? (sess.rest ? '휴식' : sess.label) : '—'));
        body.appendChild(kv('섭취 목표', m.intakeKcal + ' kcal'));
        body.appendChild(kv('단백질', m.proteinG + ' g'));

      } else if (scope === 'week') {
        /* 이번 주에는 몸 변화를 목표로 걸지 않습니다.
           주 단위 변화는 인바디 오차(체중 ±1.0kg, 체지방 ±1.0kg)보다 작아서,
           "이번 주 -0.2kg 달성/미달"은 측정값이 아니라 동전던지기가 됩니다.
           대신 셀 수 있는 것 — 운동 횟수와 식단 — 을 겁니다. */
        var trains = sessions.filter(function (x) { return x && !x.rest; });
        var grid = h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(7,1fr)',
                                       gap: '4px', margin: '2px 0 12px' } });
        DOW.forEach(function (d, i) {
          var sx = sessions[i];
          var on = sx && !sx.rest;
          grid.appendChild(h('div', {
            style: { textAlign: 'center', padding: '6px 2px', borderRadius: '8px',
                     fontSize: '11px', fontWeight: '700',
                     border: i === todayIdx ? '2px solid var(--accent)' : '1px solid var(--border)',
                     background: on ? 'color-mix(in srgb, var(--muscle) 16%, transparent)' : 'transparent',
                     color: on ? 'var(--text)' : 'var(--text-3)' } }, [
            h('div', { text: d }),
            h('div', { style: { marginTop: '2px', fontSize: '13px' }, text: on ? '운동' : '휴식' })
          ]));
        });
        body.appendChild(grid);
        body.appendChild(kv('이번 주 운동', trains.length + '회'));
        body.appendChild(kv('하루 섭취', m.intakeKcal + ' kcal'));
        body.appendChild(kv('하루 단백질', m.proteinG + ' g'));
        body.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: '한 주 만에 생기는 몸 변화는 인바디 오차보다 작습니다. 이번 주는 횟수로 봅니다.' }));

      } else {
        /* 4주는 체지방 변화가 측정 오차를 넘어서는 첫 구간입니다.
           그래서 한 달은 몸으로 말할 수 있습니다. */
        var traj = plan.trajectory || [];
        var from = traj[wk] || traj[0];
        var toI = Math.min(traj.length - 1, wk + 4);
        var to = traj[toI];
        if (from && to) {
          body.appendChild(h('div.card__sub', { style: { marginBottom: '6px' },
            text: (wk + 1) + '주차 → ' + (toI + 1) + '주차' +
                  (plan.milestones && plan.milestones.length ? '' : '') }));
          /* 지표마다 인바디 오차가 다릅니다. 예상 변화가 그 오차 안이면
             "이만큼 빠진다"고 말할 수 없습니다 — 재도 구분이 안 되니까요.
             한 달이면 보통 체지방은 넘고 골격근은 못 넘습니다. */
          var NF = (global.MB_MODES && global.MB_MODES.NOISE) || { weight: 1, smm: 0.6, bfm: 1 };
          var sub = 0;
          sub += deltaRow('체중', from.weightKg, to.weightKg, 'var(--weight)', NF.weight) ? 1 : 0;
          sub += deltaRow('골격근량', from.smmKg, to.smmKg, 'var(--muscle)', NF.smm) ? 1 : 0;
          sub += deltaRow('체지방량', from.bfmKg, to.bfmKg, 'var(--fat)', NF.bfm) ? 1 : 0;
          var wks = toI - wk;
          var trains2 = (sessions.filter(function (x) { return x && !x.rest; }).length) * wks;
          body.appendChild(h('div', { style: { marginTop: '10px' } }, [
            kv('이 기간 운동', trains2 + '회 (' + wks + '주)'),
            kv('하루 단백질', m.proteinG + ' g')
          ]));
          if (sub) {
            body.appendChild(h('div.muted', { style: { marginTop: '8px' },
              text: '별표(*)는 예상 변화가 인바디 오차보다 작다는 뜻입니다. ' +
                    '그 항목은 재도 변했는지 구분되지 않으니 숫자로 확인하려 하지 마세요.' }));
          }
        }
      }

      body.appendChild(h('button.btn.btn--sm.btn--block', {
        text: '전체 플랜 보기', uid: 'P02-B06', uidLabel: '전체 플랜 보기',
        style: { marginTop: '12px' }, onClick: function () { A.go('P07'); } }));
    }

    function kv(k, v) {
      return h('div.kv', [h('span.kv__k', { text: k }), h('span.kv__v', { text: v })]);
    }
    /** 오차 안이면 흐리게 + 별표. 반환값은 "오차 안인가" 입니다. */
    function deltaRow(label, a, b, color, noise) {
      var d = Math.round((b - a) * 10) / 10;
      var underNoise = noise != null && Math.abs(d) < noise;
      body.appendChild(h('div.kv', [
        h('span.kv__k', { text: label }),
        h('span.kv__v', { style: { color: underNoise ? 'var(--text-3)' : color },
          text: UI.sign(d) + 'kg' + (underNoise ? '*' : '') + '  (' + UI.n1(b) + ')' })
      ]));
      return underNoise;
    }

    render();
    return card;
  }

  function sparkBox(label, values, color, unit, uid) {
    var last = values[values.length - 1], first = values[0];
    var diff = last - first;
    return h('div', { uid: uid, uidLabel: label + ' 스파크라인' }, [
      h('div.stat__k', { text: label }),
      UI.sparkline(values, color, 30),
      h('div', { style: { fontSize: '11px', fontWeight: '700', color: color } },
        [UI.sign(diff) + unit])
    ]);
  }

  function progressRow(label, cur, target, unit, pct, mod) {
    return h('div', { style: { marginBottom: '8px' } }, [
      h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '12px',
                          marginBottom: '4px' } }, [
        h('span', { style: { color: 'var(--text-2)', fontWeight: '600' }, text: label }),
        h('span.num', { style: { fontWeight: '700' },
          text: UI.n1(cur) + unit + ' → ' + UI.n1(target) + unit })
      ]),
      h('div.bar' + (mod ? '.bar--' + mod : ''), [
        h('div.bar__fill', { style: { width: clamp(pct) + '%' } })
      ])
    ]);
  }
})(window);
