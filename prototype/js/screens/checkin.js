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
            var bad = weightProblem(draft.weightKg);
            if (bad) { global.MB_UID.toast(bad); return; }
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

      /* 넣은 체중이 말이 되는가 — 862 처럼 소수점을 빠뜨린 값이 기준점으로 한 번
         들어가면 그 뒤 판정이 전부 틀어집니다. 마지막 체크인(없으면 최근 인바디)에서
         15% 넘게 다르면 막습니다. 앱(checkins.dart)과 같은 규칙. */
      function weightProblem(w) {
        if (w == null) return null;
        if (w < 20 || w > 300) return '20~300kg 사이로 넣어 주세요';
        var ref = null;
        var cs = (S.get().checkins || []).filter(function (c) {
          return typeof c.weightKg === 'number' && c.at !== savedAt;
        }).sort(function (a, b) { return String(a.at) < String(b.at) ? -1 : 1; });
        if (cs.length) ref = cs[cs.length - 1].weightKg;
        else if (scan && scan.weightKg > 0) ref = scan.weightKg;
        if (!(ref > 0)) return null;
        if (Math.abs(w - ref) / ref > 0.15) {
          return '지난 기록(' + UI.n1(ref) + 'kg)과 15% 넘게 다릅니다 — 숫자를 확인해 주세요';
        }
        return null;
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
        /* 주차는 엔진과 같은 규칙으로(계획 시작일부터 7일마다, 내림). 예전엔
           반올림이라 3.5일째부터 다음 주로 넘어갔습니다. */
        var dayIdx = E.planDayOf(plan.startDate, S.dayKey());
        var wkIdx = Math.floor(dayIdx / 7);
        var snap = snapshotAt(plan, wkIdx);
        /* 계획선은 판정과 같은 자리(오늘)에서 읽습니다 — 주 사이를 이어서. */
        var expected = E.planWeightAt(plan, dayIdx);
        if (expected == null) expected = draft.weightKg;
        var actualW = draft.weightKg;
        var prevW = prevActualWeight(plan);

        /* 판정 — 이번 계획의 체크인 전부(방금 저장한 것 포함). 첫 체크인(또는
           마지막 조정)을 기준점으로, 그 뒤 변화량을 계획선과 견줍니다.
           예전엔 이번 주 값 하나를 계획선에 대고 0.15kg 만 달라도 판정했습니다. */
        var review = E.checkinReview(plan, readingsFor(plan), { dietPct: draft.dietPct });
        var dev = review.devKg;
        var profileNow = S.get().profile || global.MB_DATA.SEED_PROFILE;
        var preview = review.apply ? E.applyCheckinAdvice(plan, review, profileNow, wkIdx, 'preview') : null;
        var canApply = !!(preview && (preview.kcalDelta !== 0 || preview.cardioMinDelta !== 0));
        function previewText(res) {
          if (!res) return '';
          var parts = [];
          if (res.kcalDelta !== 0) {
            parts.push('하루 ' + UI.n0(plan.macros.intakeKcal) + ' → ' + UI.n0(res.plan.macros.intakeKcal) + 'kcal');
          }
          if (res.cardioMinDelta) {
            var c0 = (plan.workout && plan.workout.cardioMinPerWeek) || 0;
            parts.push('유산소 주 ' + UI.n0(c0) + ' → ' + UI.n0(c0 + res.cardioMinDelta) + '분');
          }
          if (res.floored) {
            parts.push(res.kcalDelta === 0 ? '칼로리는 이미 하루 하한이라 더 줄이지 않습니다'
                                           : '하한 때문에 ' + UI.n0(Math.abs(res.kcalDelta)) + 'kcal 만 줄입니다');
          }
          return parts.join(' · ');
        }

        /* --- C03 예상 vs 실제 --- */
        var card = h('div.card', { uid: 'P08-C03', uidLabel: '3단계 · 예상 vs 실제 비교' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: wkIdx + '주차 · 예상 vs 실제' }),
          h('div.card__sub', { text: UI.dateK(plan.startDate) + ' 시작 기준' })
        ]));
        card.appendChild(h('div.stats', [
          statBox('계획선(오늘)', expected, 'kg'),
          statBox('실제 체중', actualW, 'kg'),
          /* devKg 는 + 가 "계획보다 무거움" 입니다(증량 계획이어도 뒤집지 않음).
             느림 · 빠름은 단계에 따라 뜻이 달라서 아래 판정 이름이 말합니다. */
          h('div.stat' + (/^(slow|fast|heavy|light)$/.test(review.status) ? '.stat--fat' : ''), [
            h('div.stat__k', { text: '기준 대비 계획선과의 차이' }),
            h('div', [h('span.stat__v', { text: dev == null ? '—' : UI.sign(dev) }), h('span.stat__u', { text: 'kg' })]),
            h('div.stat__d', { text: statDesc(review) })
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
        card.appendChild(h('div.field__hint', {
          text: '집 체중계는 인바디와 0.5~1kg 다를 수 있어서, 판정은 계획선과의 거리가 아니라 ' +
                '기준 체크인 이후 그 거리가 얼마나 움직였는지로 합니다.' }));
        body.appendChild(card);

        /* --- C04 제안 --- */
        var sCard = h('div.card.card--accent', { uid: 'P08-C04', uidLabel: '조정 제안 카드' });
        sCard.appendChild(h('div.card__head', [
          h('div.card__title', { text: '이번 주 제안' }),
          h('span.badge.' + statusBadgeClass(review.status), { text: statusLabel(review.status) })
        ]));
        sCard.appendChild(h('div.card__sub', { text: statusDesc(review.status) }));
        sCard.appendChild(h('div', { style: { marginTop: '10px' } },
          (review.suggestions || []).map(function (s) {
            return h('div.radio-card', { style: { marginBottom: '6px' } }, [
              h('div', [
                h('div.radio-card__t', { text: s.title }),
                h('div.radio-card__d', { text: s.detail })
              ])
            ]);
          })));

        if (preview && previewText(preview)) {
          sCard.appendChild(h('div.note', { uid: 'P08-S06', uidLabel: '적용하면 바뀌는 것',
            text: '적용하면 — ' + previewText(preview) }));
        }

        if (draft.condition === 'bad') {
          sCard.appendChild(h('div.note', { uid: 'P08-S04', uidLabel: '컨디션 나쁨 해석 안내',
            text: '컨디션을 "나쁨"으로 적었습니다. 수면이 부족한 주에는 코르티솔·수분 때문에 체중이 0.5~1kg ' +
                  '더 나올 수 있습니다. 이번 주 숫자만 보고 칼로리를 더 줄이지 마세요.' }));
        }

        sCard.appendChild(h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
          /* 「제안 적용」은 두 번 연속 같은 쪽으로 벗어났을 때(review.apply)만,
             그리고 실제로 바뀌는 것이 있을 때만. 누르기 전에 바뀌는 숫자를 보여 줍니다 —
             하한에 막히면 −150 이 아니고, 운동 계획이 없으면 유산소는 안 더해집니다. */
          canApply ? h('button.btn.btn--primary.btn--block', {
            text: '제안 적용', uid: 'P08-B03', uidLabel: '제안 적용',
            onClick: function () {
              global.MB_MODALS.adjust(review, function () {
                /* 조정 기록의 시각 = 방금 저장한 체크인의 시각. 엔진이 그 체크인을
                   새 기준점으로 잡아, 다음 주에 같은 차이로 또 줄이라고 하지 않습니다. */
                var res = E.applyCheckinAdvice(plan, review, profileNow, wkIdx,
                                               savedAt || new Date().toISOString());
                if (!res) { global.MB_UID.toast('바꿀 수치가 없어 계획을 그대로 두었습니다'); return; }
                S.setPlan(res.plan);
                markApplied();
                global.MB_UID.toast('플랜이 갱신되었습니다 · ' + previewText(res));
                A.refresh();
              }, previewText(preview));
            }
          }) : null,
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
          text: '체중은 하루 사이에도 ±1kg 흔들립니다. 한 번의 숫자가 아니라 흐름으로 보세요.',
          evidence: '전날 짜게 먹었거나 탄수화물을 몰아 먹었거나 잠이 모자랐으면, ' +
                    '체지방이 전혀 늘지 않아도 숫자는 올라갑니다.\n\n' +
                    '앱의 판단 기준 — 한 주에 여러 번 넣으면 그 주의 마지막 값을 씁니다. ' +
                    '체크인마다 그날 자리의 계획선과의 차이를 구하고, 그 차이가 앞선 체크인들의 ' +
                    '평균(기준)에서 0.5kg 넘게, 두 번 연속 같은 쪽으로 움직였을 때만 계획을 건드립니다. ' +
                    '기준이 체크인 하나뿐이면 그날의 흔들림일 수 있어 한 번 더 봅니다. ' +
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
        /* 같은 체크인을 다시 저장하면 **합칩니다** — 새로 쓰면 「조정함」 표시가
           지워져, 계획을 바꾼 근거가 된 체크인이 무엇인지 잃습니다. */
        if (idx >= 0) list[idx] = Object.assign({}, list[idx], entry); else list.push(entry);
        savedAt = entry.at;
        S.set({ checkins: list });
      }

      /** 판정에 넣을 체크인 — 이번 계획 시작일 이후 것만, 주차는 엔진 규칙으로. */
      function readingsFor(plan2) {
        var start = String(plan2.startDate || '');
        return (S.get().checkins || []).slice().sort(function (a, b) {
          return String(a.at) < String(b.at) ? -1 : (String(a.at) > String(b.at) ? 1 : 0);
        }).filter(function (c) {
          return S.dayKey(c.at) >= start;
        }).map(function (c) {
          var k = S.dayKey(c.at);
          return { week: E.planWeekOf(plan2.startDate, k), day: E.planDayOf(plan2.startDate, k),
                   weightKg: c.weightKg, at: c.at };
        });
      }

      /** 방금 저장한 체크인에 "조정함" 을 남깁니다 (지난 체크인 표가 보여 줍니다). */
      function markApplied() {
        var list = (S.get().checkins || []).slice();
        for (var i = 0; i < list.length; i++) {
          if (list[i].at === savedAt) { list[i] = Object.assign({}, list[i], { applied: true }); }
        }
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

  function statBox(label, val, unit) {
    return h('div.stat', [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(val) }), h('span.stat__u', { text: unit })]),
      h('div.stat__d', { text: ' ' })
    ]);
  }

  function statusLabel(s) {
    return ({ early: '기준 잡음', onTrack: '계획대로', watch: '지켜보는 중',
              slow: '두 번 연속 느림', fast: '두 번 연속 빠름',
              heavy: '두 번 연속 무거움', light: '두 번 연속 가벼움', adherence: '실행이 먼저' })[s] || '판정';
  }
  function statusBadgeClass(s) {
    return ({ onTrack: 'badge--ok', slow: 'badge--warn', fast: 'badge--warn',
              heavy: 'badge--warn', light: 'badge--warn', adherence: 'badge--bad' })[s] || 'badge--accent';
  }
  function statusDesc(s) {
    return ({
      early: '첫 체크인(또는 조정 직후)이라 판정하지 않습니다. 이 값이 다음 비교의 기준점입니다.',
      onTrack: '기준 체크인 이후 계획선과의 차이가 0.5kg 안입니다. 이번 주는 바꿀 이유가 없습니다.',
      watch: '벗어났지만 한 번뿐이거나 기준이 체크인 하나뿐입니다. 체중은 하루에도 ±1kg 흔들려서 한 번 더 보고 정합니다.',
      slow: '두 번 연속 계획보다 느립니다. 이제는 흔들림이 아니라 추세로 봅니다.',
      fast: '두 번 연속 계획보다 빠릅니다. 너무 빠르면 근손실(증량이면 지방) 위험이 올라갑니다.',
      heavy: '유지 기간인데 두 번 연속 계획보다 무겁습니다.',
      light: '유지 기간인데 두 번 연속 계획보다 가볍습니다.',
      adherence: '계획이 틀린 게 아니라 실행이 덜 된 주입니다. 숫자를 건드릴 단계가 아닙니다.'
    })[s] || '';
  }
  /** 「기준 대비 차이」 칸의 한 줄 — 값이 없는 이유를 판정에 맞게 말합니다. */
  function statDesc(review) {
    var d = review.devKg;
    if (review.status === 'adherence') return '식단 먼저 — 체중 판정 보류';
    if (review.status === 'early') return review.since ? '조정 뒤 새 기준점' : '첫 체크인 — 기준점';
    if (d == null) return '판정 없음';
    if (Math.abs(d) < 0.5) return '흔들림 범위(±0.5)';
    return (d > 0 ? '계획보다 무거움' : '계획보다 가벼움') +
           (review.status === 'watch' ? ' · 지켜봄' : '');
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
