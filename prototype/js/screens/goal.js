/* P05 — 목표 설정 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  A.register('P05', {
    title: '목표 설정', label: '목표 설정',
    render: function (wrap, ctx) {
      var st = S.get();
      var isEdit = !!st.goal;
      this.title = isEdit ? '목표 변경' : '목표 설정';
      var baseGoal = st.goal ? JSON.parse(JSON.stringify(st.goal)) : null;
      var scan = A.requireScan(wrap, ctx, 'P05');
      if (!scan) return;
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var cur = E.derive(scan, prof);

      // 목표 초기값: 저장된 값 → 없으면 인바디 적정체중 기반 추천
      var g = st.goal ? Object.assign({}, st.goal) : recommendGoal(cur, scan, prof);
      var linked = true;        // 체중 = 제지방 + 체지방 연동
      var deadlineWeeks = st.goal && st.goal.deadlineWeeks ? st.goal.deadlineWeeks : null;
      var manualModeId = st.goal && st.goal.manualModeId ? st.goal.manualModeId : null;
      var showAllModes = false;

      var body = h('div');
      wrap.appendChild(body);
      draw();

      function draw() {
        UI.clear(body);

        /* --- C01 현재값 리본 --- */
        body.appendChild(h('div.card.card--flat', { uid: 'P05-C01', uidLabel: '현재값 리본' }, [
          h('div.card__head', [
            h('div.card__title', { text: '현재 (' + UI.dateK(scan.measuredAt) + ')' })
          ]),
          h('div.stats', [
            mini('체중', cur.weightKg, 'kg'),
            mini('골격근량', cur.smmKg, 'kg'),
            mini('체지방량', cur.bfmKg, 'kg'),
            mini('체지방률', cur.pbfPct, '%')
          ])
        ]));

        /* --- 입력 --- */
        var form = h('div.card', { uid: 'P05-C02', uidLabel: '목표 입력 폼' });

        form.appendChild(numField('P05-F01', '목표 체중', g.weightKg, 'kg', 40, 200, 0.1,
          function (v) { g.weightKg = v; if (linked) solveFromWeight(); draw(); },
          linked ? '골격근량·체지방량에서 자동 계산됩니다' : null, linked));

        form.appendChild(numField('P05-F02', '목표 골격근량 (SMM)', g.smmKg, 'kg', 10, 70, 0.1,
          function (v) { g.smmKg = v; if (linked) recalcWeight(); draw(); },
          '인바디의 "골격근량" 항목입니다 (근력이 아니라 근육량)'));

        form.appendChild(numField('P05-F03', '목표 체지방량', g.bfmKg, 'kg', 2, 80, 0.1,
          function (v) { g.bfmKg = v; if (linked) recalcWeight(); draw(); }));

        var targetPbf = g.bfmKg / g.weightKg * 100;
        form.appendChild(numField('P05-F04', '목표 체지방률', Math.round(targetPbf * 10) / 10, '%', 4, 50, 0.1,
          function (v) {
            // 체지방률을 바꾸면 골격근량은 유지한 채 체지방량·체중을 다시 푼다
            var ffm = g.smmKg / cur.smmToFfm;
            g.weightKg = Math.round(ffm / (1 - v / 100) * 10) / 10;
            g.bfmKg = Math.round((g.weightKg - ffm) * 10) / 10;
            draw();
          }, '체중·체지방량과 연동됩니다'));

        form.appendChild(h('div.field', [
          h('div.field__label', { text: '체중 자동 연동' }),
          h('label.radio-card' + (linked ? '.is-on' : ''), {
            uid: 'P05-B01', uidLabel: '체중 연동 잠금 토글',
            onClick: function () { linked = !linked; if (linked) recalcWeight(); draw(); }
          }, [
            h('span', { text: linked ? '🔒' : '🔓' }),
            h('div', [
              h('div.radio-card__t', { text: linked ? '연동 켜짐' : '연동 꺼짐' }),
              h('div.radio-card__d', { text: linked
                ? '골격근량·체지방량을 바꾸면 목표 체중이 자동으로 맞춰집니다'
                : '세 값을 따로 입력합니다 (서로 안 맞을 수 있습니다)' })
            ])
          ])
        ]));

        /* --- F05 목표 시점 (선택) --- */
        form.appendChild(h('div.field', [
          h('div.field__label', { text: '희망 기간 (선택)' }),
          h('div.chips', { uid: 'P05-F05', uidLabel: '희망 기간 선택' },
            [8, 12, 16, 24, 36, 52].map(function (w) {
              return h('button.chip' + (deadlineWeeks === w ? '.is-on' : ''), {
                text: w + '주',
                onClick: function () { deadlineWeeks = (deadlineWeeks === w ? null : w); draw(); }
              });
            }).concat([
              h('button.chip' + (deadlineWeeks == null ? '.is-on' : ''), {
                text: '기간 안 정함', uid: 'P05-B02', uidLabel: '기간 미지정',
                onClick: function () { deadlineWeeks = null; draw(); }
              })
            ])),
          h('div.field__hint', { text: deadlineWeeks
            ? '이 기간 안에 가능한지 아래에서 판정합니다. 강도별 실제 소요 기간은 다음 화면에서 봅니다.'
            : '비워두면 각 강도가 필요로 하는 기간을 그대로 보여줍니다.' })
        ]));

        /* --- F06 우선순위 --- */
        form.appendChild(h('div.field', [
          h('div.field__label', { text: '우선순위' }),
          h('div.chips', { uid: 'P05-F06', uidLabel: '우선순위 선택' }, [
            ['fat', '체지방 감량 우선'], ['muscle', '근육 증가 우선'], ['balanced', '균형']
          ].map(function (p) {
            return h('button.chip' + ((g.priority || 'balanced') === p[0] ? '.is-on' : ''), {
              text: p[1],
              onClick: function () { g.priority = p[0]; draw(); }
            });
          }))
        ]));

        body.appendChild(form);

        /* --- C03 실시간 실현가능성 --- */
        var goalInfo = E.classifyGoal(cur, g);
        var gauge = h('div.card', { uid: 'P05-C03', uidLabel: '실현가능성 게이지' });
        gauge.appendChild(h('div.card__head', [
          h('div.card__title', { text: '이 목표는?' }),
          h('span.badge.badge--accent', { text: goalInfo.typeLabel })
        ]));
        gauge.appendChild(h('div.stats', [
          delta('체중', goalInfo.dWeightKg, 'kg'),
          delta('골격근', goalInfo.dSmmKg, 'kg'),
          delta('체지방', goalInfo.dBfmKg, 'kg'),
          mini('목표 체지방률', goalInfo.targetPbfPct, '%')
        ]));

        if (!goalInfo.isConsistent) {
          gauge.appendChild(h('div.note.note--warn', { uid: 'P05-S03', uidLabel: '목표 정합성 경고',
            style: { marginTop: '12px' } }, [
            h('b', { text: '세 숫자가 서로 안 맞습니다. ' }),
            '골격근량 ' + UI.n1(g.smmKg) + 'kg + 체지방량 ' + UI.n1(g.bfmKg) + 'kg이면 체중은 약 ' +
            UI.n1(goalInfo.impliedWeightKg) + 'kg이 됩니다 (입력값 ' + UI.n1(g.weightKg) + 'kg, ' +
            UI.sign(goalInfo.mismatchKg) + 'kg 차이). ',
            h('button.btn.btn--sm', { text: '체중 맞추기', style: { marginTop: '8px' },
              uid: 'P05-B03', uidLabel: '체중 자동 정합',
              onClick: function () { recalcWeight(); draw(); } })
          ]));
        }

        var essentialFat = prof.sex === 'male' ? 8 : 15;
        if (goalInfo.targetPbfPct < essentialFat + 2) {
          gauge.appendChild(h('div.note.note--bad', { uid: 'P05-S04', uidLabel: '필수지방 경고' }, [
            h('b', { text: '체지방률이 너무 낮습니다. ' }),
            '남성 필수지방은 약 ' + essentialFat + '%입니다. ' + UI.n1(goalInfo.targetPbfPct) +
            '%는 호르몬·면역·수행능력에 문제가 생기는 구간입니다.'
          ]));
        }

        // 미리보기 — 선택된 모드의 제약을 그대로 반영해야 다음 화면과 숫자가 같다
        var selEarly = selectMode(cur, g, prof, scan, deadlineWeeks, manualModeId);
        var preview = null;
        if (!selEarly.refused) {
          try {
            preview = E.compareLevels(scan, prof, g, todayISO(), deadlineWeeks, selEarly.mode);
          } catch (e) { /* 입력이 아직 이상한 상태 */ }
        }

        if (preview && preview.results.length) {
          var mid = preview.results.find(function (r) { return r.level === 'mid'; });
          var best = preview.results.find(function (r) { return r.level === 'high'; });
          var v = mid.feasibility.verdict;
          var cls = v === 'ok' ? 'ok' : (v === 'tough' ? 'warn' : 'bad');
          gauge.appendChild(h('div.note.note--' + cls, { uid: 'P05-S05', uidLabel: '기간 미리보기',
            style: { marginTop: '12px' } }, [
            h('b', { text: '가장 빨라도 ' + best.weeks + '주 (' + UI.dateK(best.targetDate) + ')' }),
            h('div', { style: { marginTop: '4px' } },
              ['여유롭게 가면 ' + preview.results[2].weeks + '주 (' +
               UI.dateK(preview.results[2].targetDate) + ')까지 늘어납니다.']),
            deadlineWeeks ? h('div', { style: { marginTop: '6px', fontWeight: '700' },
              text: mid.feasibility.badge + ' ' + mid.feasibility.message }) : null
          ]));
          if (preview.bottleneckNote) {
            gauge.appendChild(h('div.note', { uid: 'P05-S06', uidLabel: '병목 안내',
              text: '🔎 ' + preview.bottleneckNote.text }));
          }
        }

        body.appendChild(gauge);

        /* --- C05 변경 전후 비교 (이미 목표가 있을 때만) --- */
        if (isEdit && baseGoal) {
          var changed = Math.abs(baseGoal.weightKg - g.weightKg) >= 0.05 ||
                        Math.abs(baseGoal.smmKg - g.smmKg) >= 0.05 ||
                        Math.abs(baseGoal.bfmKg - g.bfmKg) >= 0.05;
          var diff = h('div.card.card--flat', { uid: 'P05-C05', uidLabel: '목표 변경 전후' }, [
            h('div.card__head', [
              h('div.card__title', { text: '이전 목표와 비교' }),
              h('span.badge' + (changed ? '.badge--accent' : ''), { text: changed ? '바뀜' : '그대로' })
            ]),
            diffRow('체중', baseGoal.weightKg, g.weightKg, 'kg'),
            diffRow('골격근량', baseGoal.smmKg, g.smmKg, 'kg'),
            diffRow('체지방량', baseGoal.bfmKg, g.bfmKg, 'kg')
          ]);
          if (changed && st.plan) {
            diff.appendChild(h('div.note.note--warn', { style: { marginTop: '10px' },
              text: '지금 플랜은 이전 목표로 만든 것입니다. 저장하면 다시 만듭니다.' }));
          }
          if (st.goalHistory && st.goalHistory.length) {
            diff.appendChild(h('button.btn.btn--ghost.btn--sm', {
              text: '지난 목표 ' + st.goalHistory.length + '개 보기',
              style: { marginTop: '10px' },
              uid: 'P05-B08', uidLabel: '목표 이력 보기',
              onClick: function () { showHistory(st.goalHistory); }
            }));
          }
          body.appendChild(diff);
        }

        /* --- C04 몸 만들기 모드 (자동 선택) --- */
        var sel = selEarly;
        body.appendChild(modeCard(sel));

        /* --- 액션 --- */
        body.appendChild(h('div.btn-row', { style: { marginTop: '4px' } }, [
          h('button.btn', { text: '추천 목표로', uid: 'P05-B04', uidLabel: '추천 목표 채우기',
            onClick: function () {
              g = recommendGoal(cur, scan, prof); draw();
              global.MB_UID.toast('인바디 적정체중 기준으로 채웠습니다');
            } }),
          h('button.btn.btn--primary', {
            text: isEdit ? '목표 바꾸기 →' : '강도 고르기 →',
            uid: 'P05-B05', uidLabel: isEdit ? '목표 바꾸기' : '강도 고르기',
            disabled: sel.refused || undefined, onClick: next })
        ]));

        body.appendChild(h('div.muted', { style: { marginTop: '10px', textAlign: 'center' },
          text: '이 앱은 의료기기가 아니며 진단·치료 목적이 아닙니다.' }));

        function next() {
          var info = E.classifyGoal(cur, g);
          if (info.targetPbfPct < essentialFat) {
            global.MB_MODALS.unsafeGoal(info, essentialFat);
            return;
          }
          if (!info.isConsistent) {
            global.MB_MODALS.inconsistentGoal(info, function () { recalcWeight(); commit(); });
            return;
          }
          commit();
        }
        function commit() {
          g.deadlineWeeks = deadlineWeeks;
          g.modeId = sel.modeId || null;
          g.manualModeId = manualModeId;

          var hadPlan = st.plan;
          if (!isEdit || !baseGoal) {          // 처음 설정
            S.setGoal(g, 'first');
            A.go('P06');
            return;
          }

          global.MB_MODALS.changeGoal({
            oldGoal: baseGoal, newGoal: g, plan: hadPlan,
            onPickLevel: function () {
              S.setGoal(g, 'changed');
              A.go('P06');
            },
            onKeepLevel: function () {
              // 같은 강도로 플랜만 다시 만든다 — 강도를 또 고르게 하지 않는다
              S.setGoal(g, 'changed');
              try {
                var modeDef = (g.modeId && global.MB_MODES) ? global.MB_MODES.byId(g.modeId) : null;
                var cmp = E.compareLevels(scan, prof, g, todayISO(), deadlineWeeks, modeDef);
                var level = hadPlan.level;
                if (!cmp.results.some(function (r) { return r.level === level; })) level = 'mid';
                var plan = E.buildPlan(cmp, level, scan, prof);
                S.setPlan(plan);
                global.MB_UID.toast('플랜을 다시 만들었습니다 · ' + UI.dateK(plan.targetDate));
                A.go('P07');
              } catch (err) {
                global.MB_UID.toast('플랜을 다시 만들지 못했습니다. 강도를 골라주세요.');
                A.go('P06');
              }
            }
          });
        }

        /* --- 모드 카드 --- */
        function modeCard(sel) {
          var card = h('div.card.card--accent', { uid: 'P05-C04', uidLabel: '몸 만들기 모드' });

          if (sel.refused) {
            card.appendChild(h('div.card__head', [
              h('div.card__title', { text: '이 목표로는 계획을 만들 수 없습니다' }),
              h('span.badge.badge--bad', { text: '중단' })
            ]));
            card.appendChild(h('div.note.note--bad', { uid: 'P05-S07', uidLabel: '목표 거부 안내',
              text: sel.message }));
            return card;
          }

          var m = sel.mode;
          card.appendChild(h('div.card__head', [
            h('div', [
              h('div.card__sub', { text: manualModeId ? '직접 고른 모드' : '입력하신 변화량에 맞는 모드' }),
              h('div', { style: { fontSize: '19px', fontWeight: '900', letterSpacing: '-.02em' },
                         text: m.nameKo })
            ]),
            h('span.badge' + (manualModeId ? '' : '.badge--accent'),
              { text: manualModeId ? '직접 선택' : '자동 선택' })
          ]));
          if (m.aliasKo) card.appendChild(h('div.muted', { text: '다른 말로 · ' + m.aliasKo }));
          card.appendChild(h('div', { style: { marginTop: '8px', fontSize: '13.5px' }, text: m.oneLiner }));

          if (!manualModeId && sel.reason) {
            card.appendChild(h('div.note', { style: { marginTop: '10px' },
              text: '왜 이 모드인가 — ' + sel.reason }));
          }
          if (sel.trendNote) {
            card.appendChild(h('div.note.note--warn', { text: sel.trendNote }));
          }
          var sub = [];
          if (sel.subNoise) {
            if (sel.subNoise.smm) sub.push('근육');
            if (sel.subNoise.bfm) sub.push('체지방');
            if (sel.subNoise.weight) sub.push('체중');
          }
          if (sub.length) {
            card.appendChild(h('div.note.note--warn', {
              text: sub.join('·') + ' 변화량이 인바디 측정 오차(체중 ±' + MODES.NOISE.weight +
                    'kg · 근육 ±' + MODES.NOISE.smm + 'kg · 지방 ±' + MODES.NOISE.bfm +
                    'kg) 안쪽입니다. 기계가 구분하지 못하는 크기라 목표로 삼기 어렵습니다.' }));
          }

          card.appendChild(h('hr.sep'));
          card.appendChild(kv('방향', ({ deficit: '적자 (덜 먹기)', surplus: '잉여 (더 먹기)',
            maintenance: '유지', mixed: '거의 유지하며 구성만 바꾸기' })[m.direction] || m.direction));
          card.appendChild(kv('보통 걸리는 기간', m.typicalWeeksMin + '~' + m.typicalWeeksMax + '주'));
          card.appendChild(kv('단백질', m.proteinPerFfmMin + '~' + m.proteinPerFfmMax + ' g/kg 제지방'));
          if (m.maxContinuousWeeks) card.appendChild(kv('연속 지속 한계', m.maxContinuousWeeks + '주'));

          card.appendChild(h('div', { style: { marginTop: '10px' } }, [
            h('div.section-title', { text: '이 모드가 맞는 사람' }),
            h('div.muted', { text: MODES.forDisplay(m.whoFor) })
          ]));
          card.appendChild(h('div', { style: { marginTop: '8px' } }, [
            h('div.section-title', { text: '이 모드가 아닌 사람' }),
            h('div.muted', { text: MODES.forDisplay(m.notFor) })
          ]));
          var expected = MODES.forDisplay(m.expectedKo);
          var risks = MODES.forDisplay(m.risksKo);
          var training = MODES.forDisplay(m.trainingPolicyKo);
          if (training) {
            card.appendChild(h('div', { style: { marginTop: '8px' } }, [
              h('div.section-title', { text: '이 모드의 운동' }),
              h('div.muted', { text: training })
            ]));
          }
          if (expected) {
            card.appendChild(h('div.note', { style: { marginTop: '10px' }, text: '예상 — ' + expected }));
          }
          if (risks) {
            card.appendChild(h('div.note.note--warn', { text: '주의 — ' + risks }));
          }
          if (m.exitCriteriaKo) {
            card.appendChild(h('div.muted', { style: { marginTop: '8px' },
              text: '끝내는 시점 — ' + MODES.forDisplay(m.exitCriteriaKo) }));
          }

          card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
            h('button.btn.btn--sm', {
              text: showAllModes ? '모드 목록 접기' : '다른 모드 보기',
              uid: 'P05-B06', uidLabel: '모드 목록 토글',
              onClick: function () { showAllModes = !showAllModes; draw(); }
            }),
            manualModeId ? h('button.btn.btn--sm', {
              text: '자동 선택으로', uid: 'P05-B07', uidLabel: '자동 선택으로 되돌리기',
              onClick: function () { manualModeId = null; draw(); }
            }) : null
          ]));

          if (showAllModes) {
            var list = h('div', { uid: 'P05-L01', uidLabel: '모드 목록', style: { marginTop: '10px' } });
            MODES.MODES.forEach(function (x) {
              var isOn = x.id === sel.modeId;
              var why = MODES.whyNot(x, sel.input);
              list.appendChild(h('div.radio-card' + (isOn ? '.is-on' : ''), {
                style: { marginBottom: '6px' },
                onClick: function () {
                  manualModeId = (x.id === sel.modeId && !manualModeId) ? null : x.id;
                  showAllModes = false; draw();
                }
              }, [
                h('div', { style: { flex: '1' } }, [
                  h('div.radio-card__t', { text: x.nameKo + (isOn ? ' · 선택됨' : '') }),
                  h('div.radio-card__d', { text: x.oneLiner }),
                  why ? h('div.radio-card__d', {
                    style: { color: 'var(--warn)', marginTop: '4px' }, text: '⚠ ' + why }) : null
                ])
              ]));
            });
            card.appendChild(list);
            card.appendChild(h('div.muted', { style: { marginTop: '6px' },
              text: '직접 고르면 앱이 말리더라도 그 모드로 계획을 만듭니다. 경고는 그대로 남습니다.' }));
          }
          return card;
        }
      }

      function recalcWeight() {
        var ffm = g.smmKg / cur.smmToFfm;
        g.weightKg = Math.round((ffm + g.bfmKg) * 10) / 10;
      }
      function solveFromWeight() {
        // 체중을 직접 바꾸면 체지방량으로 차이를 흡수한다 (근육은 사용자 의도값 유지)
        var ffm = g.smmKg / cur.smmToFfm;
        g.bfmKg = Math.max(2, Math.round((g.weightKg - ffm) * 10) / 10);
      }
    }
  });

  var MODES = global.MB_MODES;

  function diffRow(label, a, b, unit) {
    var d = b - a, same = Math.abs(d) < 0.05;
    return h('div.kv', [
      h('span.kv__k', { text: label }),
      h('span.kv__v', [
        h('span', { style: { color: 'var(--text-3)' }, text: UI.n1(a) + unit }),
        ' → ',
        h('span', { style: { color: same ? 'inherit' : 'var(--accent)' }, text: UI.n1(b) + unit }),
        same ? null : h('span', { style: { fontSize: '11.5px', fontWeight: '600',
          marginLeft: '6px', color: 'var(--text-3)' }, text: '(' + UI.sign(d) + unit + ')' })
      ])
    ]);
  }

  /** 지난 목표들 — 언제 무엇을 목표로 했고 왜 바꿨는지 */
  function showHistory(history) {
    UI.openModal({
      uid: 'M35', title: '지난 목표',
      sub: history.length + '번 바꿨습니다',
      body: history.slice().reverse().map(function (hst, i) {
        var g = hst.goal;
        return h('div.card.card--flat', { style: { marginBottom: '8px' } }, [
          h('div.card__head', [
            h('div.card__sub', { text: UI.dateK(hst.replacedAt) + ' 까지' }),
            hst.planLevel ? h('span.badge', { text: hst.planLevel === 'high' ? '상'
              : (hst.planLevel === 'mid' ? '중' : '하') }) : null
          ]),
          h('div.stats', [
            miniStat('체중', g.weightKg, 'kg'),
            miniStat('골격근', g.smmKg, 'kg'),
            miniStat('체지방', g.bfmKg, 'kg')
          ]),
          hst.planTargetDate ? h('div.muted', { style: { marginTop: '6px' },
            text: '당시 목표일 ' + UI.dateK(hst.planTargetDate) }) : null
        ]);
      }),
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  }

  function miniStat(label, v, u) {
    return h('div.stat', [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { style: { fontSize: '15px' }, text: UI.n1(v) }),
                h('span.stat__u', { text: u })])
    ]);
  }

  function kv(k, v) {
    return h('div.kv', [h('span.kv__k', { text: k }), h('span.kv__v', { text: v })]);
  }

  /** 최근 추세로 지금 어느 국면인지 추정 — 증량 중이면 미니컷 규칙이 열린다 */
  function currentPhaseFrom(trend) {
    if (!trend || trend.weeksSpan < 4) return null;
    var N = global.MB_MODES.NOISE;
    if (trend.dWeightKg > N.weight && trend.dSmmKg > -N.smm) return 'bulk';
    if (trend.dWeightKg < -N.weight) return 'cut';
    return null;
  }

  /** 입력 변화량 → 모드 자동 선택 (직접 고른 게 있으면 그걸 쓴다) */
  function selectMode(cur, g, prof, scan, deadlineWeeks, manualModeId) {
    var gi = E.classifyGoal(cur, g);
    var scans = S.sortedScans();
    var trend = null;
    if (scans.length >= 2) {
      var a = E.derive(scans[0], prof), b = E.derive(scans[scans.length - 1], prof);
      var days = (new Date(scans[scans.length - 1].measuredAt) - new Date(scans[0].measuredAt)) / 86400000;
      trend = { weeksSpan: days / 7, dWeightKg: b.weightKg - a.weightKg,
                dSmmKg: b.smmKg - a.smmKg, dBfmKg: b.bfmKg - a.bfmKg };
    }
    var input = {
      dWeightKg: gi.dWeightKg, dSmmKg: gi.dSmmKg, dBfmKg: gi.dBfmKg,
      curWeightKg: cur.weightKg, curSmmKg: cur.smmKg, curBfmKg: cur.bfmKg,
      curPbfPct: cur.pbfPct, curBmi: cur.bmi, heightCm: prof.heightCm, tdeeKcal: cur.tdeeKcal,
      sex: prof.sex, age: prof.age, trainingAge: prof.trainingAge,
      hadPriorPeak: !!prof.hadPriorPeak, deadlineWeeks: deadlineWeeks || null,
      recentTrend: trend, currentPhase: currentPhaseFrom(trend)
    };
    var r = MODES.select(input);
    r.input = input;
    if (!r.refused && manualModeId) {
      var m = MODES.byId(manualModeId);
      if (m) { r.mode = m; r.modeId = m.id; r.manual = true; }
    }
    return r;
  }

  /* --- 추천 목표: 인바디 적정체중 + 체지방률 15% 기준 --- */
  function recommendGoal(cur, scan, prof) {
    var targetPbf = prof.sex === 'male' ? 15 : 24;
    var smm = Math.round((cur.smmKg + 1.0) * 10) / 10;        // 근육은 소폭 증가 목표
    var ffm = smm / cur.smmToFfm;
    var weight = Math.round(ffm / (1 - targetPbf / 100) * 10) / 10;
    var bfm = Math.round((weight - ffm) * 10) / 10;
    return { weightKg: weight, smmKg: smm, bfmKg: bfm, priority: 'balanced', deadlineWeeks: null };
  }

  function todayISO() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
           String(d.getDate()).padStart(2, '0');
  }

  function mini(label, v, u) {
    return h('div.stat', [h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(v) }), h('span.stat__u', { text: u })])]);
  }
  function delta(label, v, u) {
    return h('div.stat', [h('div.stat__k', { text: 'Δ ' + label }),
      h('div', [h('span.stat__v', {
        style: { color: v > 0 ? 'var(--muscle)' : (v < 0 ? 'var(--fat)' : 'inherit') },
        text: UI.sign(v) }), h('span.stat__u', { text: u })])]);
  }

  function numField(uid, label, value, unit, min, max, step, onChange, hint, readonly) {
    var input;
    var field = h('div.field', [
      h('div.field__label', { text: label }),
      h('div.input-unit', [
        input = h('input.input.input--num', {
          type: 'number', value: value, min: min, max: max, step: step,
          uid: uid, uidLabel: label, readonly: readonly || undefined,
          onChange: function () {
            var v = parseFloat(input.value);
            if (isNaN(v)) return;
            onChange(Math.max(min, Math.min(max, Math.round(v * 10) / 10)));
          }
        }),
        h('span.input-unit__u', { text: unit })
      ]),
      h('input.range', {
        type: 'range', value: value, min: min, max: max, step: step,
        onInput: function (e) { onChange(parseFloat(e.target.value)); }
      }),
      hint ? h('div.field__hint', { text: hint }) : null
    ]);
    return field;
  }
})(window);
