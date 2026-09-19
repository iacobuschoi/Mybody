/* P07 — 플랜 결과 (요약 / 운동 / 식단) */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;
  var activeTab = 0;

  A.register('P07', {
    title: '플랜', label: '플랜 결과',
    render: function (wrap, ctx) {
      var st = S.get();
      var plan = A.requirePlan(wrap, ctx, 'P07');
      if (!plan) return;
      var goal = st.goal;
      var dday = E.daysUntil(plan.targetDate);

      /* --- C01 헤더: 목표 달성일 --- */
      wrap.appendChild(h('div.card.card--accent', { uid: 'P07-C01', uidLabel: '플랜 헤더 · 목표 달성일' }, [
        h('div.card__head', [
          h('span.badge.badge--accent', { text: '강도 ' + plan.label + ' · ' + plan.title }),
          h('span.badge', { text: plan.strategyLabel })
        ]),
        h('div', { style: { textAlign: 'center', padding: '8px 0' } }, [
          h('div.stat__k', { text: '목표 달성 예정일' }),
          h('div', { style: { fontSize: '28px', fontWeight: '900', letterSpacing: '-.03em' },
                     text: UI.dateK(plan.targetDate) }),
          h('div', { style: { fontSize: '15px', fontWeight: '800', color: 'var(--accent)' },
                     text: dday > 0 ? 'D−' + dday : (dday === 0 ? 'D−DAY' : 'D+' + Math.abs(dday)) }),
          h('div.muted', { text: UI.dateK(plan.startDate) + ' 시작 · ' + UI.weeksToHuman(plan.weeks) })
        ]),
        h('div.muted', { style: { textAlign: 'center' }, text: plan.strategyDesc }),
        h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--sm', { text: '강도 바꾸기', uid: 'P07-B01', uidLabel: '강도 바꾸기',
            onClick: function () { A.go('P06'); } }),
          h('button.btn.btn--sm', { text: '다시 만들기', uid: 'P07-B02', uidLabel: '플랜 재생성',
            onClick: function () { global.MB_MODALS.regeneratePlan(); } }),
          h('button.btn.btn--sm', { text: '내보내기', uid: 'P07-B03', uidLabel: '플랜 내보내기',
            onClick: function () { global.MB_MODALS.exportPlan(plan); } })
        ])
      ]));

      if (plan.capWarning) {
        wrap.appendChild(h('div.note.note--warn', { uid: 'P07-C02', uidLabel: '지속 한계 경고',
          text: '⚠️ ' + plan.capWarning }));
      }
      if (plan.bottleneck) {
        wrap.appendChild(h('div.note', { uid: 'P07-C03', uidLabel: '병목 안내',
          text: '🔎 ' + plan.bottleneck.text }));
      }

      /* --- 탭 --- */
      var tabs = h('div.tabs', { uid: 'P07-C04', uidLabel: '플랜 탭' },
        ['요약', '운동', '식단'].map(function (t, i) {
          return h('button.tabs__item' + (activeTab === i ? '.is-active' : ''), {
            text: t, uid: 'P07-T0' + (i + 1), uidLabel: t + ' 탭',
            onClick: function () { activeTab = i; A.refresh(); }
          });
        }));
      wrap.appendChild(tabs);

      if (activeTab === 0) renderSummary(wrap, plan, goal, st);
      if (activeTab === 1) renderWorkout(wrap, plan);
      if (activeTab === 2) renderDiet(wrap, plan);
    }
  });

  /* ================= 요약 탭 ================= */
  function renderSummary(wrap, plan, goal, st) {
    var m = plan.macros;

    wrap.appendChild(h('div.card', { uid: 'P07-C05', uidLabel: '하루 목표 수치' }, [
      h('div.card__head', [h('div.card__title', { text: '하루 목표' }),
                           h('div.card__sub', { text: '1주차 기준 · 체크인마다 재계산' })]),
      h('div.stats', [
        stat('섭취', m.intakeKcal, 'kcal'),
        stat('단백질', m.proteinG, 'g', 'muscle'),
        stat('탄수화물', m.carbG, 'g'),
        stat('지방', m.fatG, 'g', 'fat')
      ]),
      h('hr.sep'),
      h('div.kv', [h('span.kv__k', { text: '유지 칼로리 (TDEE)' }),
                   h('span.kv__v', { text: m.tdeeKcal + ' kcal' })]),
      h('div.kv', [h('span.kv__k', { text: m.deficitKcal >= 0 ? '하루 적자' : '하루 잉여' }),
                   h('span.kv__v', { text: Math.abs(m.deficitKcal) + ' kcal' })]),
      h('div.kv', [h('span.kv__k', { text: '단백질 밀도' }),
                   h('span.kv__v', { text: m.proteinPerBW + ' g/kg 체중 · ' + m.proteinPerFFM + ' g/kg 제지방' })]),
      h('div.kv', [h('span.kv__k', { text: '열량 비율 (P/C/F)' }),
                   h('span.kv__v', { text: m.pctProtein + ' / ' + m.pctCarb + ' / ' + m.pctFat + ' %' })])
    ]));

    /* 궤적 차트 — 지표마다 스케일이 달라서(체중 86 / 근육 38 / 지방 20)
       한 축에 겹쳐 그리면 선이 전부 눌린다. 지표별로 나눠 그린다. */
    var traj = plan.trajectory;
    var phaseMarks = (plan.phases || []).filter(function (p) { return p.from > 0; })
      .map(function (p) { return { x: p.from, label: (p.name.split(' · ')[1] || p.name) }; });

    var METRICS = [
      { key: 'weightKg', label: '체중',     color: 'var(--weight)', goal: goal.weightKg, uid: 'P07-G01' },
      { key: 'smmKg',    label: '골격근량', color: 'var(--muscle)', goal: goal.smmKg,    uid: 'P07-G02' },
      { key: 'bfmKg',    label: '체지방량', color: 'var(--fat)',    goal: goal.bfmKg,    uid: 'P07-G03' }
    ];

    var chartCard = h('div.card', { uid: 'P07-C06', uidLabel: '예상 궤적 차트' }, [
      h('div.card__head', [h('div.card__title', { text: '예상 궤적' }),
                           h('div.card__sub', { text: '계획을 지켰을 때 · 점선 = 목표' })])
    ]);
    METRICS.forEach(function (met) {
      chartCard.appendChild(h('div', { style: { marginBottom: '14px' } }, [
        h('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
                            fontSize: '12px', marginBottom: '2px' } }, [
          h('span', { style: { fontWeight: '700', color: met.color }, text: met.label }),
          h('span.muted.num', { text: UI.n1(traj[0][met.key]) + ' → ' + UI.n1(met.goal) + ' kg' })
        ]),
        UI.lineChart({
          uid: met.uid, label: met.label + ' 궤적', height: 92, legend: false,
          series: [{ key: met.key, label: met.label, color: met.color, dots: false,
                     points: traj.map(function (t) { return { x: t.week, y: t[met.key] }; }) }],
          goal: [{ y: met.goal, color: met.color, label: '목표' }],
          markers: phaseMarks,
          xTickFmt: function (v) { return Math.round(v) + '주'; }
        })
      ]));
    });
    wrap.appendChild(chartCard);

    /* 단계 타임라인 */
    if (plan.phases && plan.phases.length > 1) {
      wrap.appendChild(h('div.card', { uid: 'P07-C07', uidLabel: '단계 타임라인' }, [
        h('div.card__title', { text: '진행 단계' }),
        h('div', { style: { marginTop: '10px' } }, plan.phases.map(function (p) {
          var wk = (p.weeks != null ? p.weeks : (p.to - p.from));
          return h('div', { style: { marginBottom: '10px' } }, [
            h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '12.5px' } }, [
              h('span', { style: { fontWeight: '700' }, text: p.name }),
              h('span.muted', { text: wk + '주 (' + (p.from + 1) + '~' + p.to + '주차)' })
            ]),
            h('div.bar' + (p.phase === 'cut' ? '.bar--fat' : (p.phase === 'bulk' ? '.bar--muscle' : '')), [
              h('div.bar__fill', { style: { width: Math.round(wk / plan.weeks * 100) + '%' } })
            ])
          ]);
        }))
      ]));
    }

    /* 마일스톤 */
    wrap.appendChild(h('div.card', { uid: 'P07-C08', uidLabel: '4주 단위 마일스톤' }, [
      h('div.card__head', [h('div.card__title', { text: '중간 목표 (4주마다)' }),
                           h('div.card__sub', { text: '여기서 벗어나면 조정' })]),
      h('div', { style: { overflowX: 'auto' } }, [
        h('table.table', { uid: 'P07-L01', uidLabel: '마일스톤 표' }, [
          h('thead', [h('tr', [
            h('th', { text: '시점' }), h('th.num', { text: '체중' }),
            h('th.num', { text: '골격근' }), h('th.num', { text: '체지방' }), h('th.num', { text: '체지방률' })
          ])]),
          h('tbody', plan.milestones.map(function (ms) {
            return h('tr', { style: ms.final ? { fontWeight: '800', color: 'var(--accent)' } : null }, [
              h('td', { text: ms.week + '주 · ' + UI.dateShort(ms.date) }),
              h('td.num', { text: UI.n1(ms.weightKg) }),
              h('td.num', { text: UI.n1(ms.smmKg) }),
              h('td.num', { text: UI.n1(ms.bfmKg) }),
              h('td.num', { text: UI.n1(ms.pbfPct) + '%' })
            ]);
          }))
        ])
      ])
    ]));

    wrap.appendChild(h('button.btn.btn--primary.btn--block', {
      text: '이번 주 체크인 하기', uid: 'P07-B04', uidLabel: '체크인 이동',
      onClick: function () { A.go('P08'); } }));
  }

  /* ================= 운동 탭 ================= */
  function renderWorkout(wrap, plan) {
    var w = plan.workout;

    wrap.appendChild(h('div.card', { uid: 'P07-C09', uidLabel: '운동 개요' }, [
      h('div.card__head', [h('div.card__title', { text: w.splitName }),
                           h('span.badge', { text: '주 ' + w.daysPerWeek + '회' })]),
      h('div.kv', [h('span.kv__k', { text: '세션 길이' }), h('span.kv__v', { text: w.sessionMinutes + '분' })]),
      h('div.kv', [h('span.kv__k', { text: '근육군당 주간 세트' }), h('span.kv__v', { text: w.setsPerMuscle + '세트' })]),
      h('div.kv', [h('span.kv__k', { text: '유산소' }), h('span.kv__v', { text: w.cardioPlan })]),
      h('div.kv', [h('span.kv__k', { text: '디로드' }), h('span.kv__v', { text: w.deloadEvery + '주마다 1주' })]),
      h('div.kv', [h('span.kv__k', { text: '증량 방식' }), h('span.kv__v', { text: '더블 프로그레션' })])
    ]));

    wrap.appendChild(h('div.card', { uid: 'P07-C10', uidLabel: '인바디 부위별 반영' }, [
      h('div.card__head', [h('div.card__title', { text: '내 인바디 반영' }),
                           h('div.card__sub', { text: '부위별 분석 기반' })]),
      h('ul', { style: { margin: '0', paddingLeft: '18px', fontSize: '13px', color: 'var(--text-2)' } },
        w.inbodyBias.map(function (b) { return h('li', { style: { marginBottom: '4px' }, text: b }); }))
    ]));

    var DAYS = ['월', '화', '수', '목', '금', '토', '일'];
    wrap.appendChild(h('div.card', { uid: 'P07-C11', uidLabel: '주간 스플릿' }, [
      h('div.card__title', { text: '주간 스케줄' }),
      h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: '4px',
                          marginTop: '10px' } },
        w.sessions.map(function (s, i) {
          return h('div', {
            style: { textAlign: 'center', padding: '7px 2px', borderRadius: '7px', fontSize: '10px',
                     fontWeight: '700', lineHeight: '1.3',
                     background: s.rest ? 'var(--surface-2)' : 'var(--accent-sub)',
                     color: s.rest ? 'var(--text-3)' : 'var(--accent)' }
          }, [h('div', { text: DAYS[i] }), h('div', { style: { fontSize: '9px', marginTop: '2px' },
                                                      text: s.rest ? '휴식' : s.label })]);
        }))
    ]));

    w.sessions.forEach(function (s, i) {
      if (s.rest) return;
      wrap.appendChild(h('div.card', { uid: 'P07-C12', uidLabel: '운동 세션 카드' }, [
        h('div.card__head', [
          h('div.card__title', { text: DAYS[i] + '요일 · ' + s.label }),
          h('div.card__sub', { text: s.minutes + '분 · ' + s.exercises.length + '종목' })
        ]),
        h('table.table', { uid: 'P07-L02', uidLabel: '종목 리스트' }, [
          h('thead', [h('tr', [h('th', { text: '종목' }), h('th.num', { text: '세트×반복' }),
                               h('th.num', { text: 'RPE' })])]),
          h('tbody', s.exercises.map(function (ex) {
            return h('tr', {
              style: { cursor: 'pointer' },
              onClick: function () { global.MB_MODALS.exerciseDetail(ex); }
            }, [
              h('td', [h('div', { style: { fontWeight: '700' }, text: ex.name }),
                       ex.note ? h('div.muted', { style: { fontSize: '11px' }, text: ex.note }) : null]),
              h('td.num', { text: ex.sets + '×' + ex.reps }),
              h('td.num', { text: ex.rpe })
            ]);
          }))
        ])
      ]));
    });

    wrap.appendChild(h('div.note', { uid: 'P07-C13', uidLabel: '운동 주의',
      text: '통증이 있는 동작은 즉시 멈추고 대체 종목으로 바꾸세요. 종목을 누르면 상세가 열립니다.' }));
  }

  /* ================= 식단 탭 ================= */
  function renderDiet(wrap, plan) {
    var d = plan.diet, m = plan.macros;

    wrap.appendChild(h('div.card', { uid: 'P07-C14', uidLabel: '하루 매크로' }, [
      h('div.card__head', [h('div.card__title', { text: '하루 매크로' }),
                           h('span.badge', { text: d.mealsPerDay + '끼' })]),
      macroBar('단백질', m.proteinG, m.pctProtein, 'var(--muscle)'),
      macroBar('탄수화물', m.carbG, m.pctCarb, 'var(--accent)'),
      macroBar('지방', m.fatG, m.pctFat, 'var(--fat)'),
      h('div.kv', { style: { marginTop: '10px' } },
        [h('span.kv__k', { text: '총 섭취' }), h('span.kv__v', { text: m.intakeKcal + ' kcal' })]),
      h('div.kv', [h('span.kv__k', { text: '끼니당 단백질' }),
                   h('span.kv__v', { text: '약 ' + d.proteinPerMeal + ' g' })]),
      h('div.kv', [h('span.kv__k', { text: '물' }), h('span.kv__v', { text: d.hydrationL + ' L' })])
    ]));

    d.meals.forEach(function (meal, i) {
      wrap.appendChild(h('div.card', { uid: 'P07-C15', uidLabel: '끼니 카드 ' + meal.name }, [
        h('div.card__head', [
          h('div.card__title', { text: meal.name }),
          h('div.card__sub', { text: meal.kcal + ' kcal · 단백질 ' + meal.proteinG + 'g' })
        ]),
        h('div', meal.options.map(function (o) {
          return h('div', { style: { marginBottom: '10px' } }, [
            h('div', { style: { fontSize: '12px', fontWeight: '700', color: 'var(--text-2)',
                                marginBottom: '3px' }, text: o.label }),
            h('ul', { style: { margin: 0, paddingLeft: '17px', fontSize: '12.5px',
                               color: 'var(--text-2)' } },
              o.items.map(function (it) { return h('li', { text: it }); }))
          ]);
        })),
        h('button.btn.btn--sm', { text: '메뉴 교체', uid: 'P07-B05', uidLabel: '메뉴 교체',
          onClick: function () { global.MB_MODALS.swapMeal(meal); } })
      ]));
    });

    wrap.appendChild(h('div.card', { uid: 'P07-C16', uidLabel: '외식 가이드' }, [
      h('div.card__title', { text: '외식 · 편의점' }),
      h('table.table', { uid: 'P07-L03', uidLabel: '외식 리스트' }, [
        h('thead', [h('tr', [h('th', { text: '메뉴' }), h('th.num', { text: 'kcal' }),
                             h('th.num', { text: '단백질' })])]),
        h('tbody', d.eatingOut.map(function (e) {
          return h('tr', [
            h('td', [h('div', { style: { fontWeight: '600' }, text: e.name }),
                     h('div.muted', { style: { fontSize: '11px' }, text: e.tip })]),
            h('td.num', { text: String(e.kcal) }),
            h('td.num', { text: e.p + 'g' })
          ]);
        }))
      ])
    ]));

    wrap.appendChild(h('div.card', { uid: 'P07-C17', uidLabel: '식단 메모' }, [
      h('div.card__title', { text: '기억할 것' }),
      h('ul', { style: { margin: '8px 0 0', paddingLeft: '18px', fontSize: '12.5px',
                         color: 'var(--text-2)' } },
        d.notes.map(function (n) { return h('li', { style: { marginBottom: '5px' }, text: n }); }))
    ]));
  }

  /* --- 조각 --- */
  function stat(label, v, u, mod) {
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n0(v) }), h('span.stat__u', { text: u })])
    ]);
  }
  function macroBar(label, grams, pct, color) {
    return h('div', { style: { marginBottom: '9px' } }, [
      h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '12px',
                          marginBottom: '3px' } }, [
        h('span', { style: { fontWeight: '600', color: 'var(--text-2)' }, text: label }),
        h('span.num', { style: { fontWeight: '700' }, text: grams + 'g · ' + pct + '%' })
      ]),
      h('div.bar', [h('div.bar__fill', { style: { width: pct + '%', background: color } })])
    ]);
  }
})(window);
