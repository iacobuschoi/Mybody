/* P18 식단 기록 · P19 음식 고르기 · P20 사진 기록 · P21 식단 달성률 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;
  function F() { return global.MB_FOOD; }

  var MEALS = ['아침', '점심', '저녁', '간식'];
  var viewDate = null;          // null = 오늘
  function curDate() { return viewDate || S.dayKey(); }
  function shiftDate(n) {
    var d = new Date(curDate() + 'T00:00:00');
    d.setDate(d.getDate() + n);
    var k = S.dayKey(d);
    viewDate = (k === S.dayKey()) ? null : k;
  }
  function targetOf() {
    var st = S.get();
    return st.plan ? st.plan.macros : null;
  }

  /* ===================== P18 식단 기록 (일간) ===================== */
  A.register('P18', {
    title: '식단', label: '식단 기록',
    render: function (wrap, ctx) {
      var date = curDate();
      var isToday = date === S.dayKey();
      var target = targetOf();
      var totals = S.dayTotals(date);
      var logs = S.logsForDate(date);

      /* --- C01 날짜 이동 --- */
      wrap.appendChild(h('div.card.card--flat', { uid: 'P18-C01', uidLabel: '날짜 이동' }, [
        h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, [
          h('button.btn.btn--ghost.btn--sm', { text: '‹', uid: 'P18-B01', uidLabel: '이전 날',
            onClick: function () { shiftDate(-1); A.refresh(); } }),
          h('div', { style: { flex: '1', textAlign: 'center' } }, [
            h('div', { style: { fontWeight: '800' }, text: isToday ? '오늘' : UI.dateK(date) }),
            h('div.muted', { text: isToday ? UI.dateK(date) : '' })
          ]),
          h('button.btn.btn--ghost.btn--sm', { text: '›', uid: 'P18-B02', uidLabel: '다음 날',
            disabled: isToday || undefined,
            onClick: function () { shiftDate(1); A.refresh(); } })
        ])
      ]));

      if (!target) {
        wrap.appendChild(h('div.note.note--warn', { uid: 'P18-S01', uidLabel: '목표 없음 안내' }, [
          h('b', { text: '아직 하루 목표가 없습니다. ' }),
          '플랜을 만들면 칼로리와 탄단지 목표가 생기고, 여기에 대조해서 보여드립니다.',
          h('button.btn.btn--sm.btn--primary.btn--block', { text: '플랜 만들기',
            style: { marginTop: '10px' }, uid: 'P18-B03', uidLabel: '플랜 만들기',
            onClick: function () { A.go('P05'); } })
        ]));
      }

      /* --- C02 남은 양 (핵심) ---
         퍼센트가 아니라 "남은 양"으로 보여줍니다. 이 화면은 먹기 직전에 보는
         화면이라, 다음 행동으로 바로 번역되는 단위여야 합니다.
         "단백질 40g 남음"은 닭가슴살 한 팩으로 바로 이어지지만
         "60% 달성"은 목표를 기억해 곱셈을 해야 행동이 됩니다. */
      if (target) {
        var remainP = Math.max(0, target.proteinG - totals.p);
        var remainK = target.intakeKcal - totals.kcal;
        var band = { lo: Math.round(target.intakeKcal * 0.9), hi: Math.round(target.intakeKcal * 1.1) };
        var inBand = totals.kcal >= band.lo && totals.kcal <= band.hi;

        var card = h('div.card.card--accent', { uid: 'P18-C02', uidLabel: '오늘 남은 양' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '오늘' }),
          h('span.badge' + (totals.logged ? (inBand ? '.badge--ok' : '') : ''),
            { text: totals.logged ? totals.entries + '건 기록' : '기록 없음' })
        ]));
        card.appendChild(h('div', { style: { display: 'grid', gridTemplateColumns: '1fr 1fr',
                                             gap: '10px', margin: '4px 0 12px' } }, [
          h('div', [
            h('div.stat__k', { text: '단백질 남음' }),
            h('div', [h('span', { style: { fontSize: '26px', fontWeight: '900',
                color: remainP > 0 ? 'var(--muscle)' : 'var(--ok)' },
                text: remainP > 0 ? UI.n0(remainP) : '완료' }),
              remainP > 0 ? h('span.stat__u', { text: 'g' }) : null]),
            h('div.muted', { text: UI.n0(totals.p) + ' / ' + target.proteinG + 'g' })
          ]),
          h('div', [
            h('div.stat__k', { text: '칼로리' }),
            h('div', [h('span', { style: { fontSize: '26px', fontWeight: '900',
                color: inBand ? 'var(--ok)' : (totals.kcal > band.hi ? 'var(--warn)' : 'var(--text)') },
                text: UI.n0(totals.kcal) })]),
            h('div.muted', { text: '목표 범위 ' + band.lo + '~' + band.hi })
          ])
        ]));

        card.appendChild(bandBar(totals.kcal, target.intakeKcal, band));
        card.appendChild(macroRow('단백질', totals.p, target.proteinG, 'var(--muscle)'));
        card.appendChild(macroRow('탄수화물', totals.c, target.carbG, 'var(--accent)'));
        card.appendChild(macroRow('지방', totals.f, target.fatG, 'var(--fat)'));

        var nudge = E.dietNudge(totals, target);
        if (nudge) {
          card.appendChild(h('div.note' + (nudge.tone ? '.note--' + nudge.tone : ''),
            { uid: 'P18-C03', uidLabel: '오늘 안내', style: { marginTop: '12px' } }, [
            h('b', { text: nudge.text }),
            h('div', { style: { marginTop: '3px' }, text: nudge.detail })
          ]));
        }
        wrap.appendChild(card);
      }

      /* --- C04 끼니별 --- */
      MEALS.forEach(function (meal, mi) {
        var mine = logs.filter(function (l) { return l.meal === meal; });
        var items = [];
        mine.forEach(function (l) { l.items.forEach(function (it) { items.push({ it: it, log: l }); }); });
        var t = S.sumItems(items.map(function (x) { return x.it; }));

        var card = h('div.card', { uid: 'P18-C0' + (4 + mi), uidLabel: meal + ' 기록' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: meal }),
          h('div.card__sub', { text: items.length ? t.kcal + 'kcal · 단백질 ' + t.p + 'g' : '비어 있음' })
        ]));
        if (items.length) {
          items.forEach(function (x, i) {
            card.appendChild(h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px',
                                                 padding: '6px 0', borderBottom: '1px solid var(--border)' } }, [
              h('div', { style: { flex: '1', minWidth: '0' } }, [
                h('div', { style: { fontWeight: '600', fontSize: '13.5px' },
                  text: x.it.name + (x.it.mult !== 1 ? ' × ' + x.it.mult : '') }),
                h('div.muted', { style: { fontSize: '11px' },
                  text: x.it.g + 'g · ' + x.it.kcal + 'kcal · P' + x.it.p + ' C' + x.it.c + ' F' + x.it.f +
                        (x.it.conf === 'low' ? ' · 편차 큼' : '') })
              ]),
              h('button.btn.btn--ghost.btn--sm', { text: '✕',
                uid: 'P18-B10#' + (mi * 20 + i + 1), uidLabel: '항목 삭제',
                onClick: function () { removeItem(x.log, x.it); } })
            ]));
          });
        }
        card.appendChild(h('button.btn.btn--sm.btn--block', { text: '+ ' + meal + ' 추가',
          style: { marginTop: '8px' },
          uid: 'P18-B0' + (4 + mi), uidLabel: meal + ' 추가',
          onClick: function () { A.go('P19', { meal: meal, date: date }); } }));
        wrap.appendChild(card);
      });

      /* --- C08 빠른 기록 --- */
      var recents = S.recentFoods(8);
      if (recents.length) {
        wrap.appendChild(h('div.card', { uid: 'P18-C08', uidLabel: '최근 먹은 것' }, [
          h('div.card__head', [h('div.card__title', { text: '최근 먹은 것' }),
                               h('div.card__sub', { text: '누르면 바로 추가' })]),
          h('div.chips', recents.map(function (it, i) {
            return h('button.chip', { text: it.name,
              uid: 'P18-B20#' + (i + 1), uidLabel: '최근 항목 추가',
              onClick: function () { quickAdd(it, date); } });
          }))
        ]));
      }

      /* --- 사진 / 달성률 --- */
      wrap.appendChild(h('div.btn-row', { style: { marginTop: '4px' } }, [
        h('button.btn', { text: '📷 사진으로', uid: 'P18-B08', uidLabel: '사진으로 기록',
          onClick: function () { A.go('P20', { meal: guessMeal(), date: date }); } }),
        h('button.btn', { text: '📊 달성률', uid: 'P18-B09', uidLabel: '달성률 보기',
          onClick: function () { A.go('P21'); } })
      ]));

      if (!logs.length) {
        wrap.appendChild(h('div.note', { uid: 'P18-S02', uidLabel: '기록 없음 안내',
          text: '완벽하게 적을 필요 없습니다. 한 끼만 적어도 주 평균이 살아납니다. ' +
                '안 적은 날은 0으로 치지 않고 평균에서 빼기 때문입니다.' }));
      }

      function removeItem(log, item) {
        log.items = log.items.filter(function (x) { return x !== item; });
        if (!log.items.length) S.removeFoodLog(log.id);
        else S.save();
        A.refresh();
      }
      function quickAdd(it, d) {
        S.addFoodLog({ date: d, meal: guessMeal(), items: [JSON.parse(JSON.stringify(it))], source: 'recent' });
        global.MB_UID.toast(it.name + ' 추가');
        A.refresh();
      }
    }
  });

  function guessMeal() {
    var hr = new Date().getHours();
    if (hr < 10) return '아침';
    if (hr < 15) return '점심';
    if (hr < 21) return '저녁';
    return '간식';
  }

  function bandBar(value, targetV, band) {
    var max = Math.max(band.hi * 1.15, value * 1.05, targetV * 1.2);
    function pct(v) { return Math.max(0, Math.min(100, v / max * 100)); }
    return h('div', { style: { margin: '10px 0 12px' } }, [
      h('div', { style: { position: 'relative', height: '10px', background: 'var(--surface-2)',
                          borderRadius: '999px', overflow: 'hidden' } }, [
        h('div', { style: { position: 'absolute', left: pct(band.lo) + '%',
                            width: (pct(band.hi) - pct(band.lo)) + '%', top: 0, bottom: 0,
                            background: 'color-mix(in srgb, var(--ok) 22%, transparent)' } }),
        h('div', { style: { position: 'absolute', left: 0, top: 0, bottom: 0,
                            width: pct(value) + '%', background: 'var(--accent)', opacity: '.75',
                            borderRadius: '999px' } })
      ]),
      h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '10.5px',
                          color: 'var(--text-3)', marginTop: '3px' } }, [
        h('span', { text: '0' }),
        h('span', { text: '목표 범위 ' + band.lo + '~' + band.hi + ' kcal' }),
        h('span', { text: String(Math.round(max)) })
      ])
    ]);
  }

  function macroRow(label, got, want, color) {
    var pct = want ? Math.min(140, got / want * 100) : 0;
    return h('div', { style: { marginBottom: '7px' } }, [
      h('div', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '12px',
                          marginBottom: '3px' } }, [
        h('span', { style: { fontWeight: '600', color: 'var(--text-2)' }, text: label }),
        h('span.num', { style: { fontWeight: '700' }, text: UI.n0(got) + ' / ' + want + 'g' })
      ]),
      h('div.bar', [h('div.bar__fill', { style: { width: Math.min(100, pct) + '%', background: color } })])
    ]);
  }

  /* ===================== P19 음식 고르기 ===================== */
  A.register('P19', {
    title: '음식 고르기', label: '음식 고르기',
    render: function (wrap, ctx) {
      var meal = ctx.params.meal || guessMeal();
      var date = ctx.params.date || S.dayKey();
      var q = '';
      var cat = null;
      var body = h('div');
      wrap.appendChild(body);
      draw();

      function draw() {
        UI.clear(body);
        body.appendChild(h('div.card.card--flat', { uid: 'P19-C01', uidLabel: '대상 끼니' }, [
          h('div.card__sub', { text: UI.dateK(date) }),
          h('div', { style: { fontSize: '17px', fontWeight: '800' }, text: meal + '에 추가' })
        ]));

        var input = h('input.input', { placeholder: '음식 이름 (예: 닭가슴살, 찌개, 김밥)',
          value: q, uid: 'P19-F01', uidLabel: '음식 검색',
          onInput: function () { q = input.value; drawResults(); } });
        body.appendChild(h('div.field', [input]));

        body.appendChild(h('div.chips', { uid: 'P19-F02', uidLabel: '분류 필터' },
          [h('button.chip' + (cat === null ? '.is-on' : ''), { text: '전체',
            onClick: function () { cat = null; draw(); } })].concat(
          F().CATS.map(function (c) {
            return h('button.chip' + (cat === c ? '.is-on' : ''), { text: c,
              onClick: function () { cat = (cat === c ? null : c); draw(); } });
          }))));

        var favs = (S.get().foodFavorites || []);
        if (favs.length && !q) {
          body.appendChild(h('div.card.card--flat', { uid: 'P19-C02', uidLabel: '즐겨찾기' }, [
            h('div.card__sub', { text: '즐겨찾기' }),
            h('div.chips', { style: { marginTop: '6px' } }, favs.map(function (n, i) {
              return h('button.chip.is-on', { text: n,
                uid: 'P19-B10#' + (i + 1), uidLabel: '즐겨찾기 선택',
                onClick: function () { openPortion(F().byName(n)); } });
            }))
          ]));
        }

        var results = h('div', { uid: 'P19-L01', uidLabel: '검색 결과' });
        body.appendChild(results);
        drawResults();

        function drawResults() {
          UI.clear(results);
          var list = q ? F().search(q, 40) : (cat ? F().byCat(cat) : F().FOODS.slice(0, 24));
          if (cat && q) list = list.filter(function (x) { return x.cat === cat; });
          if (!list.length) {
            results.appendChild(h('div.empty', { uid: 'P19-S01', uidLabel: '결과 없음' }, [
              h('div.empty__t', { text: '찾는 음식이 없습니다' }),
              h('div.empty__d', { text: '비슷한 걸 골라서 양을 조절하는 편이 안 적는 것보다 낫습니다.' }),
              h('button.btn.btn--sm', { text: '직접 입력', uid: 'P19-B02', uidLabel: '직접 입력',
                onClick: function () { openCustom(); } })
            ]));
            return;
          }
          list.forEach(function (food) {
            results.appendChild(h('div.card', {
              style: { cursor: 'pointer', padding: '11px 13px' },
              onClick: function () { openPortion(food); }
            }, [
              h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, [
                h('div', { style: { flex: '1', minWidth: '0' } }, [
                  h('div', { style: { fontWeight: '700', fontSize: '14px' }, text: food.name }),
                  h('div.muted', { style: { fontSize: '11.5px' },
                    text: food.unit + ' (' + food.g + 'g) · ' + food.kcal + 'kcal · P' + food.p +
                          ' C' + food.c + ' F' + food.f })
                ]),
                food.conf === 'low' ? h('span.badge.badge--warn', { text: '편차 큼' })
                  : (food.conf === 'high' ? h('span.badge.badge--ok', { text: '정확' }) : null)
              ])
            ]));
          });
          if (!q) {
            results.appendChild(h('button.btn.btn--sm.btn--block', { text: '목록에 없어요 · 직접 입력',
              style: { marginTop: '8px' }, uid: 'P19-B02', uidLabel: '직접 입력',
              onClick: function () { openCustom(); } }));
          }
        }
      }

      function openPortion(food) {
        if (!food) return;
        global.MB_MODALS.portion(food, function (scaled) {
          S.addFoodLog({ date: date, meal: meal, items: [scaled], source: 'manual' });
          global.MB_UID.toast(scaled.name + ' ' + scaled.kcal + 'kcal 추가');
          A.go('P18');
        });
      }
      function openCustom() {
        global.MB_MODALS.customFood(function (item) {
          S.addFoodLog({ date: date, meal: meal, items: [item], source: 'manual' });
          global.MB_UID.toast('추가했습니다');
          A.go('P18');
        });
      }
    }
  });

  /* ===================== P20 사진 기록 ===================== */
  A.register('P20', {
    title: '사진으로 기록', label: '사진 식단 기록',
    render: function (wrap, ctx) {
      var meal = ctx.params.meal || guessMeal();
      var date = ctx.params.date || S.dayKey();
      var mode = 'idle';          // idle | parsing | review
      var timers = [];
      var step = 0;
      var candidates = [];
      var body = h('div');
      wrap.appendChild(body);
      clearTimers();
      draw();

      function clearTimers() { timers.forEach(clearTimeout); timers = []; }

      function draw() {
        UI.clear(body);
        if (mode === 'idle') return drawIdle();
        if (mode === 'parsing') return drawParsing();
        return drawReview();
      }

      function drawIdle() {
        body.appendChild(h('div.note.note--warn', { uid: 'P20-C01', uidLabel: '정확도 고지' }, [
          h('b', { text: '사진은 "무엇"에 강하고 "얼마나"에 약합니다. ' }),
          '연구에서 사진 기반 양 추정의 평균 오차는 24% 정도였고, 가끔 두 배까지 틀립니다. ' +
          '그래서 이 앱은 음식만 사진으로 찾고, 양은 항상 직접 확인하게 합니다.'
        ]));
        body.appendChild(h('div.card', { uid: 'P20-C02', uidLabel: '사진 올리기' }, [
          h('div.card__title', { text: '사진 올리기' }),
          h('div.muted', { style: { marginTop: '6px' },
            text: '위에서 찍고, 그릇이 다 나오게, 숟가락이나 젓가락이 같이 보이면 크기 짐작에 도움이 됩니다.' }),
          h('div.btn-row.btn-row--stack', { style: { marginTop: '12px' } }, [
            h('button.btn.btn--primary.btn--block', { text: '📷 사진 찍기',
              uid: 'P20-B01', uidLabel: '사진 촬영',
              onClick: function () { startParse(); } }),
            h('button.btn.btn--block', { text: '갤러리에서 고르기',
              uid: 'P20-B02', uidLabel: '갤러리 선택',
              onClick: function () { startParse(); } }),
            h('button.btn.btn--ghost.btn--block', { text: '그냥 검색해서 고르기',
              uid: 'P20-B03', uidLabel: '검색으로 전환',
              onClick: function () { A.go('P19', { meal: meal, date: date }); } })
          ])
        ]));
        body.appendChild(h('div.note', { uid: 'P20-C03', uidLabel: '프로토타입 안내',
          text: '프로토타입이라 실제 인식은 하지 않습니다. 내장 샘플로 흐름만 보여드립니다.' }));
      }

      function drawParsing() {
        var steps = ['사진 불러오는 중', '음식 영역 찾는 중', '무엇인지 맞춰보는 중', '1인분 기준량 붙이는 중'];
        body.appendChild(h('div.card', { uid: 'P20-S01', uidLabel: '판독 중' }, [
          h('div.card__title', { text: '읽는 중' }),
          h('div.progress-steps', steps.map(function (t, i) {
            return h('div.pstep' + (i < step ? '.is-done' : (i === step ? '.is-active' : '')), [
              h('div.pstep__dot', { text: i < step ? '✓' : '' }),
              h('div', { text: t })
            ]);
          })),
          h('button.btn.btn--sm', { text: '취소', uid: 'P20-B04', uidLabel: '판독 취소',
            onClick: function () { clearTimers(); mode = 'idle'; draw(); } })
        ]));
      }

      function drawReview() {
        body.appendChild(h('div.note.note--warn', { uid: 'P20-C04', uidLabel: '검수 안내' }, [
          h('b', { text: '양은 직접 확인해 주세요. ' }),
          '음식 이름은 대개 맞지만 양은 자주 틀립니다. 여기서 고친 값이 기록됩니다.'
        ]));
        candidates.forEach(function (c, i) {
          var food = F().byName(c.name);
          body.appendChild(h('div.card', { uid: 'P20-C05#' + (i + 1), uidLabel: '인식 결과 ' + (i + 1) }, [
            h('div.card__head', [
              h('div', [
                h('div.card__title', { text: c.name }),
                h('div.card__sub', { text: '확신도 ' + Math.round(c.confidence * 100) + '%' })
              ]),
              h('span.dot-conf.' + (c.confidence >= 0.8 ? 'hi' : (c.confidence >= 0.55 ? 'mid' : 'lo')))
            ]),
            h('div.muted', { text: '기본값은 1인분입니다. 실제로 먹은 양으로 바꿔주세요.' }),
            h('div.chips', { style: { marginTop: '8px' } }, F().PORTIONS.map(function (p, pi) {
              return h('button.chip' + (c.mult === p.mult ? '.is-on' : ''), { text: p.label,
                uid: 'P20-F0' + (i + 1), uidLabel: '양 선택 ' + (i + 1),
                onClick: function () { c.mult = p.mult; draw(); } });
            })),
            h('div.muted', { style: { marginTop: '8px' },
              text: food ? (F().scaled(food, c.mult).g + 'g · ' + F().scaled(food, c.mult).kcal + 'kcal · 단백질 ' +
                            F().scaled(food, c.mult).p + 'g') : '' }),
            h('button.btn.btn--ghost.btn--sm', { text: '이건 아니에요 · 직접 찾기',
              style: { marginTop: '8px' },
              uid: 'P20-B05#' + (i + 1), uidLabel: '다시 찾기 ' + (i + 1),
              onClick: function () { A.go('P19', { meal: meal, date: date }); } })
          ]));
        });
        body.appendChild(h('div.btn-row', [
          h('button.btn', { text: '취소', uid: 'P20-B06', uidLabel: '기록 취소',
            onClick: function () { mode = 'idle'; draw(); } }),
          h('button.btn.btn--primary', { text: '기록하기', uid: 'P20-B07', uidLabel: '기록 저장',
            onClick: function () {
              var items = candidates.map(function (c) {
                var food = F().byName(c.name);
                var sc = F().scaled(food, c.mult);
                sc.fromPhoto = true;
                return sc;
              }).filter(Boolean);
              if (!items.length) { global.MB_UID.toast('기록할 항목이 없습니다'); return; }
              S.addFoodLog({ date: date, meal: meal, items: items, source: 'photo' });
              global.MB_UID.toast(items.length + '개 항목을 기록했습니다');
              A.go('P18');
            } })
        ]));
      }

      function startParse() {
        mode = 'parsing'; step = 0; draw();
        [0, 1, 2, 3].forEach(function (i) {
          timers.push(setTimeout(function () { step = i + 1; if (mode === 'parsing') draw(); }, 550 * (i + 1)));
        });
        timers.push(setTimeout(function () {
          if (mode !== 'parsing') return;
          // 내장 샘플: 한식 한 상. 이름은 맞히고 양은 1인분으로 깐다.
          candidates = [
            { name: '공기밥(백미)', confidence: 0.94, mult: 1 },
            { name: '김치찌개', confidence: 0.88, mult: 1 },
            { name: '계란말이', confidence: 0.61, mult: 0.5 },
            { name: '배추김치', confidence: 0.79, mult: 1 }
          ];
          mode = 'review'; draw();
        }, 2600));
      }
    }
  });

  /* ===================== P21 식단 달성률 ===================== */
  A.register('P21', {
    title: '식단 달성률', label: '식단 달성률',
    render: function (wrap, ctx) {
      var target = targetOf();
      var tab = ctx.params.tab || 'week';

      wrap.appendChild(h('div.tabs', { uid: 'P21-C01', uidLabel: '기간 탭' },
        [['week', '주간'], ['month', '월간']].map(function (t, i) {
          return h('button.tabs__item' + (tab === t[0] ? '.is-active' : ''), {
            text: t[1], uid: 'P21-T0' + (i + 1), uidLabel: t[1] + ' 탭',
            onClick: function () { A.go('P21', { tab: t[0] }, { replace: true }); } });
        })));

      if (!target) {
        wrap.appendChild(h('div.empty', { uid: 'P21-S01', uidLabel: '목표 없음' }, [
          h('div.empty__ico', { text: '🎯' }),
          h('div.empty__t', { text: '하루 목표가 없습니다' }),
          h('div.empty__d', { text: '플랜을 만들면 목표 대비 달성률을 볼 수 있습니다.' }),
          h('button.btn.btn--primary', { text: '플랜 만들기', uid: 'P21-B01', uidLabel: '플랜 만들기',
            onClick: function () { A.go('P05'); } })
        ]));
        return;
      }

      var days = collectDays(tab === 'week' ? 7 : 30);
      var adh = E.dietAdherence(days, target);

      /* 요약 — 분모를 반드시 명시한다 */
      wrap.appendChild(h('div.card.card--accent', { uid: 'P21-C02', uidLabel: '달성률 요약' }, [
        h('div.card__head', [
          h('div.card__title', { text: tab === 'week' ? '최근 7일' : '최근 30일' }),
          h('span.badge' + (adh.logRatePct >= 70 ? '.badge--ok' : ''),
            { text: '기록 ' + adh.loggedDays + '/' + adh.totalDays + '일' })
        ]),
        adh.loggedDays === 0
          ? h('div.muted', { text: '이 기간에 기록이 없습니다.' })
          : h('div', [
              h('div.stats', [
                statBox('칼로리 평균', adh.avg.kcal, 'kcal', adh.pct.kcal + '%'),
                statBox('단백질 평균', adh.avg.p, 'g', adh.pct.p + '%'),
                statBox('범위 안', adh.inBandDays, '일', adh.inBandPct + '%'),
                statBox('단백질 달성', adh.proteinHitDays, '일', adh.proteinHitPct + '%')
              ]),
              h('div.muted', { style: { marginTop: '10px' },
                text: '평균은 기록한 ' + adh.loggedDays + '일만으로 냈습니다. ' +
                      (adh.missedDays ? '기록 없는 ' + adh.missedDays + '일은 0으로 치지 않고 분모에서 뺐습니다.' : '') })
            ])
      ]));

      if (adh.missedDays >= Math.ceil(adh.totalDays * 0.5)) {
        wrap.appendChild(h('div.note', { uid: 'P21-S02', uidLabel: '기록률 안내',
          text: '절반 이상 안 적으셨습니다. 매 끼니를 다 적을 필요는 없고, ' +
                '단백질 들어간 것만 적어도 이 화면은 쓸모가 있습니다.' }));
      }

      if (tab === 'week') renderWeek(wrap, days, target, adh);
      else renderMonth(wrap, days, target, adh);

      wrap.appendChild(h('div.note', { uid: 'P21-C09', uidLabel: '해석 안내',
        text: '하루 값이 아니라 주 평균으로 보세요. 기록 오차와 TDEE 추정 오차가 겹쳐서, ' +
              '하루치 숫자는 원래 흔들립니다. 계획은 체중 변화를 보고 조정됩니다.' }));

      function collectDays(n) {
        var out = [];
        var today = new Date(S.dayKey() + 'T00:00:00');
        for (var i = n - 1; i >= 0; i--) {
          var d = new Date(today.getTime() - i * 86400000);
          var key = S.dayKey(d);
          var t = S.dayTotals(key);
          out.push({ date: key, logged: t.logged, kcal: t.kcal, p: t.p, c: t.c, f: t.f });
        }
        return out;
      }
    }
  });

  function statBox(label, v, unit, sub) {
    return h('div.stat', [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n0(v) }), h('span.stat__u', { text: unit })]),
      h('div.stat__d', { style: { color: 'var(--text-3)' }, text: sub })
    ]);
  }

  /* 주간 — 일별 바 + 목표선 + 기록일수. 단일 숫자만 보면 "평균은 맞는데 널뛰기"를 놓친다. */
  function renderWeek(wrap, days, target, adh) {
    var DOW = ['일', '월', '화', '수', '목', '금', '토'];
    [['단백질', 'p', target.proteinG, 'var(--muscle)'],
     ['칼로리', 'kcal', target.intakeKcal, 'var(--accent)'],
     ['탄수화물', 'c', target.carbG, 'var(--text-3)'],
     ['지방', 'f', target.fatG, 'var(--fat)']].forEach(function (m, mi) {
      var max = Math.max(m[2] * 1.4, Math.max.apply(null, days.map(function (d) { return d[m[1]] || 0; })) * 1.1, 1);
      wrap.appendChild(h('div.card', { uid: 'P21-C0' + (3 + mi), uidLabel: m[0] + ' 주간' }, [
        h('div.card__head', [
          h('div.card__title', { text: m[0] }),
          h('div.card__sub', { text: '목표 ' + UI.n0(m[2]) + (m[1] === 'kcal' ? 'kcal' : 'g') })
        ]),
        h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(' + days.length + ',1fr)',
                            gap: '4px', alignItems: 'end', height: '76px', position: 'relative',
                            marginTop: '6px' } },
          days.map(function (d) {
            var v = d[m[1]] || 0;
            var hgt = d.logged ? Math.max(3, v / max * 70) : 3;
            return h('div', { style: { display: 'flex', flexDirection: 'column',
                                       justifyContent: 'flex-end', height: '100%' } }, [
              h('div', { style: {
                height: hgt + 'px', borderRadius: '3px 3px 0 0',
                background: d.logged ? m[3] : 'var(--border)',
                opacity: d.logged ? (v >= m[2] * 0.9 ? '1' : '.55') : '.5'
              } })
            ]);
          })),
        h('div', { style: { position: 'relative', height: '1px', background: 'var(--text-3)',
                            opacity: '.4', marginTop: '-' + Math.round(70 * m[2] / max + 0) + 'px',
                            marginBottom: Math.round(70 * m[2] / max) + 'px' } }),
        h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(' + days.length + ',1fr)',
                            gap: '4px', fontSize: '10px', color: 'var(--text-3)',
                            textAlign: 'center', marginTop: '4px' } },
          days.map(function (d) {
            var dt = new Date(d.date + 'T00:00:00');
            return h('div', { text: d.logged ? DOW[dt.getDay()] : '·' });
          })),
        h('div.muted', { style: { marginTop: '6px' },
          text: adh.loggedDays
            ? '기록한 ' + adh.loggedDays + '일 평균 ' + UI.n0(adh.avg[m[1]]) +
              (m[1] === 'kcal' ? 'kcal' : 'g') + ' (목표의 ' + adh.pct[m[1]] + '%)'
            : '기록 없음' })
      ]));
    });
  }

  /* 월간 — 패턴을 본다. 미기록일은 0이 아니라 "없음"으로 그린다. */
  function renderMonth(wrap, days, target, adh) {
    var band = adh.band;
    wrap.appendChild(h('div.card', { uid: 'P21-C07', uidLabel: '월간 달력' }, [
      h('div.card__head', [h('div.card__title', { text: '최근 30일' }),
                           h('div.card__sub', { text: '칸 하나 = 하루' })]),
      h('div', { style: { display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: '4px',
                          marginTop: '8px' } },
        days.map(function (d) {
          var bg = 'var(--surface-2)', border = '1px dashed var(--border)', title = '기록 없음';
          if (d.logged) {
            border = 'none';
            if (d.kcal < band.lo) { bg = 'color-mix(in srgb, var(--accent) 25%, transparent)'; title = '범위 아래'; }
            else if (d.kcal > band.hi) { bg = 'color-mix(in srgb, var(--warn) 35%, transparent)'; title = '범위 위'; }
            else { bg = 'color-mix(in srgb, var(--ok) 35%, transparent)'; title = '범위 안'; }
          }
          var hit = d.logged && d.p >= target.proteinG * 0.9;
          return h('div', { title: d.date + ' · ' + title,
            style: { aspectRatio: '1', borderRadius: '6px', background: bg, border: border,
                     display: 'grid', placeItems: 'center', fontSize: '9px', color: 'var(--text-3)' } },
            [hit ? h('span', { style: { color: 'var(--muscle)', fontSize: '13px' }, text: '•' }) : null]);
        })),
      h('div', { style: { display: 'flex', gap: '10px', flexWrap: 'wrap', marginTop: '10px',
                          fontSize: '11px', color: 'var(--text-3)' } }, [
        legend('범위 안', 'color-mix(in srgb, var(--ok) 35%, transparent)'),
        legend('범위 위', 'color-mix(in srgb, var(--warn) 35%, transparent)'),
        legend('범위 아래', 'color-mix(in srgb, var(--accent) 25%, transparent)'),
        legend('기록 없음', 'var(--surface-2)', true),
        h('span', { style: { display: 'flex', alignItems: 'center', gap: '3px' } },
          [h('span', { style: { color: 'var(--muscle)' }, text: '•' }), '단백질 달성'])
      ]),
      h('div.muted', { style: { marginTop: '8px' },
        text: '여기서 볼 건 정확한 값이 아니라 패턴입니다 — 주말에 무너지는지, 바쁜 주에 끊기는지.' })
    ]));

    function legend(label, color, dashed) {
      return h('span', { style: { display: 'flex', alignItems: 'center', gap: '4px' } }, [
        h('span', { style: { width: '11px', height: '11px', borderRadius: '3px', background: color,
                             border: dashed ? '1px dashed var(--border)' : 'none' } }),
        label
      ]);
    }
  }
})(window);
