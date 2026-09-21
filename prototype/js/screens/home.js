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
          global.MB_BUILD.tools ? h('div', { style: { marginTop: '10px' } }, [
            h('button.btn.btn--ghost.btn--sm', { text: '내 실제 데이터로 채우기 (프로토타입)',
              uid: 'P02-B02', uidLabel: '시드 데이터 주입',
              onClick: function () { S.seed(); global.MB_UID.toast('실제 인바디 3건을 불러왔습니다'); A.refresh(); } })
          ]) : null
        ]));
        /* 인바디가 없어도 운동 일정은 쓸 수 있습니다. 체중을 모른다고
           월요일에 헬스 가기로 못 정할 이유가 없습니다. */
        wrap.appendChild(weekCard());
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

        /* 목표가 시작과 같으면(유지 목표, 또는 근육만 늘리는 목표) 갈 거리가
           0 입니다. 나누면 NaN 이 되고, clamp 도 NaN 을 그대로 통과시켜서
           도넛에 "NaN%" 가 찍혔습니다. 갈 거리가 없으면 이미 도착한
           것이므로 100 입니다. */
        /* 갈 거리가 없는 축은 평균에서 빼고, 100 으로 채우지 않습니다.
         *
         * 예전엔 "이미 도착했으니 100" 으로 뒀습니다. 그런데 제일 흔한
         * 목표가 "체지방은 빼고 근육은 유지" 입니다 — 근육 축은 갈
         * 거리가 0 이라 자동으로 100 이 되고, 평균이 (0 + 100) / 2 = 50
         * 에서 시작합니다. 하루도 안 지났고 1kg 도 안 뺐는데 큰 고리가
         * 50% 를 가리킵니다. 절대 50 밑으로도 안 내려갑니다.
         *
         * 같은 순간에 추이 화면은 "달성 0%", 친구에게 나가는 스냅샷도
         * progressPct 0 입니다. 한 앱이 같은 질문에 세 가지로 답하는데,
         * 제일 자주 보는 자리가 제일 후한 답을 하고 있었습니다.
         *
         * 이제 실제로 갈 거리가 있는 축만 셉니다. 셀 축이 하나도 없으면
         * (순수 유지 목표) 그때만 100 입니다 — 그건 참입니다. */
        var startBfm = plan.trajectory[0].bfmKg, targetBfm = st.goal.bfmKg;
        var fatSpan = startBfm - targetBfm;
        var startSmm = plan.trajectory[0].smmKg, targetSmm = st.goal.smmKg;
        var smmSpan = targetSmm - startSmm;

        var axes = [];
        if (Math.abs(fatSpan) >= 0.05) axes.push(clamp((startBfm - d.bfmKg) / fatSpan * 100));
        if (smmSpan > 0.05) axes.push(clamp((d.smmKg - startSmm) / smmSpan * 100));

        var doneFat = Math.abs(fatSpan) < 0.05 ? 100 : clamp((startBfm - d.bfmKg) / fatSpan * 100);
        var doneSmm = smmSpan > 0.05 ? clamp((d.smmKg - startSmm) / smmSpan * 100) : 100;
        var overall = axes.length
          ? Math.round(axes.reduce(function (a, b) { return a + b; }, 0) / axes.length)
          : 100;

        var card = h('div.card.card--accent', { uid: 'P02-C02', uidLabel: '목표 진행 카드' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '목표까지' }),
          h('div', { style: { display: 'flex', gap: '4px' } }, [
            plan.mode ? h('span.badge', { text: plan.mode.nameKo }) : null,
            h('span.badge.badge--accent', { text: plan.label + ' 강도' })
          ])
        ]));

        /* 기간 탭. 측정이 없거나 계획 시작 전이면 탭 자체를 안 만듭니다 —
           누를 때마다 "측정이 없습니다"만 나오는 탭은 없느니만 못합니다. */
        var GSCOPES = [
          { key: 'all',   label: '전체',   uid: 'P02-B17' },
          { key: 'week',  label: '이번주', uid: 'P02-B18' },
          { key: 'month', label: '이번달', uid: 'P02-B19' }
        ];
        var gscope = 'all';
        var gbody = h('div');
        var showTabs = scans.length >= 1 && plan.trajectory && plan.trajectory.length > 1;
        var gtabs = showTabs
          ? scopeTabs(GSCOPES, gscope, function (k) { gscope = k; drawGoal(); }, '목표')
          : null;
        if (gtabs) { gtabs.style.marginBottom = '4px'; card.appendChild(gtabs); }

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
            h('div.muted', { text: UI.dateK(projected) + ' 도착 예정' }),
            (function () {
              var sp = arrivalSpread(plan);
              return sp ? h('div.muted', { style: { fontSize: '11px', marginTop: '2px' },
                text: '인바디 오차만으로도 ±' + sp + '주쯤 움직이는 날짜입니다' }) : null;
            })()
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
        card.appendChild(gbody);
        card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
          h('button.btn.btn--sm', { text: '플랜 보기', uid: 'P02-B03', uidLabel: '플랜 보기',
            onClick: function () { A.go('P07'); } }),
          h('button.btn.btn--sm', { text: '목표 변경', uid: 'P02-B04', uidLabel: '목표 변경',
            onClick: function () { A.go('P05'); } })
        ]));

        var lastScanISO = scans.length ? scans[scans.length - 1].measuredAt : null;
        var dist = distinguishableDay(plan, lastScanISO);

        function drawGoal() {
          gbody.textContent = '';
          if (gscope === 'all') return drawAll();
          if (gscope === 'week') return drawWeek();
          return drawMonth();
        }

        /* --- 전체 --- */
        function drawAll() {
          gbody.appendChild(progressRow('체지방', d.bfmKg, targetBfm, 'kg', doneFat, 'fat'));
          gbody.appendChild(progressRow('골격근', d.smmKg, targetSmm, 'kg', doneSmm, 'muscle'));
        }

        /* --- 기간 보기 ---
           전체와 같은 모양(라벨 / 값→값 / 막대)을 씁니다. 탭마다 생김새가
           달라지면 같은 카드 안에서 화면이 갈아끼워지는 느낌이 됩니다.
           다른 것은 막대가 재는 대상입니다:
             전체   — 목표까지 얼마나 왔나
             기간   — 이 기간의 계획분을 얼마나 채웠나
           그리고 오차 안이면 별표 + 흐리게. 전체 탭의 규칙과 같습니다. */
        function periodRows(win) {
          var DF = diffFloor();
          var segRaw = planSegment(plan, win.fromAt, win.toAt);
          var seg = (segRaw && !segRaw.none) ? segRaw : null;

          [['체지방', 'bfmKg', DF.bfm, 'fat'],
           ['골격근', 'smmKg', DF.smm, 'muscle'],
           ['체중', 'weightKg', DF.weight, 'weight']].forEach(function (row) {
            var got = win.delta[row[1]];
            var want = seg ? Math.round(seg[row[1]] * 10) / 10 : null;
            var under = Math.abs(got) < row[2];

            /* 막대가 재는 것: 이 기간의 계획분을 얼마나 채웠나.
               계획이 이 기간을 안 덮으면 분모 자체가 없어서 비워 둡니다 —
               0%가 아니라 "잴 수 없음"입니다.

               그런데 분모가 있어도 말할 수 없는 경우가 있습니다.
               잰 변화가 인바디 오차보다 작으면, 실제 변화는 got 하나가
               아니라 [got − 문턱, got + 문턱] 어딘가입니다. 계획 −0.9kg
               에 −0.4kg 를 재고 44% 라고 찍으면, 잴 수 없는 것에 숫자를
               붙이는 것입니다. 그 숫자를 보고 사용자는 "덜 했다" 고
               결론짓고 행동을 바꿉니다 — 근거가 없는데도요.

               그래서 이때는 채우지 않고 구간을 빗금으로 표시합니다.
               "이 사이 어딘가" 가 우리가 아는 전부입니다. */
            var pct = null, band = null;
            if (want === null) {
              pct = 0;
            } else if (Math.abs(want) < 0.05) {
              // 계획이 "그대로 두기". 채울 분량이 없으니 오차 안에 머문 것이 달성입니다.
              pct = under ? 100 : 0;
            } else if (under) {
              var lo = clamp((got - row[2]) / want * 100);
              var hi = clamp((got + row[2]) / want * 100);
              band = { lo: Math.min(lo, hi), hi: Math.max(lo, hi) };
            } else {
              pct = Math.round(got / want * 100);
            }

            var bar = h('div.bar.bar--' + row[3] + (band ? '.bar--range' : ''), {
              style: { opacity: want === null ? '.3' : '1' } },
              band
                ? [h('div.bar__band', { style: { left: band.lo + '%',
                    width: Math.max(2, band.hi - band.lo) + '%' } })]
                : [h('div.bar__fill', { style: { width: clamp(pct) + '%' } })]);

            gbody.appendChild(h('div', { style: { marginBottom: '8px' } }, [
              h('div', { style: { display: 'flex', justifyContent: 'space-between',
                                  fontSize: '12px', marginBottom: '4px' } }, [
                h('span', { style: { color: 'var(--text-2)', fontWeight: '600' }, text: row[0] }),
                h('span.num', { style: { fontWeight: '700',
                    color: under ? 'var(--text-3)' : 'inherit' },
                  text: UI.n1(win.from[row[1]]) + 'kg → ' + UI.n1(win.to[row[1]]) + 'kg  ' +
                        '(' + UI.sign(got) + (under ? '*' : '') + ')' })
              ]),
              bar,
              want === null ? null
                : h('div.muted', { style: { fontSize: '11px', marginTop: '2px' },
                    text: Math.abs(want) < 0.05 ? '계획 유지'
                        : ('계획 ' + UI.sign(want) + 'kg' +
                           (band ? ' · 달성률은 이 오차 안에서 정할 수 없습니다' : '')) })
            ]));
          });

          if (!seg) {
            var why = segRaw && segRaw.none;
            gbody.appendChild(h('div.muted', { style: { marginTop: '8px' },
              text: why === 'after'
                ? '이 구간은 계획이 끝난 뒤입니다. 비교할 계획분이 없어 막대를 비워 뒀습니다.'
                : why === 'short'
                ? '이 구간이 계획과 겹치는 기간이 사흘도 안 됩니다. 비교할 계획분이 없습니다.'
                : '이 구간은 계획을 세우기 전입니다. 비교할 계획분이 없어 막대를 비워 뒀습니다.' }));
          } else if (seg.partial) {
            gbody.appendChild(h('div.muted', { style: { marginTop: '8px' },
              text: '잰 구간 ' + seg.windowDays + '일 중 ' + seg.days + '일만 계획과 겹칩니다. ' +
                    '위의 "계획" 은 겹치는 기간의 몫입니다.' }));
          }
          gbody.appendChild(h('div.muted', { style: { marginTop: '8px' },
            text: '별표(*)는 두 측정의 차이가 인바디 오차 안이라는 뜻입니다. ' +
                  '그 항목은 변했는지 아닌지 이 두 번의 측정으로는 알 수 없습니다. ' +
                  '막대의 빗금은 "실제 달성률이 이 사이 어딘가" 라는 뜻입니다.' }));
        }

        /** 기간 머리 — 실제로 잰 구간을 먼저 적습니다. "이번주"라고 적혀 있어도. */
        function periodHead(win) {
          gbody.appendChild(h('div.card__sub', { style: { marginBottom: '8px' },
            text: '잰 구간 ' + UI.dateShort(win.fromAt) + ' → ' + UI.dateShort(win.toAt) +
                  ' · ' + win.spanDays + '일 · 측정 ' + win.inWindow + '회' +
                  (win.usedBefore ? ' (직전 측정과 비교)' : '') }));
        }

        /** 비교할 측정이 없을 때 — 대부분의 주가 여기입니다. */
        function noPair(days) {
          /* 예전 문구는 "그 전 측정과 짝을 지을 수도 없습니다" 였습니다.
             측정이 여러 번 있는데도 그렇게 말했습니다 — 짝지을 수 없는
             게 아니라, 이 기간 안에 잰 것이 없어서 이 기간에 대해 할
             말이 없는 것입니다. 둘은 다릅니다. 앞의 말은 "네 기록으로는
             아무것도 알 수 없다" 로 들리고, 뒤의 말은 "다른 탭에 가면
             있다" 입니다. */
          var n = scans.length;
          gbody.appendChild(h('div.note', { text: n < 2
            ? '비교할 측정이 두 번 필요합니다.'
            : '최근 ' + days + '일 안에 잰 측정이 없습니다.' }));
          gbody.appendChild(h('div.muted', { style: { marginTop: '6px' },
            text: n < 2
              ? '측정이 한 번뿐이라 아직 변화를 말할 수 없습니다.'
              : '기록은 ' + n + '건 있습니다. 지금까지의 변화는 "전체" 에서 볼 수 있습니다.' }));
          if (n >= 2) {
            gbody.appendChild(h('button.btn.btn--sm', {
              text: '전체 보기', style: { marginTop: '8px' },
              uid: 'P02-B22', uidLabel: '전체 탭으로',
              onClick: function () { gscope = 'all'; A.refresh(); }
            }));
          }
          measureBar();
        }

        /** 측정 대기 막대 — 언제 다시 재면 의미가 있는가. */
        function measureBar() {
          if (dist && dist.ended) {
            gbody.appendChild(h('div.muted', { style: { marginTop: '10px' },
              text: '계획한 기간이 끝났습니다. 다시 재고 계획을 새로 세울 때입니다.' }));
            return;
          }
          if (!dist) {
            gbody.appendChild(h('div.muted', { style: { marginTop: '10px' },
              text: '이 구간은 계획상 체지방 변화가 인바디 오차보다 느립니다. ' +
                    '언제부터 구분되는지 날짜로 말할 수 없습니다.' }));
            return;
          }
          var left = dist.daysLeft;
          var pct = Math.max(0, Math.min(100, Math.round((dist.moveDays - left) / dist.moveDays * 100)));
          gbody.appendChild(h('div', { uid: 'P02-G05', uidLabel: '측정 대기',
            style: { marginTop: '12px' } }, [
            h('div.bar', [h('div.bar__fill', { style: { width: pct + '%',
              background: left > 0 ? 'var(--accent)' : 'var(--ok)' } })]),
            h('div.muted', { style: { marginTop: '6px' },
              text: left > 0
                ? UI.dateK(dist.date) + ' 이후에 재면, 그때까지의 변화가 인바디 오차보다 커집니다. ' +
                  '계획대로 갔을 때 기준이고, ' + left + '일 남았습니다.'
                : UI.dateK(dist.date) + '이 지났습니다. 지금 재면 이전 측정과의 차이를 ' +
                  '인바디 오차와 구분해서 읽을 수 있습니다.' })
          ]));
          if (left <= 0) {
            gbody.appendChild(h('button.btn.btn--sm.btn--primary', { text: '지금 재기',
              style: { marginTop: '8px' }, uid: 'P02-B21', uidLabel: '지금 재기',
              onClick: function () { A.go('P03'); } }));
          }
        }

        function drawWeek() {
          var prof2 = st.profile || global.MB_DATA.SEED_PROFILE;
          var win = scansInWindow(scans, 7, prof2);
          if (!win.delta) return noPair(7);
          periodHead(win);
          periodRows(win);
          measureBar();
        }

        function drawMonth() {
          var prof2 = st.profile || global.MB_DATA.SEED_PROFILE;
          var win = scansInWindow(scans, 28, prof2);
          if (!win.delta) return noPair(28);
          periodHead(win);
          periodRows(win);
          measureBar();
        }

        drawGoal();
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

      /* --- C08 이번 주 운동 --- */
      wrap.appendChild(weekCard());

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


  /* --- C08 이번 주 운동 -----------------------------------------------
     홈에 두는 이유: 이 카드가 매일 만지는 유일한 칸입니다. 인바디는
     한 달에 한 번 보고, 이건 하루에 한 번 봅니다.

     칸 하나를 누르면 그 날 무엇을 할지 정하고, 하고 나서 다시 눌러
     체크합니다. 오늘 할 일이 있으면 카드 안에서 바로 체크할 수 있게
     버튼을 따로 냅니다 — 매일 하는 동작을 모달 뒤에 숨기면 안 됩니다. */
  function weekCard() {
    var W = global.MB_SCHED;
    var sum = W.weekSummary();
    var card = h('div.card', { uid: 'P02-C08', uidLabel: '이번 주 운동' });

    card.appendChild(h('div.card__head', [
      h('div.card__title', { text: '이번 주 운동' }),
      h('div.card__sub', { text: sum.plannedDays
        ? sum.keptDays + '/' + sum.plannedDays + '일 완료'
        : '아직 정한 날이 없습니다' })
    ]));

    /* 일곱 칸은 같은 컨트롤이 일곱 번 반복된 것이라 번호를 일곱 개 쓰지
       않고 리스트 번호 하나에 #1..#7 을 답니다 (측정 기록 행과 같은 방식).
       번호를 문자열 그대로 적는 것이 중요합니다 — 'P02-B' + (23+i) 처럼
       만들면 화면에는 뜨지만 레지스트리 생성기가 소스에서 못 읽고,
       번호 재사용을 잡는 그물에서 빠집니다. */
    var strip = h('div.wk', { uid: 'P02-L01', uidLabel: '이번 주 일곱 칸' });
    sum.days.forEach(function (d, i) {
      var cls = '.wk__d' + (d.isToday ? '.is-today' : '') +
                (d.missed ? '.is-missed' : '') +
                (!d.plan.length && !d.isToday ? '.is-rest' : '');
      var marks = h('div.wk__marks');
      W.TYPES.forEach(function (t) {
        if (d.plan.indexOf(t.id) < 0) return;
        marks.appendChild(h('span.wk__m.wk__m--' + t.id + (d.done[t.id] ? '.is-done' : ''),
          { 'aria-label': t.label + (d.done[t.id] ? ' 완료' : ' 예정') }));
      });
      strip.appendChild(h('button' + cls, {
        uid: 'P02-L02#' + (i + 1), uidLabel: '요일 칸 ' + d.dow,
        'aria-label': (d.dayNum) + '일 ' + d.dow + '요일, ' +
          (d.plan.length ? d.plan.map(W.labelOf).join(' ') +
            (d.kept ? ' 완료' : (d.missed ? ' 안 함' : ' 예정')) : '쉬는 날'),
        onClick: function () { dayModal(d.key); }
      }, [
        h('div.wk__dow', { text: d.dow }),
        h('div.wk__num', { text: String(d.dayNum) }),
        marks
      ]));
    });
    card.appendChild(strip);

    /* 플랜이 이미 요일 배치를 들고 있으면 한 번에 깔아 줍니다.
       목표를 정할 때 "주 4회, 상하체 4분할" 을 이미 골랐는데 그걸 또
       손으로 옮겨 적게 하는 건 같은 질문을 두 번 하는 것입니다. */
    var fill = fillFromPlan(sum);
    if (fill) card.appendChild(fill);
    var cnote = cardioNote(sum);
    if (cnote) card.appendChild(cnote);

    /* 오늘 줄 — 카드 안에서 바로 체크 */
    var today = null;
    sum.days.forEach(function (d) { if (d.isToday) today = d; });
    var row = h('div', { style: { marginTop: '12px' } });
    if (!today || !today.plan.length) {
      row.appendChild(h('div.muted', { text: '오늘은 정해 둔 운동이 없습니다. 칸을 눌러서 정하세요.' }));
    } else {
      var left = today.plan.filter(function (t) { return !today.done[t]; });
      if (!left.length) {
        row.appendChild(h('div.note.note--ok', { style: { marginBottom: 0 },
          text: '오늘 할 것 다 했습니다 — ' + today.plan.map(W.labelOf).join(' · ') }));
      } else {
        row.appendChild(h('div.btn-row', left.map(function (t, i) {
          return h('button.btn.btn--primary.btn--sm', {
            text: W.typeOf(t).icon + ' ' + W.labelOf(t) + ' 했어요',
            uid: 'P02-B23#' + (W.indexOf(t) + 1), uidLabel: '오늘 ' + W.labelOf(t) + ' 체크',
            onClick: function () {
              S.setScheduleDone(today.key, t, true);
              global.MB_UID.toast(W.labelOf(t) + ' 체크했습니다');
              A.refresh();
            }
          });
        })));
      }
    }
    card.appendChild(row);

    /* 스트릭 — 행동에만 답니다. 몸무게에는 절대 달지 않습니다.
       설정에서 숨길 수 있습니다 (연속 숫자가 부담인 사람을 위해). */
    if (!(S.get().settings || {}).hideStreaks) card.appendChild(streakRow());
    return card;
  }

  /**
   * "플랜대로 채우기" — 엔진이 만든 주간 분할을 이번 주 칸에 깔아 줍니다.
   *
   * 두 가지를 지킵니다.
   *   (가) 이미 정해 둔 날은 건드리지 않습니다. 엔진의 배치는 제안이고,
   *        사람이 고른 것이 언제나 이깁니다.
   *   (나) **지나간 날은 채우지 않습니다.** 금요일에 눌렀는데 월·수가
   *        헬스로 채워지면, 안 간 날이 그 자리에서 "못 지킨 날" 이 됩니다.
   *        하지도 않은 실패를 앱이 만들어 주는 셈입니다. 오늘부터 채웁니다.
   *
   * 유산소는 안 채웁니다. 엔진에는 요일 개념이 없고 주당 분(分)만 있습니다
   * (cardioMinPerWeek). 없는 정보를 있는 척 배치하지 않습니다.
   */
  function fillFromPlan(sum) {
    var st = S.get();
    var w = st.plan && st.plan.workout;
    if (!w || !w.sessions || w.sessions.length !== 7) return null;

    var today = S.dayKey();
    var targets = [];
    sum.days.forEach(function (d, i) {
      if (d.key < today) return;                 // 지나간 날은 건드리지 않습니다
      if (d.plan.length) return;                 // 이미 정해 둔 날도
      var sess = w.sessions[i];
      if (!sess || sess.rest) return;
      targets.push({ key: d.key, label: sess.label });
    });
    if (!targets.length) return null;

    var box = h('div', { style: { marginTop: '10px' } }, [
      h('button.btn.btn--sm.btn--block', {
        text: '플랜대로 채우기 (' + w.splitName + ' · 남은 ' + targets.length + '일)',
        uid: 'P02-B32', uidLabel: '플랜대로 채우기',
        onClick: function () {
          targets.forEach(function (t) { S.setSchedulePlan(t.key, 'gym', true); });
          global.MB_UID.toast(targets.length + '일을 헬스로 채웠습니다');
          A.refresh();
        } }),
      h('div.muted', { style: { marginTop: '5px' },
        text: '오늘부터 채웁니다. 이미 정한 날은 그대로 둡니다.' })
    ]);
    return box;
  }

  /* 유산소 안내는 채우기 버튼과 따로 둡니다.
     예전엔 버튼 밑에 붙어 있었는데, 누르는 순간 버튼이 사라지면서
     설명도 같이 사라졌습니다 — 하필 "유산소는 왜 안 채워졌지?" 가
     생기는 바로 그 순간에 답이 없어집니다. */
  function cardioNote(sum) {
    var w = (S.get().plan || {}).workout;
    if (!w || !(w.cardioMinPerWeek > 0)) return null;
    var hasCardio = sum.days.some(function (d) { return d.plan.indexOf('cardio') >= 0; });
    if (hasCardio) return null;
    return h('div.muted', { style: { marginTop: '8px' },
      text: '유산소는 플랜에 주 ' + w.cardioMinPerWeek + '분만 있고 요일이 없습니다. ' +
            '직접 고르셔야 합니다 (' + (w.cardioPlan || '') + ').' });
  }

  /* --- C09 스트릭 ------------------------------------------------------
     0 일 때 "0일째"를 빨갛게 띄우지 않습니다. 홈 화면에서 매일 보는 0 은
     독려가 아니라 매일 듣는 잔소리이고, 이 앱이 피하려는 학습된 무력감을
     정확히 그렇게 만듭니다. 0 일 때는 앞을 봅니다 — "오늘부터 다시".

     그리고 스트릭은 행동에만 답니다. 체중·골격근·체지방에는 달지 않습니다.
     저울의 떨림으로 연속 기록을 만들면 그건 미신입니다. */
  function streakRow() {
    var W = global.MB_SCHED;
    var w = W.workoutStreak(), f = W.foodStreak();
    var box = h('div.streaks', { uid: 'P02-C09', uidLabel: '스트릭' });

    function cell(icon, name, st, cold, opts) {
      opts = opts || {};
      var val, sub, warm = st.days > 0 && !opts.stale;

      if (!st.days) { val = '—'; sub = opts.extra || cold; }
      else if (opts.stale) {
        /* 오래된 기록을 현재형으로 말하지 않습니다.
           "3일 연속" 이라고 써 놓고 마지막이 40일 전이면 그건 거짓말입니다.
           숫자는 지우지 않습니다 — 지우면 "네 기록은 없다" 가 되는데,
           있었고 지금 안 세는 중인 것이 사실입니다. */
        val = '지난 기록 ' + st.days + '일';
        sub = opts.staleSub;
      } else if (st.days === 1) {
        /* "1일 연속" 은 말도 이상하고, 다음 날 0 으로 떨어지는 낙차를
           매일 만듭니다. 하루는 연속이 아니라 그냥 지킨 하루입니다. */
        val = '오늘 지킴';
        sub = name;
      } else {
        val = st.days + '일 연속';
        sub = name + (st.openToday ? ' · 오늘 남음' : '');
      }
      if (opts.extra && st.days) sub += ' · ' + opts.extra;

      return h('div.streak' + (warm ? '.is-on' : ''), [
        h('div.streak__ico', { text: icon }),
        h('div.streak__body', [
          h('div.streak__v', { text: val }),
          h('div.streak__k', { text: sub, title: sub })
        ])
      ]);
    }
    box.appendChild(cell('\uD83C\uDFCB\uFE0F', '운동', w,
      w.everPlanned ? '오늘부터 다시' : '날을 정하면 시작',
      /* 부제는 짧아야 합니다 — 두 칸이 나란히 서는 자리라 길면 말줄임으로
         잘리고, 잘린 설명은 없는 설명입니다. "다시 시작하세요" 는 카드
         본문이 이미 말하고 있으므로 여기서는 날짜만 적습니다. */
      { stale: w.stale,
        staleSub: w.lastKept ? UI.dateShort(w.lastKept) + '까지' : '',
        /* 끊겨도 안 줄어드는 숫자를 나란히 둡니다. 연속만 보여 주면
           끊기는 날 그동안 한 일이 통째로 사라진 것처럼 보입니다. */
        extra: w.last28 ? '4주 중 ' + w.last28 + '일' : null }));
    /* 식단은 "최근 7일 중 N일" 을 같이 적습니다. 어제 하루 빼먹어
       연속이 0인 날에도 7일 중 5일이면 잘 하고 있는 겁니다.
       연속이 0인데 7일 창에 기록이 있으면 그 사람에게 필요한 말은
       "한 끼만 적어도 1일" 이 아니라 그 숫자입니다 — 이미 적고 있는
       사람에게 적는 법을 알려 주는 칸이 되면 안 됩니다. */
    var last7 = f.last7 ? '7일 중 ' + f.last7 + '일' : null;
    box.appendChild(cell('\uD83C\uDF5A', '식단 기록', f,
      last7 || '한 끼만 적어도 1일',
      { extra: f.days ? last7 : null }));

    box.appendChild(h('div.muted', { style: { gridColumn: '1/-1' },
      text: '쉬는 날은 끊지 않습니다. 계획한 날만 셉니다.' }));
    return box;
  }

  /* --- M51 하루 정하기 ------------------------------------------------- */
  function dayModal(key) {
    var W = global.MB_SCHED;
    var ST = S.get();
    var today = S.dayKey();
    var d = new Date(key + 'T00:00:00');
    var dow = W.DOW[(d.getDay() + 6) % 7];
    var future = key > today;

    UI.openModal({
      uid: 'M51', title: '하루 정하기',
      sub: (d.getMonth() + 1) + '월 ' + d.getDate() + '일 (' + dow + ') · ' +
           (future ? '아직 오지 않은 날' : (key === today ? '오늘' : '지난 날')),
      body: function (close) {
        var box = h('div');
        function draw() {
          UI.clear(box);
          var e = S.scheduleDay(key);
          W.TYPES.forEach(function (t) {
            var planned = e.plan.indexOf(t.id) >= 0;
            var done = !!e.done[t.id];
            var rowEl = h('div.daypick' + (planned ? '.is-on' : ''), [
              h('button.daypick__main', {
                uid: 'M51-L01#' + (W.indexOf(t.id) + 1), uidLabel: '하기로 정하기 ' + t.label,
                'aria-pressed': planned ? 'true' : 'false',
                onClick: function () { S.setSchedulePlan(key, t.id, !planned); draw(); }
              }, [
                h('span.daypick__ico', { text: t.icon }),
                h('span.daypick__t', { text: t.label }),
                h('span.daypick__s', { text: planned ? '하기로 함' : '누르면 추가' })
              ]),
              planned && !future ? h('button.btn.btn--sm' + (done ? '.btn--primary' : ''), {
                text: done ? '✓ 했음' : '했어요',
                uid: 'M51-L02#' + (W.indexOf(t.id) + 1), uidLabel: '완료 체크 ' + t.label,
                onClick: function () { S.setScheduleDone(key, t.id, !done); draw(); }
              }) : null
            ]);
            box.appendChild(rowEl);
            /* 늦게 누른 체크는 늦게 눌렀다고 적습니다. 막지는 않습니다 —
               갔는데 누르는 걸 잊는 쪽이 훨씬 흔합니다. */
            if (done && e.done[t.id] && S.dayKey(e.done[t.id]) > key) {
              box.appendChild(h('div.muted', { style: { margin: '-4px 0 8px 2px' },
                text: UI.dateShort(e.done[t.id]) + ' 에 체크했습니다' }));
            }
          });
          if (future) {
            box.appendChild(h('div.muted', { style: { marginTop: '8px' },
              text: '아직 오지 않은 날은 체크할 수 없습니다. 그 날 눌러주세요.' }));
          }
        }
        draw();
        return box;
      },
      actions: [{ label: '닫기', kind: 'primary', uid: 'M51-B01',
        onClick: function () { A.refresh(); } }]
    });
  }

  /* NaN 을 0 으로 받습니다. Math.max/min 은 NaN 을 그대로 통과시켜서,
     0 으로 나눈 값이 화면까지 "NaN%" 로 흘러갔습니다. */
  function clamp(x) { return isFinite(x) ? Math.max(0, Math.min(100, x)) : 0; }

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

  /**
   * 도착 예정일이 측정 오차만으로 얼마나 흔들리는가.
   *
   * 화면은 "D−153 · 2027. 2. 20. 도착 예정" 을 한 날짜로 보여줍니다.
   * 그 날짜는 계획상으로는 정확하지만, 계획 자체가 인바디 측정 한 번
   * 위에 서 있습니다. 그 측정의 체지방이 ±1.0kg 흔들리면 도착일이
   * 몇 주씩 움직입니다 — 실측으로 확인해 보니 4/10 ~ 5/1 이었고,
   * 단조롭지도 않았습니다(19.0kg 과 20.0kg 이 같은 날짜).
   *
   * 날짜를 지우지는 않습니다. 목표가 있는 사람에게 "언제쯤" 은 필요한
   * 숫자입니다. 대신 그 숫자가 얼마나 단단한지를 같이 적습니다.
   *
   * 계산: 계획이 주당 r kg 의 지방을 뺀다면, 시작값의 오차 n kg 은
   * n/r 주만큼의 도착일 오차가 됩니다. 매번 계획을 다시 돌리지 않고
   * 궤적의 기울기만 봅니다.
   */
  function arrivalSpread(plan) {
    var t = (plan && plan.trajectory) || [];
    if (t.length < 3) return null;
    var n = Math.min(8, t.length - 1);
    var rate = Math.abs(t[0].bfmKg - t[n].bfmKg) / n;      // kg/주
    if (!(rate > 0.02)) return null;                        // 유지 계획 — 날짜 이야기가 아닙니다
    var weeks = noiseFloor().bfm / rate;
    if (!isFinite(weeks) || weeks > 26) return null;         // 너무 넓으면 숫자로 말하지 않습니다
    return Math.max(1, Math.round(weeks));
  }

  /**
   * 이 기간에 계획이 기대한 변화.
   *
   * 창은 "측정일 → 측정일"로 정해지는데 계획은 주 단위 눈금이라,
   * 창의 양끝을 계획의 눈금 위로 옮겨서 읽습니다(주 사이는 직선 보간).
   * 창이 계획 시작 전이면 겹치는 구간이 없습니다 — 그때는 null 입니다.
   * 계획이 존재하지도 않던 기간에 "계획 대비"를 찍는 것은 거짓말입니다.
   */
  function planSegment(plan, fromISO, toISO) {
    var t = (plan && plan.trajectory) || [];
    if (t.length < 2 || !plan.startDate || !fromISO || !toISO) return null;
    var WEEK = 7 * 86400000;
    var s0 = Date.parse(plan.startDate);
    var last = (t.length - 1) * WEEK;
    var rawF = Date.parse(fromISO) - s0, rawO = Date.parse(toISO) - s0;
    if (!isFinite(rawF) || !isFinite(rawO)) return null;

    /* 창이 계획 밖으로 나가는 "방향" 을 구분합니다.
       예전에는 양끝을 [0, last] 로 자르고 겹치는 구간이 없으면 그냥
       null 이었습니다. 그래서 창이 계획 "이후" 일 때도 화면이
       "이 구간은 계획을 세우기 전입니다" 라고 했습니다 — 정반대입니다.
       계획이 끝난 뒤에 잰 것을 세우기 전이라고 하면, 사용자는 자기가
       뭘 잘못했나 찾게 됩니다. */
    if (rawO <= 0) return { none: 'before' };
    if (rawF >= last) return { none: 'after' };

    var f = Math.max(0, Math.min(last, rawF));
    var o = Math.max(0, Math.min(last, rawO));
    // 겹치는 구간이 사흘 미만이면 비교할 만한 계획분이 아닙니다.
    if (!(o - f >= 3 * 86400000)) return { none: 'short' };

    /* 창의 일부만 계획과 겹칠 수 있습니다(계획 시작을 걸치는 창).
       그때 겹친 부분의 계획분을 창 전체의 계획인 것처럼 적으면 안 됩니다 —
       사용자는 그 숫자로 자기를 평가합니다. 겹친 기간을 같이 돌려줘서
       화면이 사실대로 말하게 합니다. */
    var windowDays = Math.round((rawO - rawF) / 86400000);
    var overlapDays = Math.round((o - f) / 86400000);
    function at(ms) {
      var w = ms / WEEK, i = Math.floor(w), r = w - i;
      var a = t[Math.min(i, t.length - 1)], b = t[Math.min(i + 1, t.length - 1)];
      return function (k) { return a[k] + (b[k] - a[k]) * r; };
    }
    var A = at(f), B = at(o);
    return {
      days: overlapDays,
      partial: overlapDays < windowDays - 1,
      windowDays: windowDays,
      bfmKg: B('bfmKg') - A('bfmKg'),
      smmKg: B('smmKg') - A('smmKg'),
      weightKg: B('weightKg') - A('weightKg')
    };
  }

  /* ------------------------------------------------------------------ */
  /* 측정 창 — 기간 보기가 쓸 재료                                        */
  /*                                                                      */
  /* 사용자가 인바디를 재는 주기는 제각각입니다(2~12주가 흔합니다).       */
  /* "이번 주 변화"를 말하려면 이번 주 안에 측정이 두 번 있어야 하는데    */
  /* 그런 일은 거의 없습니다. 그래서 창 안의 측정을 세고, 몇 개인지에     */
  /* 따라 화면이 다른 말을 하게 합니다.                                   */
  /* ------------------------------------------------------------------ */
  function scansInWindow(scans, days, profile) {
    var cut = Date.now() - days * 86400000;
    var inWin = (scans || []).filter(function (s2) {
      return Date.parse(s2.measuredAt) >= cut;
    });
    // 창 시작 직전의 측정 하나도 같이 가져옵니다 — 그게 있어야 "이 창에서
    // 얼마나 변했나"를 말할 수 있습니다. 없으면 비교 대상이 없습니다.
    var before = (scans || []).filter(function (s2) {
      return Date.parse(s2.measuredAt) < cut;
    }).slice(-1)[0] || null;

    /* 짝짓기 규칙:
       창 안에 2개 이상이면 창 안에서 비교합니다 — 창 밖을 끌어오면
       "28일 창"이라고 해 놓고 81일 구간을 돌려주게 됩니다(실제로 그랬습니다).
       창 안에 1개뿐이면 그때만 창 직전 측정을 끌어옵니다. 비교 대상이
       없으면 이 기간에 대해 아무 말도 할 수 없기 때문입니다. */
    var out = { inWindow: inWin.length, from: null, to: null, spanDays: 0,
                delta: null, usedBefore: false };
    var a, b = inWin[inWin.length - 1];
    if (inWin.length >= 2) { a = inWin[0]; }
    else { a = before; out.usedBefore = !!before; }
    if (!a || !b || a === b) return out;

    var da = E.derive(a, profile), db2 = E.derive(b, profile);
    // derive() 는 측정일을 안 돌려줍니다. 구간 머리에 날짜를 찍으려면
    // 원본 스캔을 같이 들고 있어야 합니다.
    out.from = da; out.to = db2;
    out.fromAt = a.measuredAt; out.toAt = b.measuredAt;
    out.spanDays = Math.round((Date.parse(b.measuredAt) - Date.parse(a.measuredAt)) / 86400000);
    out.delta = {
      weightKg: Math.round((db2.weightKg - da.weightKg) * 10) / 10,
      smmKg: Math.round((db2.smmKg - da.smmKg) * 100) / 100,
      bfmKg: Math.round((db2.bfmKg - da.bfmKg) * 100) / 100
    };
    return out;
  }

  /** 지표별 오차 바닥. 이 안이면 "변했다"고 말할 수 없습니다. */
  function noiseFloor() {
    return (global.MB_MODES && global.MB_MODES.NOISE) || { weight: 1.0, smm: 0.6, bfm: 1.0 };
  }

  /* 두 측정의 "차이"를 판정할 때 쓰는 바닥.
     오차가 두 번 들어가므로 √2 배입니다. 이걸 빼먹으면 일주일 일찍
     "이제 재도 된다"고 말하게 됩니다. */
  function diffFloor() {
    var n = noiseFloor();
    return { weight: n.weight * Math.SQRT2, smm: n.smm * Math.SQRT2, bfm: n.bfm * Math.SQRT2 };
  }

  /**
   * "구분되는 날" — 계획대로 갔을 때, 언제부터 변화가 측정 오차보다 커지는가.
   *
   * 이 카드가 새로 들이는 유일한 숫자입니다. 도착일이 며칠 움직였는지를
   * 말하지 않는 대신 이걸 말합니다 — 도착일 이동은 측정 오차 ±1.0kg 만으로
   * 6주 넘게 흔들리고 부호까지 뒤집히지만, 이 날짜는 계획의 기울기에서
   * 나오므로 측정 노이즈와 무관합니다.
   */
  function distinguishableDay(plan, lastScanISO) {
    if (!plan || !plan.trajectory || !lastScanISO) return null;
    var t = plan.trajectory;
    var wk = planWeek(plan);
    var last = t.length - 1;

    /* 계획이 끝났으면 "느리다" 가 아니라 "끝났다" 입니다.
       예전에는 마지막 주에서 a 와 b 가 같은 칸이 되어 기울기가 0 이
       나왔고, 화면은 "이 구간은 계획상 체지방 변화가 인바디 오차보다
       느립니다" 라고 했습니다. 느린 게 아니라 남은 계획이 없는 것이라,
       사용자는 자기 계획이 무의미하다고 읽게 됩니다. */
    if (wk >= last) return { ended: true };

    /* 앞으로 두 주를 보되, 계획이 두 주 안 남았으면 남은 만큼만 봅니다.
       예전에는 b 를 t[wk+2] 로 잡고 무조건 2 로 나눴습니다. 끝에서
       두 번째 주에서는 clamp 때문에 실제로 한 주만 보면서 2 로 나눠,
       기울기가 절반이 되고 "다시 재세요" 날짜가 두 배로 밀렸습니다. */
    var span = Math.min(2, last - wk);
    var a = t[wk], b = t[wk + span];
    if (!a || !b || span < 1) return null;
    var slope = Math.abs(b.bfmKg - a.bfmKg) / span;        // kg/주
    if (!(slope > 0.001)) return null;                     // 유지 구간 — 날짜로 말할 수 없습니다
    var rawDays = Math.ceil(diffFloor().bfm / slope * 7);
    if (rawDays > 84) return null;                         // 12주 넘으면 날짜를 지어내지 않습니다
    // 28일 하한 — modes.js 가 "4주 미만 간격은 추세로 쓰지 않는다"를 이미 선언했습니다.
    var moveDays = Math.max(28, rawDays);
    var when = new Date(Date.parse(lastScanISO) + moveDays * 86400000);
    return { moveDays: moveDays, date: E.toISODate(when),
             daysLeft: Math.ceil((when - Date.now()) / 86400000),
             weeks: Math.round(moveDays / 7) };
  }

  /* 기간 탭 한 줄. 목표 카드와 플랜 카드가 같은 것을 씁니다 —
     두 벌이면 한쪽만 고치는 일이 생기고, 탭이 서로 다르게 동작하게 됩니다. */
  function scopeTabs(scopes, initial, onPick, labelSuffix) {
    var scope = initial;
    var tabs = h('div.chips', { style: { marginBottom: '10px' } },
      scopes.map(function (sc) {
        return h('button.chip' + (sc.key === scope ? '.is-on' : ''), {
          text: sc.label, uid: sc.uid, uidLabel: sc.label + ' ' + (labelSuffix || ''),
          onClick: function () {
            scope = sc.key;
            tabs.querySelectorAll('.chip').forEach(function (x, i) {
              x.classList.toggle('is-on', scopes[i].key === scope);
            });
            onPick(scope);
          } });
      }));
    tabs.current = function () { return scope; };
    return tabs;
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
    var tabs = scopeTabs(SCOPES, scope, function (k) { scope = k; render(); }, '플랜');

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
