/* P08 — 주간 체크인 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 식단 준수도: 상/중/하 → 수치화 (엔진의 adherence.dietPct 로 그대로 들어간다) */
  var DIET_LEVELS = [
    { key: 'high', label: '상', pct: 90, desc: '거의 계획대로 먹었다' },
    { key: 'mid',  label: '중', pct: 70, desc: '절반 이상은 지켰다' },
    { key: 'low',  label: '하', pct: 45, desc: '거의 못 지켰다' }
  ];
  var CONDITIONS = [
    { key: 'good',   label: '좋음', desc: '잘 잤고 몸이 가볍다' },
    { key: 'normal', label: '보통', desc: '평소와 비슷하다' },
    { key: 'bad',    label: '나쁨', desc: '수면 부족 · 피로 누적' }
  ];
  var STEPS = [
    { t: '측정',   d: '이번 주 숫자를 넣습니다' },
    { t: '수행도', d: '얼마나 지켰는지 솔직하게' },
    { t: '결과',   d: '예상과 실제를 맞춰봅니다' }
  ];

  /* 화면을 떠났다 돌아와도 작성 중이던 내용은 그날 안에서는 유지한다 */
  var step = 0;
  var draft = null;
  var draftDay = null;
  var savedAt = null;

  function newDraft() {
    return { weightKg: null, workoutPct: 70, dietKey: 'mid', dietPct: 70,
             condition: 'normal', memo: '' };
  }

  A.register('P08', {
    title: '체크인', label: '주간 체크인',
    render: function (wrap, ctx) {
      var st = S.get();
      var plan = A.requirePlan(wrap, ctx, 'P08');
      if (!plan) return;

      var today = todayISO();
      if (!draft || draftDay !== today) {
        draft = newDraft(); draftDay = today; savedAt = null; step = 0;
      }

      var scan = S.latestScan();
      var lastMeasuredISO = lastMeasureISO(st, scan);

      var body = h('div');
      wrap.appendChild(body);
      draw();

      /* =====================================================================
       * 그리기
       * ================================================================== */
      function draw() {
        UI.clear(body);
        body.appendChild(stepHeader());
        if (step === 0) drawStep1();
        else if (step === 1) drawStep2();
        else drawStep3();
        body.appendChild(pastCard());
        body.appendChild(honestyCard());
      }

      function stepHeader() {
        return h('div.card.card--flat', { uid: 'P08-C07', uidLabel: '체크인 단계 표시' }, [
          h('div.card__head', [
            h('div.card__title', { text: (step + 1) + '/3 · ' + STEPS[step].t }),
            h('span.badge.badge--accent', { text: Math.round((step + 1) / 3 * 100) + '%' })
          ]),
          h('div.bar', [h('div.bar__fill', { style: { width: ((step + 1) / 3 * 100) + '%' } })]),
          h('div.progress-steps', STEPS.map(function (s, i) {
            return h('div.pstep' + (i < step ? '.is-done' : (i === step ? '.is-active' : '')), [
              h('div.pstep__dot', { text: i < step ? '✓' : String(i + 1) }),
              h('span', { text: s.t })
            ]);
          })),
          h('div.card__sub', { text: STEPS[step].d })
        ]);
      }

      /* ---------------------------------------------------------------- */
      /* 1단계 — 측정                                                       */
      /* ---------------------------------------------------------------- */
      function drawStep1() {
        var card = h('div.card', { uid: 'P08-C01', uidLabel: '1단계 · 이번 주 측정' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '이번 주 측정' }),
          h('div.card__sub', { text: lastMeasuredISO
            ? '마지막 측정 ' + UI.dateK(lastMeasuredISO) + ' · ' + agoText(lastMeasuredISO)
            : '아직 기록이 없습니다' })
        ]));

        card.appendChild(h('button.btn.btn--block', {
          text: '📷 인바디 새로 찍기', uid: 'P08-B01', uidLabel: '인바디 새로 찍기',
          onClick: function () { A.go('P03'); }
        }));
        card.appendChild(h('div.field__hint', {
          text: '인바디를 새로 찍었다면 결과지를 올리는 쪽이 정확합니다. 체지방·골격근까지 같이 갱신됩니다.'
        }));

        card.appendChild(h('hr.sep'));

        var nextBtn, hint, input;
        hint = h('div.field__hint', { text: '아침 기상 직후 · 화장실 다녀온 뒤 · 같은 옷차림으로 잰 값이 가장 비교 가능합니다.' });
        input = h('input.input.input--num', {
          type: 'number', step: '0.1', min: '30', max: '250',
          value: draft.weightKg != null ? draft.weightKg : '',
          placeholder: scan ? UI.n1(scan.weightKg) : '',
          uid: 'P08-F01', uidLabel: '체중 간단 입력',
          onInput: function () {
            var v = parseFloat(input.value);
            draft.weightKg = isNaN(v) ? null : Math.round(v * 10) / 10;
            sync();
          }
        });
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '체중만 간단 입력' }),
          h('div.input-unit', [input, h('span.input-unit__u', { text: 'kg' })]),
          hint
        ]));

        var gap = gapWarning();
        if (gap) card.appendChild(gap);

        nextBtn = h('button.btn.btn--primary.btn--block', {
          text: '다음 · 수행도 적기', uid: 'P08-B06', uidLabel: '다음 단계',
          onClick: function () {
            if (draft.weightKg == null) { global.MB_UID.toast('체중을 입력해 주세요'); return; }
            step = 1; draw();
          }
        });
        card.appendChild(h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
          nextBtn,
          h('button.btn.btn--ghost.btn--block', {
            text: '이번 주 건너뛰기', uid: 'P08-B02', uidLabel: '이번 주 건너뛰기',
            onClick: function () {
              draft = newDraft(); draftDay = todayISO(); savedAt = null; step = 0;
              global.MB_UID.toast('이번 주 체크인을 건너뜁니다');
              A.go('P02');
            }
          })
        ]));

        sync();
        function sync() {
          var ok = draft.weightKg != null;
          nextBtn.disabled = !ok;
          nextBtn.style.opacity = ok ? '' : '.5';
        }

        body.appendChild(card);
      }

      /** S01 — 측정 간격이 3일 미만이면 경고 (진행은 막지 않는다) */
      function gapWarning() {
        if (!lastMeasuredISO) return null;
        var d = daysSince(lastMeasuredISO);
        if (d >= 3) return null;
        return UI.plainNote({
          uid: 'P08-S01', label: '측정 간격 경고 상태', tone: 'warn',
          title: d === 0 ? '오늘 이미 쟀습니다' : d + '일밖에 안 지났습니다',
          text: '이 간격에서는 수분 변동이 실제 변화보다 큽니다. 기록은 그대로 하셔도 됩니다.',
          evidence: '최소 3일, 가능하면 7일 간격을 권합니다. 하루 사이 체중은 수분·나트륨·' +
                    '글리코겐 때문에 ±1kg까지 움직이는데, 체지방 1kg은 7,700kcal이라 ' +
                    '하루 만에 그만큼 빠지거나 붙을 수 없습니다.'
        });
      }

      /* ---------------------------------------------------------------- */
      /* 2단계 — 수행도                                                     */
      /* ---------------------------------------------------------------- */
      function drawStep2() {
        var w = plan.workout || {};
        var days = w.daysPerWeek || 4;

        var card = h('div.card', { uid: 'P08-C02', uidLabel: '2단계 · 수행도 입력' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '이번 주 수행도' }),
          h('div.card__sub', { text: '낮게 적어도 됩니다. 숫자를 좋게 적으면 다음 제안이 틀어집니다' })
        ]));

        /* F02 운동 이행률 */
        var pctOut = h('span.num', { style: { fontWeight: '800' }, text: draft.workoutPct + '%' });
        var sessOut = h('div.field__hint', { text: sessionsText(days, draft.workoutPct) });
        card.appendChild(h('div.field', [
          h('div.field__label', { style: { display: 'flex', justifyContent: 'space-between' } }, [
            h('span', { text: '운동 이행률' }), pctOut
          ]),
          h('input.range', {
            type: 'range', min: 0, max: 100, step: 5, value: draft.workoutPct,
            uid: 'P08-F02', uidLabel: '운동 이행률',
            onInput: function (e) {
              draft.workoutPct = parseInt(e.target.value, 10);
              pctOut.textContent = draft.workoutPct + '%';
              sessOut.textContent = sessionsText(days, draft.workoutPct);
            }
          }),
          h('div.muted', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '11px' } }, [
            h('span', { text: '0%' }), h('span', { text: '100%' })
          ]),
          sessOut
        ]));

        /* F03 식단 준수도 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '식단 준수도' }),
          h('div.chips', { uid: 'P08-F03', uidLabel: '식단 준수도 선택' },
            DIET_LEVELS.map(function (o) {
              return h('button.chip' + (draft.dietKey === o.key ? '.is-on' : ''), {
                text: o.label + ' · ' + o.pct + '%',
                onClick: function () { draft.dietKey = o.key; draft.dietPct = o.pct; draw(); }
              });
            })),
          h('div.field__hint', { text: dietHint(draft.dietKey) })
        ]));

        /* F04 컨디션 · 수면 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '컨디션 · 수면' }),
          h('div.chips', { uid: 'P08-F04', uidLabel: '컨디션·수면 선택' },
            CONDITIONS.map(function (o) {
              return h('button.chip' + (draft.condition === o.key ? '.is-on' : ''), {
                text: o.label,
                onClick: function () { draft.condition = o.key; draw(); }
              });
            })),
          h('div.field__hint', { text: '수면이 부족한 주에는 수분이 붙어 체중이 올라가기 쉽습니다. 해석할 때 참고합니다.' })
        ]));

        /* F05 메모 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '메모 (선택)' }),
          h('textarea.textarea', {
            rows: 3, text: draft.memo,
            placeholder: '예) 회식 2번, 목요일 어깨 통증으로 상체 건너뜀',
            uid: 'P08-F05', uidLabel: '체크인 메모',
            onInput: function (e) { draft.memo = e.target.value; }
          }),
          h('div.field__hint', { text: '다음 주에 같은 일이 반복되는지 보려고 남깁니다.' })
        ]));

        card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--ghost', {
            text: '‹ 이전', uid: 'P08-B07', uidLabel: '이전 단계',
            onClick: function () { step = 0; draw(); }
          }),
          h('button.btn.btn--primary', {
            text: '결과 보기', uid: 'P08-B08', uidLabel: '결과 보기 · 체크인 저장',
            onClick: function () {
              if (draft.weightKg == null) { step = 0; draw(); return; }
              saveCheckin();
              global.MB_UID.toast('체크인을 저장했습니다');
              step = 2; draw();
            }
          })
        ]));

        body.appendChild(card);
      }

      /* ---------------------------------------------------------------- */
      /* 3단계 — 결과                                                       */
      /* ---------------------------------------------------------------- */
      function drawStep3() {
        if (draft.weightKg == null) { step = 0; drawStep1(); return; }

        var traj = plan.trajectory || [];
        var elapsed = weeksElapsed(plan.startDate);
        var wkIdx = Math.max(0, Math.min(Math.round(elapsed), traj.length ? traj[traj.length - 1].week : 0));
        var snap = snapshotAt(plan, wkIdx);
        var expected = snap ? snap.weightKg : (traj.length ? traj[0].weightKg : draft.weightKg);
        var actualW = draft.weightKg;
        var gap = actualW - expected;                    // + = 예상보다 무거움
        var prevW = prevActualWeight(plan);

        /* --- C03 예상 vs 실제 --- */
        var card = h('div.card', { uid: 'P08-C03', uidLabel: '3단계 · 예상 vs 실제 비교' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: wkIdx + '주차 · 예상 vs 실제' }),
          h('div.card__sub', { text: UI.dateK(plan.startDate) + ' 시작 기준' })
        ]));
        card.appendChild(h('div.stats', [
          statBox('예상 체중', expected, 'kg'),
          statBox('실제 체중', actualW, 'kg'),
          h('div.stat' + (Math.abs(gap) < 0.15 ? '' : (gap > 0 ? '.stat--fat' : '.stat--muscle')), [
            h('div.stat__k', { text: '차이' }),
            h('div', [h('span.stat__v', { text: UI.sign(gap) }), h('span.stat__u', { text: 'kg' })]),
            h('div.stat__d', { text: Math.abs(gap) < 0.15 ? '예상 범위'
              : (gap > 0 ? '예상보다 무거움' : '예상보다 가벼움') })
          ])
        ]));
        card.appendChild(h('div.kv', [
          h('span.kv__k', { text: '지난 기록 대비' }),
          h('span.kv__v', { text: prevW != null
            ? UI.n1(prevW) + ' → ' + UI.n1(actualW) + ' kg (' + UI.sign(actualW - prevW) + 'kg)'
            : '비교할 이전 기록이 없습니다' })
        ]));
        card.appendChild(h('div.kv', [
          h('span.kv__k', { text: '계획상 이번 주 목표' }),
          h('span.kv__v', { text: snap
            ? UI.n1(snap.smmKg) + 'kg 골격근 · ' + UI.n1(snap.bfmKg) + 'kg 체지방 (추정)'
            : '—' })
        ]));

        /* --- G01 계획 궤적 + 실측 점 --- */
        var pts = actualPoints(plan);
        var series = [{
          key: 'plan', label: '계획 궤적', color: 'var(--text-3)', dashed: true, dots: false,
          points: traj.map(function (t) { return { x: t.week, y: t.weightKg }; })
        }];
        if (pts.length) {
          series.push({ key: 'actual', label: '실측 체중', color: 'var(--weight)', points: pts });
        }
        card.appendChild(h('div', { style: { marginTop: '12px' } }, [
          UI.lineChart({
            uid: 'P08-G01', label: '계획 궤적 vs 실측 체중', height: 118,
            series: series,
            goal: [{ y: expected, color: 'var(--accent)', label: '이번 주 예상' }],
            markers: [{ x: wkIdx, label: '지금' }],
            xTickFmt: function (v) { return Math.round(v) + '주'; }
          })
        ]));
        body.appendChild(card);

        /* --- C04 제안 --- */
        var advice = E.checkinAdvice(plan,
          { weightKg: expected, prevWeightKg: prevW != null ? prevW : expected },
          { weightKg: actualW },
          { dietPct: draft.dietPct });

        var sCard = h('div.card.card--accent', { uid: 'P08-C04', uidLabel: '조정 제안 카드' });
        sCard.appendChild(h('div.card__head', [
          h('div.card__title', { text: '이번 주 제안' }),
          h('span.badge.' + statusBadgeClass(advice.status), { text: statusLabel(advice.status) })
        ]));
        sCard.appendChild(h('div.card__sub', { text: statusDesc(advice.status) }));
        sCard.appendChild(h('div', { style: { marginTop: '10px' } },
          (advice.suggestions || []).map(function (s) {
            return h('div.radio-card', { style: { marginBottom: '6px' } }, [
              h('div', [
                h('div.radio-card__t', { text: s.title }),
                h('div.radio-card__d', { text: s.detail })
              ])
            ]);
          })));

        /* 엔진 판정과 화면의 실측 비교가 어긋날 수 있다 (엔진은 지난 실측치와 계획치를 비교한다).
           어긋날 때 숨기지 않고 그대로 보여준다. */
        var mStatus = measuredStatus(plan, expected, actualW);
        if (advice.status !== 'adherence' && mStatus !== advice.status) {
          sCard.appendChild(h('div.note.note--warn', { uid: 'P08-S05', uidLabel: '판정 불일치 안내' }, [
            h('b', { text: '위 비교와 판정이 다릅니다' }),
            h('div', { text: '이번 주 입력값 기준으로는 "' + statusLabel(mStatus) + '"이지만, ' +
                             '판정 엔진은 직전 실측치와 계획치를 비교해 "' + statusLabel(advice.status) + '"으로 봅니다. ' +
                             '둘이 갈릴 때는 이번 주에 아무것도 바꾸지 말고 다음 주 한 번을 더 보세요.' })
          ]));
        }

        if (draft.condition === 'bad') {
          sCard.appendChild(h('div.note', { uid: 'P08-S04', uidLabel: '컨디션 나쁨 해석 안내',
            text: '컨디션을 "나쁨"으로 적었습니다. 수면이 부족한 주에는 코르티솔·수분 때문에 체중이 0.5~1kg ' +
                  '더 나올 수 있습니다. 이번 주 숫자만 보고 칼로리를 더 줄이지 마세요.' }));
        }

        sCard.appendChild(h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--primary.btn--block', {
            text: '제안 적용', uid: 'P08-B03', uidLabel: '제안 적용',
            onClick: function () {
              global.MB_MODALS.adjust(advice, function () {
                var delta = applyAdvice(plan, advice);
                S.setPlan(plan);
                // 바꿀 수치가 없는 판정(예상 범위·순응도 문제)에서는 갱신했다고 말하지 않는다
                global.MB_UID.toast(delta !== 0
                  ? '플랜이 갱신되었습니다' + (plan.macros ? ' · 하루 ' + UI.n0(plan.macros.intakeKcal) + 'kcal' : '')
                  : '바꿀 수치가 없어 계획을 그대로 두었습니다');
                A.refresh();
              });
            }
          }),
          h('button.btn.btn--block', {
            text: '이번엔 유지', uid: 'P08-B04', uidLabel: '이번엔 유지',
            onClick: function () {
              global.MB_UID.toast('계획을 그대로 두었습니다');
              A.go('P02');
            }
          }),
          h('button.btn.btn--ghost.btn--block', {
            text: '강도 변경', uid: 'P08-B05', uidLabel: '강도 변경',
            onClick: function () { global.MB_MODALS.changeLevel(rebuildWithLevel); }
          })
        ]));
        body.appendChild(sCard);

        body.appendChild(h('div.btn-row', { style: { marginBottom: '14px' } }, [
          h('button.btn.btn--ghost', {
            text: '‹ 이전', uid: 'P08-B07', uidLabel: '이전 단계',
            onClick: function () { step = 1; draw(); }
          }),
          h('button.btn', {
            text: '플랜 보기', uid: 'P08-B09', uidLabel: '플랜 보기',
            onClick: function () { A.go('P07'); }
          })
        ]));
      }

      /* ---------------------------------------------------------------- */
      /* C05 지난 체크인 · C06 정직성 안내                                    */
      /* ---------------------------------------------------------------- */
      function pastCard() {
        var list = (S.get().checkins || []).slice().sort(function (a, b) {
          return new Date(b.at) - new Date(a.at);
        }).slice(0, 5);

        var card = h('div.card', { uid: 'P08-C05', uidLabel: '지난 체크인 목록' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '지난 체크인' }),
          h('div.card__sub', { text: '최근 5건' })
        ]));

        if (!list.length) {
          card.appendChild(h('div.empty', { uid: 'P08-S03', uidLabel: '체크인 기록 없음 빈 상태' }, [
            h('div.empty__ico', { text: '🗒' }),
            h('div.empty__t', { text: '아직 체크인 기록이 없습니다' }),
            h('div.empty__d', { text: '주 1회 같은 조건으로 기록하면 그때부터 추세가 보입니다.' })
          ]));
          return card;
        }

        card.appendChild(h('div', { style: { overflowX: 'auto' } }, [
          h('table.table', { uid: 'P08-L01', uidLabel: '지난 체크인 표' }, [
            h('thead', [h('tr', [
              h('th', { text: '날짜' }),
              h('th.num', { text: '체중' }),
              h('th.num', { text: '이행률' })
            ])]),
            h('tbody', list.map(function (c) {
              return h('tr', [
                h('td', { text: UI.dateShort(c.at) + ' · ' + condLabel(c.condition) }),
                h('td.num', { text: c.weightKg != null ? UI.n1(c.weightKg) + 'kg' : '—' }),
                h('td.num', { text: '운동 ' + UI.n0(c.workoutPct) + '% · 식단 ' + UI.n0(c.dietPct) + '%' })
              ]);
            }))
          ])
        ]));
        return card;
      }

      function honestyCard() {
        var list = (S.get().checkins || []).slice().sort(function (a, b) {
          return new Date(a.at) - new Date(b.at);
        }).filter(function (c) { return c.weightKg != null; });

        var card = h('div.card.card--flat', { uid: 'P08-C06', uidLabel: '체중 해석 안내' });
        card.appendChild(h('div.card__title', { text: '숫자 한 번으로 판단하지 마세요' }));
        card.appendChild(UI.plainNote({
          uid: 'P08-C07', label: '체중 해석',
          text: '체중은 하루 사이에도 ±1kg 흔들립니다. 주 평균의 방향으로 보세요.',
          evidence: '전날 짜게 먹었거나 탄수화물을 몰아 먹었거나 잠이 모자랐으면, ' +
                    '체지방이 전혀 늘지 않아도 숫자는 올라갑니다.\n\n' +
                    '앱의 판단 기준 — 이번 주 평균과 지난 주 평균을 비교해서, ' +
                    '2주 연속 같은 방향으로 벗어날 때만 계획을 건드립니다. ' +
                    '체지방과 골격근이 실제로 어떻게 움직였는지는 인바디로만 확인됩니다.'
        }));

        if (list.length >= 2) {
          var recent = list.slice(-3), prior = list.slice(-6, -3);
          var ra = avg(recent.map(function (c) { return c.weightKg; }));
          card.appendChild(h('div.kv', [
            h('span.kv__k', { text: '최근 ' + recent.length + '회 평균' }),
            h('span.kv__v', { text: UI.n1(ra) + ' kg' })
          ]));
          if (prior.length) {
            var pa = avg(prior.map(function (c) { return c.weightKg; }));
            card.appendChild(h('div.kv', [
              h('span.kv__k', { text: '그 이전 ' + prior.length + '회 평균 대비' }),
              h('span.kv__v', { text: UI.sign(ra - pa) + ' kg' })
            ]));
          }
        }
        return card;
      }

      /* ---------------------------------------------------------------- */
      /* 동작                                                               */
      /* ---------------------------------------------------------------- */
      function saveCheckin() {
        var list = (S.get().checkins || []).slice();
        var entry = {
          at: savedAt || new Date().toISOString(),
          weightKg: draft.weightKg,
          workoutPct: draft.workoutPct,
          dietPct: draft.dietPct,
          condition: draft.condition,
          memo: draft.memo
        };
        var idx = -1;
        for (var i = 0; i < list.length; i++) { if (list[i].at === entry.at) { idx = i; break; } }
        if (idx >= 0) list[idx] = entry; else list.push(entry);
        savedAt = entry.at;
        S.set({ checkins: list });
      }

      /** 실측 점: 플랜 시작 이후의 인바디 + 체크인 기록 (같은 주차는 뒤엣것으로 덮는다) */
      function actualPoints(plan2) {
        var start = plan2.startDate;
        var map = {}, keys = [];
        function put(wk, y) {
          var k = wk.toFixed(1);
          if (map[k] == null) keys.push(k);
          map[k] = { x: parseFloat(k), y: y };
        }
        var scans = S.sortedScans(), i;
        var seen = 0;
        for (i = 0; i < scans.length; i++) {
          var wk = weeksBetween(start, scans[i].measuredAt);
          if (wk >= -0.2) { put(Math.max(0, wk), scans[i].weightKg); seen++; }
        }
        // 플랜 시작 이후 인바디가 아직 없으면, 플랜의 기준이 된 직전 인바디를 0주차 점으로 쓴다
        if (!seen && scans.length) put(0, scans[scans.length - 1].weightKg);

        var cs = (S.get().checkins || []);
        for (i = 0; i < cs.length; i++) {
          if (cs[i].weightKg == null) continue;
          var cw = weeksBetween(start, cs[i].at);
          if (cw >= -0.2) put(Math.max(0, cw), cs[i].weightKg);
        }
        return keys.map(function (k) { return map[k]; }).sort(function (a, b) { return a.x - b.x; });
      }

      function prevActualWeight(plan2) {
        var cs = (S.get().checkins || []).filter(function (c) {
          return c.weightKg != null && c.at !== savedAt;
        }).sort(function (a, b) { return new Date(b.at) - new Date(a.at); });
        if (cs.length) return cs[0].weightKg;
        if (scan) return scan.weightKg;
        return plan2.trajectory && plan2.trajectory.length ? plan2.trajectory[0].weightKg : null;
      }

      function rebuildWithLevel(level) {
        var st2 = S.get(), sc = S.latestScan();
        var prof = st2.profile || global.MB_DATA.SEED_PROFILE;
        if (!sc || !st2.goal) {
          global.MB_UID.toast('목표와 측정 기록이 있어야 다시 만들 수 있습니다');
          return;
        }
        var cmp = E.compareLevels(sc, prof, st2.goal, todayISO(), st2.goal.deadlineWeeks || null);
        var np = E.buildPlan(cmp, level, sc, prof);
        if (!np) { global.MB_UID.toast('그 강도로는 목표에 도달하는 계획이 나오지 않습니다'); return; }
        S.setPlan(np);
        global.MB_UID.toast('강도 ' + np.label + ' 플랜으로 바꿨습니다 · 목표일 ' + UI.dateK(np.targetDate));
        A.refresh();
      }
    }
  });

  /* =======================================================================
   * 순수 헬퍼
   * ==================================================================== */

  /** 제안 적용 — 칼로리만 ±150kcal 움직이고, 느릴 때는 유산소를 먼저 늘린다 */
  function applyAdvice(plan, advice) {
    var delta = advice.status === 'slow' ? -150 : (advice.status === 'fast' ? 150 : 0);
    var m = plan.macros;
    if (delta !== 0 && m) {
      m.intakeKcal = Math.round(m.intakeKcal + delta);
      m.carbG = Math.max(50, Math.round(m.carbG + delta / 4));
      if (m.deficitKcal != null) m.deficitKcal = Math.round(m.deficitKcal - delta);
      if (m.intakeKcal > 0) {
        m.pctProtein = Math.round(m.proteinG * 4 / m.intakeKcal * 100);
        m.pctFat = Math.round(m.fatG * 9 / m.intakeKcal * 100);
        m.pctCarb = Math.max(0, 100 - m.pctProtein - m.pctFat);
      }
    }
    if (advice.status === 'slow' && plan.workout) {
      plan.workout.cardioMinPerWeek = (plan.workout.cardioMinPerWeek || 0) + 40;
    }
    return delta;
  }

  /** 이번 주 입력값만으로 본 상태 (계획이 감량이면 예상보다 무거울 때 '느림') */
  function measuredStatus(plan, expected, actualW) {
    var g = actualW - expected;
    if (Math.abs(g) < 0.15) return 'onTrack';
    var traj = plan.trajectory || [];
    var cutting = traj.length > 1 ? traj[traj.length - 1].weightKg < traj[0].weightKg : true;
    if (cutting) return g > 0 ? 'slow' : 'fast';
    return g < 0 ? 'slow' : 'fast';
  }

  function statBox(label, val, unit) {
    return h('div.stat', [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(val) }), h('span.stat__u', { text: unit })]),
      h('div.stat__d', { text: ' ' })
    ]);
  }

  function statusLabel(s) {
    return ({ onTrack: '예상 범위', slow: '예상보다 느림', fast: '예상보다 빠름',
              adherence: '실행이 먼저' })[s] || '판정';
  }
  function statusBadgeClass(s) {
    return ({ onTrack: 'badge--ok', slow: 'badge--warn', fast: 'badge--warn',
              adherence: 'badge--bad' })[s] || 'badge--accent';
  }
  function statusDesc(s) {
    return ({
      onTrack: '계획대로 가고 있습니다. 이번 주는 바꿀 이유가 없습니다.',
      slow: '계획보다 덜 움직였습니다. 다만 1주 결과만으로 바꾸면 과잉 반응입니다.',
      fast: '계획보다 빠릅니다. 빠른 감량은 근손실 위험을 같이 올립니다.',
      adherence: '계획이 틀린 게 아니라 실행이 덜 된 주입니다. 숫자를 건드릴 단계가 아닙니다.'
    })[s] || '';
  }
  function dietHint(key) {
    return ({
      high: '계획 칼로리 기준 약 90% 수준으로 봅니다.',
      mid: '계획 칼로리 기준 약 70% 수준으로 봅니다. 70% 미만이면 엔진은 칼로리를 더 줄이지 않습니다.',
      low: '약 45%로 봅니다. 이 경우 계획 수정보다 실행 복구가 먼저입니다.'
    })[key] || '';
  }
  function condLabel(key) {
    return ({ good: '좋음', normal: '보통', bad: '나쁨' })[key] || '—';
  }
  function sessionsText(days, pct) {
    return '계획 주 ' + days + '회 중 약 ' + Math.round(days * pct / 100) + '회 수행';
  }

  function toDate(iso) {
    return new Date(String(iso).length <= 10 ? iso + 'T00:00:00' : iso);
  }
  function weeksBetween(aISO, bISO) {
    return (toDate(bISO) - toDate(aISO)) / 604800000;
  }
  function weeksElapsed(startISO) {
    return (new Date().getTime() - toDate(startISO).getTime()) / 604800000;
  }
  function agoText(iso) {
    var d = daysSince(iso);
    return d === 0 ? '오늘' : d + '일 전';
  }
  function daysSince(iso) {
    return Math.max(0, Math.floor((new Date().getTime() - toDate(iso).getTime()) / 86400000));
  }
  function todayISO() { return E.toISODate(new Date()); }

  function snapshotAt(plan, wk) {
    var traj = plan.trajectory || [];
    if (!traj.length) return null;
    var best = traj[0];
    for (var i = 0; i < traj.length; i++) {
      if (traj[i].week === wk) return traj[i];
      if (Math.abs(traj[i].week - wk) < Math.abs(best.week - wk)) best = traj[i];
    }
    return best;
  }

  function lastMeasureISO(st, scan) {
    var out = scan ? scan.measuredAt : null;
    (st.checkins || []).forEach(function (c) {
      if (!out || new Date(c.at) > toDate(out)) out = c.at;
    });
    return out;
  }

  function avg(arr) {
    if (!arr.length) return null;
    var s = 0;
    for (var i = 0; i < arr.length; i++) s += arr[i];
    return s / arr.length;
  }
})(window);
