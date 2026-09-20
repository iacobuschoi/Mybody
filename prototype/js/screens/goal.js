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

      /* 이 앱이 허용하는 체지방률 하한과, 생리적 필수 체지방.
       *
       * 둘은 다른 숫자입니다. 필수지방은 "이 밑으로는 살 수 없다",
       * 하한은 "이 앱은 여기까지만 도와준다" 입니다. 한 문장에 섞어
       * 쓰다가 서로 다른 숫자 셋이 한 화면에 나왔고, 그중 하나는
       * 여성 사용자에게 "남성 필수지방은..." 이라고 말했습니다.
       * 앱에서 유일하게 "그건 몸에 해롭습니다" 라고 말하는 자리라,
       * 여기서 신뢰를 잃으면 그 말을 지킬 방법이 없습니다.
       * 화면 두 곳(경고 줄 · 진행 차단)이 같은 값을 써야 하므로
       * 여기 한 군데서 정합니다. */
      var isMale = prof.sex === 'male';
      var floorPct = isMale ? 8 : 15;                 // 이 앱이 허용하는 하한
      var essentialPct = isMale ? '2~5' : '10~13';    // 생리적 필수 체지방

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

        /* 이 경고는 앱에서 유일하게 "그건 몸에 해롭습니다" 라고 말하는
           자리입니다. 그런데 문장이 "남성 필수지방은..." 으로 박혀 있어서,
           여성 사용자는 자기 얘기가 아니거나 앱이 성별을 잘못 안 것으로
           읽었습니다. 막으려고 만든 경고가 무시당하는 방식입니다.
           하한 숫자도 바로 아래 설명(남 2~5% / 여 10~13%)과 어긋났습니다 —
           여기 8/15 는 "필수지방" 이 아니라 "이 앱이 허용하는 하한" 입니다.
           둘은 다른 것이고, 다르게 말해야 합니다. */
        if (goalInfo.targetPbfPct < floorPct + 2) {
          gauge.appendChild(h('div.note.note--bad', { uid: 'P05-S04', uidLabel: '필수지방 경고' }, [
            h('b', { text: '체지방률이 너무 낮습니다. ' }),
            (isMale ? '남성' : '여성') + '의 필수 체지방은 ' + essentialPct + '% 이고, ' +
            '이 앱은 ' + floorPct + '% 를 하한으로 둡니다. ' + UI.n1(goalInfo.targetPbfPct) +
            '% 는 호르몬·면역·수행능력에 문제가 생기는 구간입니다.'
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

        if (preview && (preview.impossible || !preview.results.length)) {
          // 강도 화면까지 가서야 "도달 불가"를 알게 하면 안 된다. 여기서 막는다.
          var box = h('div.note.note--bad', { uid: 'P05-S08', uidLabel: '도달 불가 안내' }, [
            h('b', { text: '이 목표에는 도달할 수 없습니다. ' }),
            (preview.warnings && preview.warnings[0]) ||
              '지금 모드가 허용하는 속도로는 4년 안에도 닿지 않습니다.'
          ]);

          /* 제일 흔한 원인 하나는 짚어 줍니다.
           *
           * "근육 1kg 만 늘리고 체지방은 지금 그대로" 는 사람이 아주
           * 자연스럽게 세우는 목표인데, 앱은 "어떤 강도로도 4년 안에
           * 안 됩니다" 라고만 답했습니다. 무엇을 어느 방향으로 고쳐야
           * 하는지는 말하지 않았고, 기본 안내("목표치를 줄이세요")는
           * 여기서 정반대였습니다 — 올려야 합니다.
           *
           * 근육을 늘리려면 잉여 칼로리가 필요하고, 그러면 체지방도
           * 얼마간 같이 올라갑니다. 그게 생리적인 사실이지 앱의 고집이
           * 아니라는 것을 말해야 합니다. */
          var dSmm = g.smmKg - cur.smmKg;
          var dBfm = g.bfmKg - cur.bfmKg;
          var N = (global.MB_MODES && global.MB_MODES.NOISE) || { smm: 0.6, bfm: 1.0 };
          if (dSmm > N.smm && Math.abs(dBfm) < N.bfm) {
            /* 근육 1kg 을 늘리는 동안 늘어나는 체지방은 강도와 경험에
               따라 다르지만, 초보라도 대략 같은 양 안팎입니다. 여기서는
               "조금은 올려야 한다" 만 말하고, 정확한 숫자는 다음 화면의
               시뮬레이션이 냅니다. */
            var suggest = Math.round((cur.bfmKg + Math.max(1.0, dSmm)) * 10) / 10;
            box.appendChild(h('div', { style: { marginTop: '8px' } }, [
              '근육을 늘리려면 잉여 칼로리가 필요하고, 그동안 체지방도 조금 올라갑니다. ' +
              '체지방을 지금 그대로 묶어 두면 근육만 늘릴 방법이 없습니다.'
            ]));
            box.appendChild(h('button.btn.btn--sm', {
              text: '목표 체지방량을 ' + UI.n1(suggest) + 'kg 으로 올리기',
              style: { marginTop: '8px' },
              uid: 'P05-B09', uidLabel: '체지방 목표 올리기',
              onClick: function () { g.bfmKg = suggest; recalcWeight(); draw(); }
            }));
          } else {
            box.appendChild(h('div', { style: { marginTop: '8px' },
              text: '목표치를 줄이거나 모드를 바꿔보세요.' }));
          }
          gauge.appendChild(box);
        } else if (preview && preview.results.length) {
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
            disabled: (sel.refused || (preview && preview.impossible)) || undefined, onClick: next })
        ]));

        body.appendChild(h('div.muted', { style: { marginTop: '10px', textAlign: 'center' },
          text: '이 앱은 의료기기가 아니며 진단·치료 목적이 아닙니다.' }));

        function next() {
          var info = E.classifyGoal(cur, g);
          if (info.targetPbfPct < floorPct) {
            global.MB_MODALS.unsafeGoal(info, floorPct);
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
          var pl = m.plain || {};
          card.appendChild(h('div', { style: { marginTop: '8px', fontSize: '13.5px' },
            text: pl.one || m.oneLiner }));

          if (!manualModeId && sel.reason) {
            // 선택 이유는 길어서 앞 한 문장만 보여주고 나머지는 접는다
            var parts = String(sel.reason).split(/(?<=\.)\s+/);
            var head = parts[0] || sel.reason;
            var rest = parts.slice(1).join(' ');
            card.appendChild(UI.plainNote({
              uid: 'P05-S09', label: '모드 선택 이유',
              title: '왜 이 모드인가', text: head,
              evidence: rest || null
            }));
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

          card.appendChild(h('div', { style: { marginTop: '12px', display: 'grid', gap: '6px' } }, [
            h('div', [h('span.section-title', { style: { margin: '0 6px 0 0', display: 'inline' },
                                                text: '맞는 사람' }),
                      h('span.muted', { text: pl.who || MODES.forDisplay(m.whoFor) })]),
            h('div', [h('span.section-title', { style: { margin: '0 6px 0 0', display: 'inline' },
                                                text: '아닌 사람' }),
                      h('span.muted', { text: pl.not || MODES.forDisplay(m.notFor) })])
          ]));
          card.appendChild(UI.plainNote({
            uid: 'P05-S10', label: '예상 결과',
            title: '예상', text: pl.expect || MODES.forDisplay(m.expectedKo).slice(0, 90),
            evidence: pl.evidence || null
          }));
          if (pl.risk || m.risksKo) {
            card.appendChild(UI.plainNote({
              uid: 'P05-S11', label: '주의', tone: 'warn',
              title: '주의', text: pl.risk || MODES.forDisplay(m.risksKo).slice(0, 90),
              evidence: MODES.forDisplay(m.risksKo) !== (pl.risk || '')
                ? MODES.forDisplay(m.risksKo) : null
            }));
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
