/* P05 — 목표 설정 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  A.register('P05', {
    title: '목표 설정', label: '목표 설정',
    render: function (wrap, ctx) {
      var st = S.get();
      var scan = A.requireScan(wrap, ctx, 'P05');
      if (!scan) return;
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var cur = E.derive(scan, prof);

      // 목표 초기값: 저장된 값 → 없으면 인바디 적정체중 기반 추천
      var g = st.goal ? Object.assign({}, st.goal) : recommendGoal(cur, scan, prof);
      var linked = true;        // 체중 = 제지방 + 체지방 연동
      var deadlineWeeks = st.goal && st.goal.deadlineWeeks ? st.goal.deadlineWeeks : null;

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

        // 가벼운 미리보기 — 중간 강도 기준 예상 기간
        var preview = null;
        try {
          preview = E.compareLevels(scan, prof, g, todayISO(), deadlineWeeks);
        } catch (e) { /* 입력이 아직 이상한 상태 */ }

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

        /* --- 액션 --- */
        body.appendChild(h('div.btn-row', { style: { marginTop: '4px' } }, [
          h('button.btn', { text: '추천 목표로', uid: 'P05-B04', uidLabel: '추천 목표 채우기',
            onClick: function () {
              g = recommendGoal(cur, scan, prof); draw();
              global.MB_UID.toast('인바디 적정체중 기준으로 채웠습니다');
            } }),
          h('button.btn.btn--primary', { text: '강도 고르기 →', uid: 'P05-B05',
            uidLabel: '강도 고르기', onClick: next })
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
          S.set({ goal: g });
          A.go('P06');
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
