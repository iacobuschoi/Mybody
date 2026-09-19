/* P09 — 진행 추적 / 추이 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 화면을 떠났다 와도 보던 탭/기간은 유지한다 */
  var activeTab = 0;      // 0 전체 · 1 체중 · 2 골격근량 · 3 체지방량 · 4 체지방률
  /* 기본값이 '전체'면 계획(수십 주)이 x축을 다 먹어 측정 3건이 왼쪽 끝에 뭉친다.
     '12주'가 실측과 계획을 반반으로 보여주는 가장 읽기 쉬운 창이다. */
  var period = '12';      // '4' | '12' | 'all'

  var SEGMENTS = [
    { key: 'rightArm', label: '오른팔' },
    { key: 'leftArm',  label: '왼팔' },
    { key: 'trunk',    label: '몸통' },
    { key: 'rightLeg', label: '오른다리' },
    { key: 'leftLeg',  label: '왼다리' }
  ];
  /* 인바디 부위별 판정 등급 — 순위를 매겨야 "좋아졌다/나빠졌다"를 말할 수 있다 */
  var GRADE_RANK = { '표준이하': 0, '표준': 1, '표준이상': 2 };

  A.register('P09', {
    title: '추이', label: '진행 추적',
    render: function (wrap, ctx) {
      var st = S.get();
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var scans = S.sortedScans();

      /* --- S01 측정이 2건 미만이면 추이 자체가 성립하지 않는다 --- */
      if (scans.length < 2) { renderEmpty(wrap, scans.length); return; }

      var goal = st.goal || null;
      var plan = st.plan || null;

      /* 측정값 → 파생값 + 첫 측정 기준 경과 주차 */
      var firstDate = dayOf(scans[0].measuredAt);
      var pts = scans.map(function (s) {
        var d = E.derive(s, prof);
        d.measuredAt = s.measuredAt;
        d.scan = s;
        d.week = weeksBetween(firstDate, dayOf(s.measuredAt));
        return d;
      });
      var first = pts[0];
      var last = pts[pts.length - 1];

      var METRICS = [
        { key: 'weightKg', label: '체중',     short: '체중',     unit: 'kg', color: 'var(--weight)',
          goal: goal ? goal.weightKg : null },
        { key: 'smmKg',    label: '골격근량', short: '골격근',   unit: 'kg', color: 'var(--muscle)',
          goal: goal ? goal.smmKg : null, higherIsBetter: true },
        { key: 'bfmKg',    label: '체지방량', short: '체지방',   unit: 'kg', color: 'var(--fat)',
          goal: goal ? goal.bfmKg : null },
        { key: 'pbfPct',   label: '체지방률', short: '체지방률', unit: '%',  color: 'var(--fat)',
          goal: goal ? (goal.bfmKg / goal.weightKg * 100) : null }
      ];
      var isAll = activeTab === 0;
      var met = METRICS[activeTab - 1] || METRICS[0];

      /* --- C01 지표 탭 (0번은 세 지표를 한 번에) --- */
      var TAB_LABELS = ['전체'].concat(METRICS.map(function (m) { return m.short; }));
      wrap.appendChild(h('div.tabs', { uid: 'P09-C01', uidLabel: '지표 탭' },
        TAB_LABELS.map(function (label, i) {
          return h('button.tabs__item' + (activeTab === i ? '.is-active' : ''), {
            text: label, uid: 'P09-T0' + (i + 1), uidLabel: label + ' 탭',
            onClick: function () { activeTab = i; A.refresh(); }
          });
        })));

      /* --- C02 기간 필터 --- */
      wrap.appendChild(h('div.card.card--flat', { uid: 'P09-C02', uidLabel: '기간 필터' }, [
        h('div.card__head', [
          h('div.card__title', { text: '기간' }),
          h('div.card__sub', { text: '차트에 보이는 구간만 바뀝니다' })
        ]),
        h('div.chips', [
          periodChip('P09-B01', '4주', '4'),
          periodChip('P09-B02', '12주', '12'),
          periodChip('P09-B03', '전체', 'all')
        ]),
        h('div.muted', { style: { marginTop: '8px' }, text: periodHint(plan) })
      ]));

      /* --- C06 메인 차트 --- */
      if (isAll) {
        wrap.appendChild(combinedCard(METRICS, pts, firstDate));
      } else {
        wrap.appendChild(chartCard(met));
      }

      /* --- C03 델타 표 --- */
      wrap.appendChild(deltaCard(METRICS));

      /* --- C04 부위별 비교 --- */
      var segCard = segmentalCard(scans);
      if (segCard) wrap.appendChild(segCard);

      /* --- C05 예측 재계산 배너 --- */
      wrap.appendChild(forecastCard());

      /* ====================================================================
       * C06 — 차트
       * ================================================================= */
      /* --- 전체 보기: 시작 대비 변화율을 한 축에 겹친다 ---------------------
       * 단위가 서로 달라(체중 86 / 근육 38 / 지방 20 kg) 실제값을 한 축에 그리면
       * 선이 전부 눌린다. 시작값 대비 %변화로 바꾸면 근육은 위로 지방은 아래로
       * 갈라지는 모양이 그대로 보인다 — 리컴프가 되고 있는지가 한 장에 드러난다. */
      function combinedCard(metrics, points, baseDate) {
        var card = h('div.card', { uid: 'P09-C07', uidLabel: '전체 지표 한눈에' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '세 지표 한 번에' }),
          h('div.card__sub', { text: '시작 대비 변화율' })
        ]));

        var three = metrics.slice(0, 3);          // 체중 · 골격근량 · 체지방량
        var b0 = points[0];
        var series = three.map(function (m) {
          var b = b0[m.key];
          return {
            key: m.key, label: m.short, color: m.color, dots: points.length <= 12,
            points: points.map(function (p) {
              return { x: p.week, y: b ? ((p[m.key] - b) / b * 100) : 0 };
            })
          };
        });
        card.appendChild(UI.lineChart({
          uid: 'P09-G05', label: '시작 대비 변화율', height: 168,
          series: series,
          goal: [{ y: 0, color: 'var(--text-3)', label: '시작' }],
          xTickFmt: function (v) { return UI.dateShort(E.addWeeks(baseDate, v)); }
        }));

        var lastP = points[points.length - 1];
        card.appendChild(h('div.stats', { style: { marginTop: '12px' } },
          three.map(function (m) {
            var d = lastP[m.key] - b0[m.key];
            var good = m.higherIsBetter ? d > 0 : d < 0;
            return h('div.stat', [
              h('div.stat__k', { text: m.short }),
              h('div', [h('span.stat__v', { style: { color: m.color }, text: UI.n1(lastP[m.key]) }),
                        h('span.stat__u', { text: m.unit })]),
              h('div.stat__d', {
                style: { color: Math.abs(d) < 0.05 ? 'var(--text-3)'
                              : (good ? 'var(--ok)' : 'var(--bad)') },
                text: UI.sign(d) + m.unit })
            ]);
          })));

        var dS = lastP.smmKg - b0.smmKg, dF = lastP.bfmKg - b0.bfmKg;
        var N = global.MB_MODES ? global.MB_MODES.NOISE : { smm: 0.6, bfm: 1.0 };
        var v;
        if (dS > N.smm && dF < -N.bfm) {
          v = { cls: '--ok', text: '근육은 늘고 지방은 줄었습니다. 체중계 숫자만 봤다면 놓쳤을 변화입니다.' };
        } else if (dF < -N.bfm && Math.abs(dS) <= N.smm) {
          v = { cls: '', text: '지방이 줄고 근육은 지켜졌습니다. 감량 구간에서는 이게 성공입니다.' };
        } else if (dS > N.smm && dF > N.bfm) {
          v = { cls: '--warn', text: '근육과 지방이 함께 늘었습니다. 증량 중이라면 정상이고, 아니라면 섭취를 줄일 때입니다.' };
        } else if (dS < -N.smm) {
          v = { cls: '--bad', text: '근육이 줄었습니다. 적자가 깊거나 단백질이 모자란 신호입니다.' };
        } else {
          v = { cls: '', text: '아직 측정 오차를 넘는 변화가 없습니다. 판정하려면 4주 이상 간격이 필요합니다.' };
        }
        card.appendChild(h('div.note' + (v.cls ? '.note' + v.cls : ''),
          { style: { marginTop: '12px' }, text: v.text }));

        card.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: '지표마다 단위가 달라 실제값을 한 축에 겹치면 선이 눌립니다. ' +
                '그래서 시작값 대비 몇 % 움직였는지로 바꿔 겹쳤습니다. ' +
                '실제 값은 위 숫자와 각 지표 탭에서 봅니다.' }));
        return card;
      }

      function chartCard(m) {
        var latestX = last.week;

        /* 계획 궤적을 첫 측정 기준 x축으로 옮긴다 */
        var planPts = [];
        if (plan && plan.trajectory && plan.trajectory.length) {
          var planOffset = weeksBetween(firstDate, dayOf(plan.startDate));
          planPts = plan.trajectory.map(function (t) {
            return { x: planOffset + t.week, y: t[m.key] };
          });
        }
        var planEndX = planPts.length ? planPts[planPts.length - 1].x : latestX;

        /* 창(window) 잡기 — 4주·12주는 "지금"을 가운데 두고 앞뒤로 본다 */
        var xFrom, xTo;
        if (period === 'all') {
          xFrom = 0;
          xTo = Math.max(latestX, planEndX);
        } else {
          var span = parseFloat(period);
          xFrom = Math.max(0, latestX - span);
          xTo = Math.min(Math.max(latestX, planEndX), latestX + span);
        }
        if (xTo <= xFrom) xTo = xFrom + 1;

        function inWin(p) { return p.x >= xFrom - 0.01 && p.x <= xTo + 0.01; }

        var measured = pts.map(function (p) { return { x: p.week, y: p[m.key] }; }).filter(inWin);
        var planned = planPts.filter(inWin);

        var series = [{ key: 'actual', label: '실측', color: m.color, points: measured }];
        if (planned.length >= 2) {
          series.push({ key: 'plan', label: '계획', color: 'var(--accent)',
                        dashed: true, dots: false, points: planned });
        }

        var todayX = weeksBetween(firstDate, dayOf(todayISO()));
        var markers = [];
        if (todayX > xFrom + 0.3 && todayX < xTo - 0.3 && Math.abs(todayX - latestX) > 0.5) {
          markers.push({ x: todayX, label: '오늘' });
        }

        var card = h('div.card', { uid: 'P09-C06', uidLabel: '추이 차트 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: m.label }),
            h('div.card__sub', {
              text: UI.n1(first[m.key]) + ' → ' + UI.n1(last[m.key]) + m.unit +
                    ' (' + UI.sign(last[m.key] - first[m.key]) + m.unit + ')'
            })
          ]),
          UI.lineChart({
            uid: 'P09-G01', label: m.label + ' 추이 차트', height: 168,
            series: series,
            goal: m.goal != null ? [{ y: m.goal, color: 'var(--text-3)', label: '목표' }] : [],
            markers: markers,
            xTickFmt: function (v) { return UI.dateShort(E.addWeeks(firstDate, v)); }
          })
        ]);

        if (measured.length < 2) {
          card.appendChild(h('div.muted', { style: { marginTop: '6px' },
            text: '이 기간에 측정이 ' + measured.length + '건뿐입니다. 기간을 넓히면 선이 보입니다.' }));
        }
        if (!plan) {
          card.appendChild(h('div.muted', { style: { marginTop: '6px' },
            text: '계획(점선)은 플랜을 만들면 함께 그려집니다.' }));
        }

        card.appendChild(recompNote());
        return card;
      }

      /* 리컴프 서술 — 체중계만 보면 놓치는 변화를 문장으로 말해 준다 */
      function recompNote() {
        var weeks = Math.max(1, Math.round(last.week));
        var dW = last.weightKg - first.weightKg;
        var dF = last.bfmKg - first.bfmKg;
        var dS = last.smmKg - first.smmKg;
        var head = weeks + '주 동안 체중 ' + UI.sign(dW) + 'kg · 체지방 ' + UI.sign(dF) +
                   'kg · 골격근 ' + UI.sign(dS) + 'kg';
        var cls, tail;
        if (dF < -0.3 && dS > 0.3) {
          cls = '.note--ok';
          tail = '지방이 빠지는 동안 근육은 늘었습니다. 체중계 숫자만 봤다면 놓쳤을 변화입니다.';
        } else if (dF < -0.3 && dS < -0.3) {
          cls = '.note--warn';
          tail = '지방과 함께 근육도 줄었습니다. 단백질 섭취량과 주간 세트 수부터 점검하세요.';
        } else if (dF > 0.3 && dS > 0.3) {
          cls = '.note--warn';
          tail = '근육은 늘었지만 지방도 같이 늘었습니다. 잉여 칼로리가 필요 이상입니다.';
        } else {
          cls = '';
          tail = '아직 방향을 단정할 만한 변화는 아닙니다. 측정 간격을 2~4주로 유지하세요.';
        }
        return h('div.note' + cls, { style: { marginTop: '10px' } },
          [h('b', { text: head }), h('div', { style: { marginTop: '4px' }, text: tail })]);
      }

      /* ====================================================================
       * C03 — 델타 표
       * ================================================================= */
      function deltaCard(metrics) {
        var card = h('div.card', { uid: 'P09-C03', uidLabel: '지표별 델타 표' }, [
          h('div.card__head', [
            h('div.card__title', { text: '시작 대비 변화' }),
            h('div.card__sub', { text: '기준: 첫 측정 ' + UI.dateK(first.measuredAt) })
          ])
        ]);

        card.appendChild(h('div', { style: { overflowX: 'auto' } }, [
          h('table.table', { uid: 'P09-L01', uidLabel: '델타 표' }, [
            h('thead', [h('tr', [
              h('th', { text: '지표' }),
              h('th.num', { text: '시작' }),
              h('th.num', { text: '현재' }),
              h('th.num', { text: '목표' }),
              h('th.num', { text: '남은' }),
              h('th.num', { text: '달성' })
            ])]),
            h('tbody', metrics.map(function (m) {
              var startV = first[m.key], curV = last[m.key], goalV = m.goal;
              var remain = goalV != null ? goalV - curV : null;
              var pct = achievedPct(startV, curV, goalV);
              var moved = curV - startV;
              return h('tr', [
                h('td', [
                  h('div', { style: { fontWeight: '700' }, text: m.short }),
                  h('div.muted', { style: { fontSize: '11px' }, text: m.unit })
                ]),
                h('td.num.muted', { text: UI.n1(startV) }),
                h('td.num', { style: { fontWeight: '800' } }, [
                  h('div', { text: UI.n1(curV) }),
                  h('div', { style: { fontSize: '11px', fontWeight: '700',
                                      color: deltaColor(m, moved) }, text: UI.sign(moved) })
                ]),
                h('td.num', { text: goalV != null ? UI.n1(goalV) : '—' }),
                h('td.num', { text: remain != null ? UI.sign(remain) : '—' }),
                h('td.num', {
                  style: { fontWeight: '800',
                           color: pct == null ? 'var(--text-3)'
                                 : (pct >= 100 ? 'var(--accent)' : 'var(--text)') },
                  text: pct == null ? '—' : UI.n0(pct) + '%'
                })
              ]);
            }))
          ])
        ]));

        if (!goal) {
          card.appendChild(h('div.note', { style: { marginTop: '10px' } }, [
            '목표가 없어 목표·남은 양·달성률은 비워 둡니다.'
          ]));
        }
        card.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: '달성률 = (현재 − 시작) ÷ (목표 − 시작). 0~100%로 자릅니다.' }));
        return card;
      }

      /* ====================================================================
       * C04 — 부위별 비교
       * ================================================================= */
      function segmentalCard(allScans) {
        var withSeg = allScans.filter(function (s) { return s.segmentalLean || s.segmentalFat; });
        if (!withSeg.length) return null;   // 부위별 데이터가 아예 없으면 카드를 내지 않는다

        var a = withSeg[0], b = withSeg[withSeg.length - 1];
        var single = withSeg.length < 2;

        var card = h('div.card', { uid: 'P09-C04', uidLabel: '부위별 비교' }, [
          h('div.card__head', [
            h('div.card__title', { text: '부위별 판정' }),
            h('div.card__sub', { text: single
              ? UI.dateShort(b.measuredAt) + ' 1건'
              : UI.dateShort(a.measuredAt) + ' → ' + UI.dateShort(b.measuredAt) })
          ])
        ]);

        card.appendChild(h('div', { style: { overflowX: 'auto' } }, [
          h('table.table', { uid: 'P09-L02', uidLabel: '부위별 비교 표' }, [
            h('thead', [h('tr', [
              h('th', { text: '부위' }), h('th', { text: '근육' }), h('th', { text: '지방' })
            ])]),
            h('tbody', SEGMENTS.map(function (seg) {
              return h('tr', [
                h('td', { style: { fontWeight: '700' }, text: seg.label }),
                gradeCell(pick(a.segmentalLean, seg.key), pick(b.segmentalLean, seg.key), single, true),
                gradeCell(pick(a.segmentalFat, seg.key), pick(b.segmentalFat, seg.key), single, false)
              ]);
            }))
          ])
        ]));

        card.appendChild(h('div.muted', { style: { marginTop: '8px' }, text: single
          ? '부위별 데이터가 있는 측정이 1건뿐이라 비교할 수 없습니다. 다음 측정부터 변화가 표시됩니다.'
          : '인바디의 부위별 판정(표준이하 · 표준 · 표준이상)을 그대로 비교한 것입니다. 등급이라 소수점 변화는 보이지 않습니다.' }));
        return card;
      }

      function gradeCell(from, to, single, higherIsBetter) {
        if (to == null && from == null) return h('td.muted', { text: '—' });
        if (single || from == null || to == null || from === to) {
          return h('td.muted', { text: (to != null ? to : from) });
        }
        var rf = GRADE_RANK[from], rt = GRADE_RANK[to];
        var better = (rf == null || rt == null) ? null
          : (higherIsBetter ? rt > rf : rt < rf);
        var color = better == null ? 'var(--text-2)'
          : (better ? 'var(--muscle)' : 'var(--fat)');
        return h('td', { style: { fontWeight: '700', color: color },
                         text: from + ' → ' + to });
      }

      /* ====================================================================
       * C05 — 예측 재계산 배너
       * ================================================================= */
      function forecastCard() {
        if (!goal) {
          return h('div.card', { uid: 'P09-C05', uidLabel: '예측 재계산 배너' }, [
            h('div.card__title', { text: '예측 재계산' }),
            h('div.muted', { style: { margin: '6px 0 10px' },
              text: '목표가 없어 비교할 예정일이 없습니다. 목표를 정하면 현재 측정값으로 도달 시점을 다시 계산해 드립니다.' }),
            h('button.btn.btn--primary.btn--block', { text: '목표 다시 보기',
              uid: 'P09-B05', uidLabel: '목표 다시 보기',
              onClick: function () { A.go('P05'); } })
          ]);
        }
        if (!plan) {
          return h('div.card', { uid: 'P09-C05', uidLabel: '예측 재계산 배너' }, [
            h('div.card__title', { text: '예측 재계산' }),
            h('div.muted', { style: { margin: '6px 0 10px' },
              text: '목표는 있는데 플랜이 없습니다. 강도를 고르면 예정일이 생기고, 그때부터 실제 진행과 비교할 수 있습니다.' }),
            h('button.btn.btn--primary.btn--block', { text: '플랜 만들기',
              uid: 'P09-B07', uidLabel: '플랜 만들기',
              onClick: function () { A.go('P06'); } })
          ]);
        }

        /* 최신 측정값 + 저장된 목표로 같은 강도를 다시 시뮬레이션한다 */
        var cmp = null, failed = false;
        try {
          cmp = E.compareLevels(last.scan, prof, goal, todayISO(), goal.deadlineWeeks || null);
        } catch (e) { failed = true; }

        var r = null;
        if (cmp && cmp.results && cmp.results.length) {
          r = cmp.results.filter(function (x) { return x.level === plan.level; })[0] || cmp.results[0];
        }

        var card = h('div.card.card--accent', { uid: 'P09-C05', uidLabel: '예측 재계산 배너' }, [
          h('div.card__head', [
            h('div.card__title', { text: '지금 다시 계산하면' }),
            h('span.badge', { text: '강도 ' + plan.label + ' 기준' })
          ])
        ]);

        if (failed || !r || (cmp && cmp.impossible)) {
          card.appendChild(h('div.note.note--bad', { style: { marginTop: '4px' } }, [
            h('b', { text: '재계산 실패' }),
            h('div', { style: { marginTop: '4px' },
              text: '현재 측정값에서는 이 목표에 도달하는 계획을 찾지 못했습니다. 목표치가 너무 멀거나 서로 안 맞는 상태일 수 있습니다.' })
          ]));
          card.appendChild(h('button.btn.btn--block', { text: '목표 다시 보기',
            uid: 'P09-B05', uidLabel: '목표 다시 보기', style: { marginTop: '10px' },
            onClick: function () { A.go('P05'); } }));
          return card;
        }

        var diffDays = E.daysUntil(plan.targetDate, r.targetDate); // + = 재계산이 더 빠름
        var diffWeeks = Math.round(Math.abs(diffDays) / 7);
        var cls, headline;
        if (Math.abs(diffDays) < 4) {
          cls = ''; headline = '예정과 거의 같습니다.';
        } else if (diffDays > 0) {
          cls = '.note--ok';
          headline = diffWeeks >= 1
            ? '예정보다 ' + diffWeeks + '주 빠릅니다.'
            : '예정보다 ' + Math.abs(diffDays) + '일 빠릅니다.';
        } else {
          cls = '.note--warn';
          headline = diffWeeks >= 1
            ? '목표일보다 ' + diffWeeks + '주 늦습니다.'
            : '목표일보다 ' + Math.abs(diffDays) + '일 늦습니다.';
        }

        card.appendChild(h('div.note' + cls, { style: { marginTop: '4px' } }, [
          h('b', { text: headline }),
          h('div', { style: { marginTop: '4px' },
            text: '원래 예정일 ' + UI.dateK(plan.targetDate) + ' · 재계산 ' + UI.dateK(r.targetDate) })
        ]));

        card.appendChild(h('div.kv', [
          h('span.kv__k', { text: '남은 기간 (재계산)' }),
          h('span.kv__v', { text: UI.weeksToHuman(r.weeks) })
        ]));

        var rate = observedRate();
        if (rate) {
          card.appendChild(h('div.kv', [
            h('span.kv__k', { text: '최근 구간 실제 속도' }),
            h('span.kv__v', { text: '주당 체중 ' + UI.sign(rate.weight, 2) + 'kg · 체지방 ' +
                                    UI.sign(rate.fat, 2) + 'kg · 골격근 ' + UI.sign(rate.smm, 2) + 'kg' })
          ]));
        }
        card.appendChild(h('div.kv', [
          h('span.kv__k', { text: '계획상 주당 속도' }),
          h('span.kv__v', { text: '체중 ' + UI.sign(r.weeklyRateKg, 2) + 'kg · 체지방 ' +
                                  UI.sign(r.weeklyFatKg, 2) + 'kg' })
        ]));

        card.appendChild(h('div.muted', { style: { marginTop: '10px' },
          text: '재계산은 "지금 몸 상태에서 같은 강도로 다시 시작하면 언제 도달하는가"입니다. ' +
                '지난 몇 주의 진행 속도를 그대로 연장한 값이 아니라, 남은 거리 기준입니다.' }));

        card.appendChild(h('button.btn.btn--primary.btn--block', {
          text: '계획 재조정', uid: 'P09-B04', uidLabel: '계획 재조정',
          style: { marginTop: '10px' },
          onClick: function () { global.MB_MODALS.regeneratePlan(); }
        }));
        return card;
      }

      /* 마지막 두 측정 사이의 실제 변화 속도 (주당) */
      function observedRate() {
        if (pts.length < 2) return null;
        var p0 = pts[pts.length - 2], p1 = pts[pts.length - 1];
        var dw = p1.week - p0.week;
        if (!(dw > 0.2)) return null;
        return {
          weight: (p1.weightKg - p0.weightKg) / dw,
          fat: (p1.bfmKg - p0.bfmKg) / dw,
          smm: (p1.smmKg - p0.smmKg) / dw
        };
      }

      function periodChip(uid, label, value) {
        return h('button.chip' + (period === value ? '.is-on' : ''), {
          text: label, uid: uid, uidLabel: label + ' 기간',
          onClick: function () { period = value; A.refresh(); }
        });
      }
    }
  });

  /* ======================================================================
   * S01 — 빈 상태
   * =================================================================== */
  function renderEmpty(wrap, count) {
    wrap.appendChild(h('div.empty', { uid: 'P09-S01', uidLabel: '추이 불가 빈 상태' }, [
      h('div.empty__ico', { text: '📈' }),
      h('div.empty__t', { text: count === 0
        ? '아직 측정 기록이 없습니다'
        : '두 번째 측정부터 추이가 보입니다' }),
      h('div.empty__d', { text: count === 0
        ? '인바디 결과지를 한 번 올리면 여기서부터 기록이 쌓입니다.'
        : '측정이 1건이라 아직 선이 그려지지 않습니다. 보통 2~4주 간격으로 다시 재면 변화가 나타납니다.' }),
      h('button.btn.btn--primary', { text: '인바디 올리기',
        uid: 'P09-B06', uidLabel: '인바디 올리기',
        onClick: function () { A.go('P03'); } })
    ]));
  }

  /* ======================================================================
   * 조각
   * =================================================================== */
  function periodHint(plan) {
    if (period === 'all') {
      return plan
        ? '첫 측정부터 계획 종료일까지 전부 봅니다.'
        : '첫 측정부터 마지막 측정까지 전부 봅니다.';
    }
    return '최근 측정을 가운데 두고 앞뒤 ' + period + '주를 봅니다. 점선(계획)과 실제 위치를 바로 겹쳐 볼 수 있습니다.';
  }

  function achievedPct(startV, curV, goalV) {
    if (goalV == null) return null;
    var span = goalV - startV;
    if (Math.abs(span) < 0.05) return null;   // 시작값이 이미 목표 — 달성률이 정의되지 않는다
    var p = (curV - startV) / span * 100;
    return Math.max(0, Math.min(100, p));
  }

  function deltaColor(m, moved) {
    if (Math.abs(moved) < 0.05) return 'var(--text-3)';
    var good = m.higherIsBetter ? moved > 0 : moved < 0;
    if (m.key === 'weightKg') return 'var(--text-2)';   // 체중은 방향만으로 좋다/나쁘다를 말할 수 없다
    return good ? 'var(--muscle)' : 'var(--fat)';
  }

  function pick(obj, key) {
    if (!obj) return null;
    return obj[key] != null ? obj[key] : null;
  }

  function dayOf(iso) {
    var d = new Date(String(iso).length <= 10 ? iso + 'T00:00:00' : iso);
    return new Date(d.getFullYear(), d.getMonth(), d.getDate());
  }
  function weeksBetween(a, b) { return (b - a) / (7 * 86400000); }

  function todayISO() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
           String(d.getDate()).padStart(2, '0');
  }
})(window);
