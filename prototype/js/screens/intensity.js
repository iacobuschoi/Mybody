/* P06 — 실현 강도 선택 (상/중/하 = 기간 길이) */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var COLORS = { high: '#e0703a', mid: '#4f46e5', low: '#15803d' };

  A.register('P06', {
    title: '실현 강도', label: '실현 강도 선택',
    render: function (wrap, ctx) {
      var st = S.get();
      var scan = A.requireScan(wrap, ctx, 'P06');
      if (!scan) return;
      if (!st.goal) {
        wrap.appendChild(h('div.empty', { uid: 'P06-S01', uidLabel: '목표 없음' }, [
          h('div.empty__ico', { text: '🎯' }),
          h('div.empty__t', { text: '먼저 목표를 정해주세요' }),
          h('button.btn.btn--primary', { text: '목표 설정하기', uid: 'P06-B90',
            uidLabel: '목표 설정하기', onClick: function () { A.go('P05'); } })
        ]));
        return;
      }
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var modeDef = (st.goal.modeId && global.MB_MODES) ? global.MB_MODES.byId(st.goal.modeId) : null;
      var cmp = E.compareLevels(scan, prof, st.goal, todayISO(),
                                st.goal.deadlineWeeks || null, modeDef);
      S.set({ comparison: null }); // 매번 새로 계산 (저장하면 용량만 커짐)

      /* --- C01 목표 요약 --- */
      wrap.appendChild(h('div.card.card--flat', { uid: 'P06-C01', uidLabel: '목표 요약 리본' }, [
        h('div.card__head', [
          h('div.card__title', { text: '목표' }),
          h('button.btn.btn--ghost.btn--sm', { text: '수정', uid: 'P06-B01', uidLabel: '목표 수정',
            onClick: function () { A.go('P05'); } })
        ]),
        h('div.stats', [
          arrow('체중', cmp.current.weightKg, st.goal.weightKg, 'kg'),
          arrow('골격근', cmp.current.smmKg, st.goal.smmKg, 'kg'),
          arrow('체지방', cmp.current.bfmKg, st.goal.bfmKg, 'kg')
        ])
      ]));

      if (cmp.impossible || !cmp.results.length) {
        wrap.appendChild(h('div.note.note--bad', { uid: 'P06-S02', uidLabel: '도달 불가',
          text: cmp.warnings[0] || '이 목표에는 도달할 수 없습니다.' }));
        return;
      }

      /* --- 모드 리본 --- */
      if (modeDef) {
        wrap.appendChild(h('div.card.card--flat', { uid: 'P06-C09', uidLabel: '선택된 모드 리본' }, [
          h('div.card__head', [
            h('div', [
              h('div.card__sub', { text: '모드' }),
              h('div', { style: { fontSize: '16px', fontWeight: '800' }, text: modeDef.nameKo })
            ]),
            h('button.btn.btn--ghost.btn--sm', { text: '바꾸기', uid: 'P06-B02',
              uidLabel: '모드 바꾸기', onClick: function () { A.go('P05'); } })
          ]),
          h('div.muted', { text: modeDef.oneLiner }),
          h('div.muted', { style: { marginTop: '6px' },
            text: '이 모드 안에서 얼마나 빨리 갈지를 아래에서 고릅니다. 모드가 식단 강도 범위와 단백질 하한을 이미 묶어 두었습니다.' })
        ]));
      }

      /* --- 안내: 강도 = 기간 --- */
      wrap.appendChild(h('div.note', { uid: 'P06-C02', uidLabel: '강도 설명' }, [
        h('b', { text: '강도는 곧 기간입니다. ' }),
        '같은 목표라도 얼마나 빨리 갈지에 따라 달성일이 달라집니다. ' +
        '빠를수록 식단이 빡빡하고 근손실 위험이 올라갑니다.'
      ]));

      /* --- 강도 카드 3장 --- */
      cmp.results.forEach(function (r, i) {
        wrap.appendChild(levelCard(r, i, cmp, scan, prof));
      });

      /* --- G01 3안 비교 차트 --- */
      wrap.appendChild(h('div.card', { uid: 'P06-C06', uidLabel: '3안 비교 차트' }, [
        h('div.card__head', [
          h('div.card__title', { text: '체지방 감소 궤적 비교' }),
          h('div.card__sub', { text: '점선 = 목표' })
        ]),
        UI.lineChart({
          uid: 'P06-G01', label: '강도별 체지방 궤적', height: 160,
          series: cmp.results.map(function (r) {
            return {
              key: r.level, label: r.label + ' · ' + r.weeks + '주',
              color: COLORS[r.level], dots: false,
              points: r.sim.trajectory.map(function (t) { return { x: t.week, y: t.bfmKg }; })
            };
          }),
          goal: [{ y: st.goal.bfmKg, color: 'var(--text-3)', label: '목표 ' + UI.n1(st.goal.bfmKg) + 'kg' }],
          xTickFmt: function (v) { return Math.round(v) + '주'; }
        }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '골격근량 궤적은 각 강도 카드의 "자세히"에서 볼 수 있습니다.' })
      ]));

      /* --- 경고 / 병목 --- */
      if (cmp.bottleneckNote) {
        wrap.appendChild(h('div.note.note--warn', { uid: 'P06-C07', uidLabel: '병목 안내' }, [
          h('b', { text: '🔎 병목: ' }), cmp.bottleneckNote.text
        ]));
      }
      cmp.warnings.forEach(function (w, i) {
        wrap.appendChild(h('div.note', { uid: 'P06-C0' + (8 + i), uidLabel: '엔진 경고 ' + (i + 1),
          text: '⚠️ ' + w }));
      });

      wrap.appendChild(h('div.muted', { style: { textAlign: 'center', marginTop: '14px' },
        text: '예상 달성일은 계획을 100% 지켰을 때의 추정입니다. 체크인마다 다시 계산됩니다.' }));
    }
  });

  /* ------------------------------------------------------------------ */
  function levelCard(r, i, cmp, scan, prof) {
    var isRec = cmp.recommended === r.level;
    var n = i + 1;
    var uid = 'P06-C0' + (2 + n);      // C03 / C04 / C05
    var dday = E.daysUntil(r.targetDate);

    var card = h('div.card' + (isRec ? '.card--accent' : ''), {
      uid: uid, uidLabel: '강도 카드 ' + r.label
    });

    card.appendChild(h('div.card__head', [
      h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, [
        h('span', { style: { fontSize: '22px', fontWeight: '900',
          color: COLORS[r.level], letterSpacing: '-.03em' }, text: r.label }),
        h('div', [
          h('div.card__title', { text: r.title }),
          h('div.card__sub', { text: r.blurb })
        ])
      ]),
      isRec ? h('span.badge.badge--accent', { text: '추천' }) : null
    ]));

    /* 주인공: 예상 달성일 */
    card.appendChild(h('div', {
      style: { background: 'var(--surface-2)', borderRadius: '10px', padding: '12px',
               margin: '4px 0 12px', textAlign: 'center' }
    }, [
      h('div.stat__k', { text: '목표 달성 예정일' }),
      h('div', { style: { fontSize: '24px', fontWeight: '900', letterSpacing: '-.02em',
                          color: COLORS[r.level] }, text: UI.dateK(r.targetDate) }),
      h('div.muted', { text: UI.weeksToHuman(r.weeks) + (dday > 0 ? ' · D−' + dday : '') })
    ]));

    card.appendChild(h('div.kv', [h('span.kv__k', { text: '전략' }),
      h('span.kv__v', { text: r.sim.strategyLabel })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '주당 체중 변화' }),
      h('span.kv__v', { text: UI.sign(r.weeklyRateKg, 2) + 'kg (' + UI.n2(r.weeklyRatePct) + '%)' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '하루 섭취' }),
      h('span.kv__v', { text: r.macros.intakeKcal + ' kcal' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '단백질 / 탄수 / 지방' }),
      h('span.kv__v', { text: r.macros.proteinG + ' / ' + r.macros.carbG + ' / ' + r.macros.fatG + ' g' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '운동' }),
      h('span.kv__v', { text: '주 ' + r.daysPerWeek + '회 · ' + r.sessionMin + '분' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '유산소' }),
      h('span.kv__v', { text: '주 ' + r.cardioMin + '분' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '난이도' }),
      h('span.kv__v', { text: r.difficultyLabel })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '외식/치팅' }),
      h('span.kv__v', { text: r.cheatMeals === 0 ? '사실상 불가' : '주 ' + r.cheatMeals + '회' })]));
    card.appendChild(h('div.kv', [h('span.kv__k', { text: '근손실 위험' }),
      h('span.kv__v', { text: r.muscleLossRisk })]));

    if (r.feasibility.verdict !== 'ok') {
      card.appendChild(h('div.note.note--' +
        (r.feasibility.verdict === 'tough' ? 'warn' : 'bad'),
        { style: { marginTop: '10px' }, text: r.feasibility.badge + ' ' + r.feasibility.message }));
    }
    if (r.capWarning) {
      card.appendChild(h('div.note.note--warn', { style: { marginTop: '10px' }, text: '⚠️ ' + r.capWarning }));
    }

    card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
      h('button.btn', { text: '자세히', uid: 'P06-B' + (10 + n) + '', uidLabel: r.label + ' 자세히',
        onClick: function () { global.MB_MODALS.levelDetail(r, cmp); } }),
      h('button.btn.btn--primary', { text: '이 강도로 시작',
        uid: 'P06-B' + (20 + n), uidLabel: r.label + ' 선택',
        onClick: function () {
          if (r.feasibility.verdict === 'blocked') { global.MB_MODALS.unsafeGoal(cmp.goalInfo, 8); return; }
          if (r.difficulty >= 3) {
            global.MB_MODALS.hardIntensityWarn(r, function () { choose(r, cmp, scan, prof); });
          } else { choose(r, cmp, scan, prof); }
        } })
    ]));
    return card;
  }

  function choose(r, cmp, scan, prof) {
    var plan = E.buildPlan(cmp, r.level, scan, prof);
    S.set({ plan: plan });
    global.MB_UID.toast('플랜이 만들어졌습니다 · 목표일 ' + UI.dateK(plan.targetDate));
    A.go('P07');
  }

  function arrow(label, from, to, u) {
    return h('div.stat', [
      h('div.stat__k', { text: label }),
      h('div', { style: { fontSize: '14px', fontWeight: '700' } },
        [UI.n1(from) + ' → ', h('span', { style: { color: 'var(--accent)' }, text: UI.n1(to) + u })])
    ]);
  }

  function todayISO() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
           String(d.getDate()).padStart(2, '0');
  }
})(window);
