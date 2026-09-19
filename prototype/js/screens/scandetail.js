/* P11 — 개별 측정 상세 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 화면 상태 (다시 들어와도 유지) */
  var compareOn = false;      // C06 토글 — 켜면 C03 표에 Δ 열이 붙는다
  var impedanceOpen = false;  // C05 접이식 — 기본 접힘

  /* E.derive 가 채워줄 수 있는 항목. 결과지에 값이 없으면 계산값으로 대신 보여주고
     '계산값' 이라고 표시한다 (인쇄된 값인 척하지 않는다). */
  var DERIVABLE = {
    weightKg: 1, smmKg: 1, bfmKg: 1, ffmKg: 1, pbfPct: 1, bmi: 1, bmrKcal: 1
  };

  /* C03 전체 필드 — 결과지(InBody270) 인쇄 순서에 가깝게 */
  var FIELDS = [
    { key: 'tbwL',      label: '체수분 (TBW)',   unit: 'L',     dec: 1, rangeKey: 'tbwRange',     dir: 'lean' },
    { key: 'proteinKg', label: '단백질',          unit: 'kg',    dec: 1, rangeKey: 'proteinRange', dir: 'lean' },
    { key: 'mineralKg', label: '무기질',          unit: 'kg',    dec: 2, rangeKey: 'mineralRange', dir: 'lean' },
    { key: 'bfmKg',     label: '체지방량',        unit: 'kg',    dec: 1, rangeKey: 'bfmRange',     dir: 'fat' },
    { key: 'weightKg',  label: '체중',            unit: 'kg',    dec: 1, rangeKey: 'weightRange',  dir: 'fat' },
    { key: 'smmKg',     label: '골격근량 (SMM)',  unit: 'kg',    dec: 1, dir: 'lean' },
    { key: 'bmi',       label: 'BMI',             unit: 'kg/m²', dec: 1, general: true, dir: 'fat', gradeKey: 'bmiGrade' },
    { key: 'pbfPct',    label: '체지방률 (PBF)',  unit: '%',     dec: 1, general: true, dir: 'fat', gradeKey: 'pbfGrade' },
    { key: 'ffmKg',     label: '제지방량 (FFM)',  unit: 'kg',    dec: 1, rangeKey: 'ffmRange',     dir: 'lean' },
    { key: 'bmrKcal',   label: '기초대사량 (BMR)', unit: 'kcal', dec: 0, rangeKey: 'bmrRange',     dir: 'lean' },
    { key: 'visceralFatLevel',  label: '내장지방 레벨',   unit: '',     dec: 0, general: true, dir: 'fat' },
    { key: 'whr',               label: '복부지방률 (WHR)', unit: '',    dec: 2, general: true, dir: 'fat' },
    { key: 'obesityDegreePct',  label: '비만도',          unit: '%',    dec: 0, general: true, dir: 'fat' },
    { key: 'idealWeightKg',     label: '적정체중',        unit: 'kg',   dec: 1 },
    { key: 'weightControlKg',   label: '체중조절',        unit: 'kg',   dec: 1, signed: true },
    { key: 'fatControlKg',      label: '지방조절',        unit: 'kg',   dec: 1, signed: true },
    { key: 'muscleControlKg',   label: '근육조절',        unit: 'kg',   dec: 1, signed: true },
    { key: 'recommendedIntakeKcal', label: '권장섭취열량', unit: 'kcal', dec: 0 }
  ];

  var SEG_PARTS = [
    ['rightArm', '오른팔'], ['leftArm', '왼팔'], ['trunk', '몸통'],
    ['rightLeg', '오른다리'], ['leftLeg', '왼다리']
  ];
  var IMP_COLS = ['RA', 'LA', 'TR', 'RL', 'LL'];
  var IMP_ROWS = [['khz20', '20 kHz'], ['khz100', '100 kHz']];

  A.register('P11', {
    title: '측정 상세', label: '스캔 상세',
    render: function (wrap, ctx) {
      var st = S.get();
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var p = (ctx && ctx.params) || {};

      var scan = p.scanId ? S.scanById(p.scanId) : null;
      var lost = !!(p.scanId && !scan);      // 지워졌거나 없는 id 로 들어온 경우
      if (!scan) scan = S.latestScan();

      /* --- S01 빈 상태 --------------------------------------------------- */
      if (!scan) {
        wrap.appendChild(h('div.empty', { uid: 'P11-S01', uidLabel: '측정 없음 빈 상태' }, [
          h('div.empty__ico', { text: '📄' }),
          h('div.empty__t', { text: '볼 측정 기록이 없습니다' }),
          h('div.empty__d', { text: '인바디를 한 번 올리면 이 화면에서 결과지 전체를 그대로 볼 수 있습니다.' }),
          h('div.btn-row', [
            h('button.btn.btn--primary', {
              text: '측정 기록으로', uid: 'P11-B07', uidLabel: '측정 기록으로',
              onClick: function () { A.go('P10'); }
            }),
            h('button.btn.btn--ghost', {
              text: '인바디 올리기', uid: 'P11-B08', uidLabel: '인바디 올리기',
              onClick: function () { A.go('P03'); }
            })
          ])
        ]));
        return;
      }

      var asc = S.sortedScans();                       // 오래된 → 최신
      var idx = indexOfId(asc, scan.id);
      var prev = idx > 0 ? asc[idx - 1] : null;        // 시간상 직전 측정
      var isLatest = asc.length > 0 && asc[asc.length - 1].id === scan.id;
      var d = E.derive(scan, prof);
      var pd = prev ? E.derive(prev, prof) : null;
      if (!prev) compareOn = false;                    // 비교 대상이 없으면 토글은 꺼진 상태

      if (lost) {
        wrap.appendChild(h('div.note.note--warn', {
          uid: 'P11-S02', uidLabel: '없는 기록 안내',
          text: '요청한 측정 기록을 찾을 수 없어 가장 최근 측정을 보여줍니다.'
        }));
      }

      renderHeader(wrap, scan, d, st, isLatest);
      renderKeyStats(wrap, scan, d, prev, pd);
      renderCompareToggle(wrap, prev);
      renderFields(wrap, scan, d, prev, pd, prof);
      renderSegmental(wrap, scan);
      renderImpedance(wrap, scan);
    }
  });

  /* ======================================================================== */
  /* C01 헤더                                                                  */
  /* ======================================================================== */
  function renderHeader(wrap, scan, d, st, isLatest) {
    var score = num(scan.inbodyScore);
    var canPlan = !!st.goal;
    /* '부분 데이터' 는 플래그만 믿지 않고 실제로 몇 항목이 들어 있는지 센다 */
    var total = FIELDS.length;
    var filled = 0;
    FIELDS.forEach(function (f) { if (num(scan[f.key]) != null) filled++; });
    var lacking = scan.partial || filled < total;

    var card = h('div.card', { uid: 'P11-C01', uidLabel: '측정 헤더' }, [
      h('div.card__head', [
        h('div', { style: { minWidth: '0' } }, [
          h('div.card__title', { text: UI.dateK(scan.measuredAt) }),
          h('div.card__sub', {
            text: timeOf(scan.measuredAt) + ' · ' + (scan.device || '기기 미상') +
                  ' · ' + sourceLabel(scan.source)
          })
        ]),
        h('div', { style: { display: 'flex', gap: '6px', flex: 'none', alignItems: 'center' } }, [
          isLatest ? h('span.badge.badge--accent', { text: '최신' }) : null,
          h('span.badge' + (lacking ? '.badge--warn' : '.badge--ok'),
            { text: (lacking ? '부분 데이터 ' : '전체 ') + filled + '/' + total })
        ])
      ])
    ]);

    /* 올린 사진이 남아 있으면 같이 보여 줍니다. "그때 결과지가 어떻게
       생겼더라" 를 다시 볼 수 있어야, 나중에 숫자가 이상해 보일 때
       원본과 대조할 수 있습니다. */
    var ph = scan.photoId && global.MB_PHOTO ? global.MB_PHOTO.get(scan.photoId) : null;
    if (ph) {
      card.appendChild(h('img', {
        src: ph.dataUrl, alt: '그때 올린 결과지',
        uid: 'P11-B09', uidLabel: '결과지 사진 크게 보기',
        style: { width: '100%', borderRadius: '10px', display: 'block',
                 marginTop: '10px', cursor: 'zoom-in', background: 'var(--bg-2)' },
        onClick: function () { global.MB_MODALS.photoZoom(ph.dataUrl); }
      }));
      card.appendChild(h('div.muted', { style: { marginTop: '6px' },
        text: '눌러서 크게 보기 · 이 사진은 이 기기에만 있습니다' }));
    }

    if (score != null) {
      card.appendChild(h('div.kv', [
        h('span.kv__k', { text: 'InBody 점수' }),
        h('span.kv__v', [
          h('span.badge' + (score >= 80 ? '.badge--ok' : (score < 70 ? '.badge--warn' : '')),
            { text: UI.n0(score) + ' / 100' })
        ])
      ]));
      card.appendChild(h('div.muted', {
        text: '80점 이상이면 근육이 충분한 편, 70점 아래면 근육 대비 지방이 많은 편입니다.'
      }));
    }

    if (lacking) {
      card.appendChild(h('div.note.note--warn', { style: { marginTop: '10px' },
        text: '결과지 ' + total + '개 항목 중 ' + filled + '개만 들어 있습니다. ' +
              '아래 표의 “—”는 읽지 못했거나 입력하지 않은 값입니다.' }));
    }

    card.appendChild(h('div.btn-row', { style: { marginTop: '12px' } }, [
      h('button.btn.btn--sm', {
        text: '수정', uid: 'P11-B01', uidLabel: '이 측정 수정',
        onClick: function () { A.go('P04', { scanId: scan.id }); }
      }),
      h('button.btn.btn--sm.btn--danger', {
        text: '삭제', uid: 'P11-B02', uidLabel: '이 측정 삭제',
        onClick: function () {
          global.MB_MODALS.deleteScan(scan, function () { A.go('P10'); });
        }
      }),
      h('button.btn.btn--sm' + (canPlan ? '.btn--primary' : ''), {
        text: '이 측정으로 플랜 다시 만들기', uid: 'P11-B03', uidLabel: '플랜 다시 만들기',
        disabled: !canPlan,
        onClick: function () { if (canPlan) global.MB_MODALS.regeneratePlan(); }
      })
    ]));

    if (!canPlan) {
      card.appendChild(h('div.muted', { style: { marginTop: '6px' },
        text: '목표가 아직 없습니다. 목표를 정해야 플랜을 만들 수 있습니다.' }));
    } else if (!isLatest) {
      card.appendChild(h('div.muted', { style: { marginTop: '6px' },
        text: '플랜은 항상 가장 최근 측정을 기준으로 계산됩니다. 이 측정은 최신이 아닙니다.' }));
    }

    wrap.appendChild(card);
  }

  /* ======================================================================== */
  /* C02 핵심 지표                                                             */
  /* ======================================================================== */
  function renderKeyStats(wrap, scan, d, prev, pd) {
    wrap.appendChild(h('div.card', { uid: 'P11-C02', uidLabel: '핵심 지표' }, [
      h('div.card__head', [
        h('div.card__title', { text: '핵심 지표' }),
        h('div.card__sub', {
          text: prev ? ('직전 ' + UI.dateShort(prev.measuredAt) + ' 측정 대비') : '첫 측정 (비교 대상 없음)'
        })
      ]),
      h('div.stats', [
        keyStat('체중', num(d.weightKg), 'kg', delta(d, pd, 'weightKg'), ''),
        keyStat('골격근량', num(d.smmKg), 'kg', delta(d, pd, 'smmKg'), 'muscle'),
        keyStat('체지방량', num(d.bfmKg), 'kg', delta(d, pd, 'bfmKg'), 'fat'),
        keyStat('체지방률', num(d.pbfPct), '%', delta(d, pd, 'pbfPct'), 'fat')
      ])
    ]));
  }

  function keyStat(label, val, unit, diff, mod) {
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(val) }), h('span.stat__u', { text: unit })]),
      diff != null && Math.abs(diff) >= 0.05
        ? h('div.stat__d' + (diff > 0 ? '.up' : '.down'),
            { text: (diff > 0 ? '▲ ' : '▼ ') + UI.n1(Math.abs(diff)) + unit })
        : h('div.stat__d.muted', { text: diff == null ? '—' : '변화 없음' })
    ]);
  }

  /* ======================================================================== */
  /* C06 직전 측정 비교 토글                                                    */
  /* ======================================================================== */
  function renderCompareToggle(wrap, prev) {
    wrap.appendChild(h('div.card.card--flat', { uid: 'P11-C06', uidLabel: '직전 측정 비교 토글' }, [
      h('div', { style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                          gap: '8px', flexWrap: 'wrap' } }, [
        h('div', { style: { minWidth: '0' } }, [
          h('div', { style: { fontSize: '13px', fontWeight: '700' }, text: '직전 측정과 비교' }),
          h('div.muted', {
            text: prev
              ? (UI.dateK(prev.measuredAt) + ' 측정과의 차이를 아래 표에 Δ 열로 붙입니다')
              : '직전 측정이 없어 비교할 수 없습니다'
          })
        ]),
        h('button.btn.btn--sm' + (compareOn ? '.btn--primary' : ''), {
          text: compareOn ? '비교 끄기' : '비교 켜기',
          disabled: !prev, uid: 'P11-B04', uidLabel: '직전 측정 비교 토글',
          onClick: function () { compareOn = !compareOn; A.refresh(); }
        })
      ])
    ]));
  }

  /* ======================================================================== */
  /* C03 전체 필드 표                                                           */
  /* ======================================================================== */
  function renderFields(wrap, scan, d, prev, pd, prof) {
    var usedGeneral = false;

    var headRow = h('tr', [
      h('th', { text: '항목' }),
      h('th.num', { text: '값' }),
      h('th', { text: '기준' }),
      compareOn ? h('th.num', { text: 'Δ' }) : null
    ]);

    var body = h('tbody', FIELDS.map(function (f) {
      var cur = fieldValue(scan, d, f.key);
      var range = f.rangeKey ? validRange(scan[f.rangeKey]) : null;
      var fromGeneral = false;
      if (!range && f.general) {
        range = stdRange(f.key, prof);
        if (range) { fromGeneral = true; usedGeneral = true; }
      }
      var verdict = judgeNum(cur.v, range, f.dir);

      var diffText = '—', diffCalc = false;
      if (compareOn && prev) {
        var before = fieldValue(prev, pd, f.key);
        if (cur.v != null && before.v != null) {
          diffText = fmtSigned(cur.v - before.v, f.dec);
          /* 한쪽이라도 계산값이면 인쇄값끼리의 차이가 아니다 — 그렇게 표시한다 */
          diffCalc = cur.calc || before.calc;
        }
      }

      var valueText = cur.v == null
        ? '—'
        : (f.signed ? fmtSigned(cur.v, f.dec) : fmt(cur.v, f.dec)) + (f.unit ? ' ' + f.unit : '');

      return h('tr', [
        h('td', [
          h('div', { style: { fontWeight: '600' }, text: f.label }),
          cur.calc ? h('div.muted', { style: { fontSize: '11px' }, text: '계산값 (결과지에 없음)' }) : null,
          f.gradeKey && scan[f.gradeKey]
            ? h('div.muted', { style: { fontSize: '11px' }, text: '결과지 표기 · ' + scan[f.gradeKey] }) : null
        ]),
        h('td.num', { style: cur.v == null ? { color: 'var(--text-3)' } : null, text: valueText }),
        h('td', [
          verdict ? h('span.badge.' + verdict.cls, { text: verdict.text }) : null,
          range
            ? h('div.muted', { style: { fontSize: '11px' },
                text: (fromGeneral ? '*' : '') + rangeText(range, f.dec) })
            : (f.dir ? h('span.muted', { text: '판정 기준 없음' }) : null)
        ]),
        compareOn ? h('td.num', { style: diffText === '—' ? { color: 'var(--text-3)' } : null }, [
          h('div', { text: diffText }),
          diffCalc ? h('div.muted', { style: { fontSize: '11px' }, text: '계산값 비교' }) : null
        ]) : null
      ]);
    }));

    var card = h('div.card', { uid: 'P11-C03', uidLabel: '전체 항목 표 카드' }, [
      h('div.card__head', [
        h('div', [
          h('div.card__title', { text: '전체 항목' }),
          h('div.card__sub', { text: '결과지에 인쇄된 값 그대로 · 여기서는 수정할 수 없습니다' })
        ]),
        h('button.btn.btn--ghost.btn--sm', {
          text: '용어', uid: 'P11-B06', uidLabel: '용어 사전 열기',
          onClick: function () { global.MB_MODALS.glossary(); }
        })
      ]),
      h('div', { style: { overflowX: 'auto' } }, [
        h('table.table', { uid: 'P11-L01', uidLabel: '전체 항목 표' }, [
          h('thead', [headRow]), body
        ])
      ])
    ]);

    if (usedGeneral) {
      card.appendChild(h('div.muted', { style: { marginTop: '8px' },
        text: '* 표시한 기준은 결과지에 인쇄되지 않아 일반 기준값(성별 기준)을 쓴 것입니다.' }));
    }
    card.appendChild(h('div.muted', {
      text: '값을 고치려면 위의 “수정”을 누르세요. 이 표는 읽기 전용입니다.' }));

    wrap.appendChild(card);
  }

  /* ======================================================================== */
  /* C04 부위별 분석                                                            */
  /* ======================================================================== */
  function renderSegmental(wrap, scan) {
    var lean = scan.segmentalLean, fat = scan.segmentalFat;
    var card = h('div.card', { uid: 'P11-C04', uidLabel: '부위별 분석' }, [
      h('div.card__head', [
        h('div.card__title', { text: '부위별 분석' }),
        h('div.card__sub', { text: '팔·다리·몸통 각각의 근육량과 지방량 판정' })
      ])
    ]);

    if (!lean && !fat) {
      card.appendChild(h('div.empty', { style: { padding: '16px 0' } }, [
        h('div.empty__t', { text: '부위별 값이 없는 측정입니다' }),
        h('div.empty__d', { text: '결과지 전체를 올린 측정에서만 부위별 판정이 나옵니다.' })
      ]));
      wrap.appendChild(card);
      return;
    }

    card.appendChild(h('div', {
      style: { display: 'grid', gridTemplateColumns: 'repeat(2, minmax(0,1fr))', gap: '10px' }
    }, [
      h('div', [
        h('div.section-title', { text: '근육' }),
        segTable('P11-L02', '부위별 근육 표', lean, 'lean')
      ]),
      h('div', [
        h('div.section-title', { text: '지방' }),
        segTable('P11-L03', '부위별 지방 표', fat, 'fat')
      ])
    ]));

    card.appendChild(h('div.muted', { style: { marginTop: '8px' },
      text: '근육은 표준 이상이 좋고, 지방은 표준 이상이면 줄일 대상입니다.' }));

    wrap.appendChild(card);
  }

  function segTable(uid, label, map, dir) {
    return h('table.table', { uid: uid, uidLabel: label }, [
      h('tbody', SEG_PARTS.map(function (part) {
        var v = map ? map[part[0]] : null;
        var verdict = judgeText(v, dir);
        return h('tr', [
          h('td', { text: part[1] }),
          h('td', { style: { textAlign: 'right' } }, [
            verdict ? h('span.badge.' + verdict.cls, { text: verdict.text })
                    : h('span.muted', { text: '—' })
          ])
        ]);
      }))
    ]);
  }

  /* ======================================================================== */
  /* C05 임피던스 (접이식, 기본 접힘)                                            */
  /* ======================================================================== */
  function renderImpedance(wrap, scan) {
    var imp = scan.impedance;
    if (!imp) return;

    var card = h('div.card', { uid: 'P11-C05', uidLabel: '임피던스 원자료' }, [
      h('div.card__head', [
        h('div', [
          h('div.card__title', { text: '임피던스' }),
          h('div.card__sub', { text: '기기가 실제로 잰 저항값 (단위 Ω)' })
        ]),
        h('button.btn.btn--ghost.btn--sm', {
          text: impedanceOpen ? '접기' : '펼치기',
          uid: 'P11-B05', uidLabel: '임피던스 펼치기 토글',
          onClick: function () { impedanceOpen = !impedanceOpen; A.refresh(); }
        })
      ])
    ]);

    if (impedanceOpen) {
      card.appendChild(h('div', { style: { overflowX: 'auto' } }, [
        h('table.table', { uid: 'P11-L04', uidLabel: '임피던스 표' }, [
          h('thead', [h('tr', [h('th', { text: '주파수' })].concat(
            IMP_COLS.map(function (c) { return h('th.num', { text: c }); })
          ))]),
          h('tbody', IMP_ROWS.map(function (row) {
            var vals = imp[row[0]] || {};
            return h('tr', [h('td', { style: { fontWeight: '600' }, text: row[1] })].concat(
              IMP_COLS.map(function (c) {
                return h('td.num', { text: num(vals[c]) == null ? '—' : UI.n1(vals[c]) });
              })
            ));
          }))
        ])
      ]));
      card.appendChild(h('div.muted', { style: { marginTop: '8px' },
        text: 'RA 오른팔 · LA 왼팔 · TR 몸통 · RL 오른다리 · LL 왼다리. ' +
              '체성분은 이 값에서 계산됩니다. 해석에 쓸 일은 거의 없지만, 판독이 틀렸는지 확인할 때 쓸모가 있습니다.' }));
    }

    wrap.appendChild(card);
  }

  /* ======================================================================== */
  /* 작은 조각들                                                                */
  /* ======================================================================== */
  function num(v) { return (typeof v === 'number' && isFinite(v)) ? v : null; }

  function indexOfId(list, id) {
    for (var i = 0; i < list.length; i++) { if (list[i].id === id) return i; }
    return -1;
  }

  function delta(d, pd, key) {
    var a = num(d && d[key]), b = num(pd && pd[key]);
    return (a == null || b == null) ? null : (a - b);
  }

  /* 결과지 값 우선, 없으면 파생값 (파생이면 calc:true 로 표시) */
  function fieldValue(scan, d, key) {
    var direct = num(scan ? scan[key] : null);
    if (direct != null) return { v: direct, calc: false };
    if (DERIVABLE[key]) {
      var calc = num(d ? d[key] : null);
      if (calc != null) return { v: calc, calc: true };
    }
    return { v: null, calc: false };
  }

  function validRange(r) {
    if (!r || r.length !== 2) return null;
    return (num(r[0]) == null || num(r[1]) == null) ? null : [r[0], r[1]];
  }

  /* 결과지에 인쇄되지 않는 항목의 일반 기준값 (성별 기준) */
  function stdRange(key, prof) {
    var male = !prof || prof.sex !== 'female';
    if (key === 'bmi') return [18.5, 25.0];
    if (key === 'pbfPct') return male ? [10, 20] : [18, 28];
    if (key === 'visceralFatLevel') return [1, 9];
    if (key === 'whr') return male ? [0.80, 0.90] : [0.75, 0.85];
    if (key === 'obesityDegreePct') return [90, 110];
    return null;
  }

  /* 표준 미만 / 표준 / 표준 초과.
     근육 쪽(lean)은 많을수록 좋고, 지방 쪽(fat)은 많을수록 나쁘다. */
  function judgeNum(v, range, dir) {
    if (v == null || !range || !dir) return null;
    if (v < range[0]) return { text: '표준이하', cls: 'badge--warn' };
    if (v > range[1]) return dir === 'lean'
      ? { text: '표준이상', cls: 'badge--ok' }
      : { text: '표준이상', cls: 'badge--bad' };
    return { text: '표준', cls: 'badge--ok' };
  }

  function judgeText(v, dir) {
    if (!v) return null;
    if (v === '표준이하') return { text: '표준이하', cls: 'badge--warn' };
    if (v === '표준이상') return dir === 'lean'
      ? { text: '표준이상', cls: 'badge--ok' }
      : { text: '표준이상', cls: 'badge--bad' };
    if (v === '표준') return { text: '표준', cls: 'badge--ok' };
    return { text: String(v), cls: 'badge--warn' };
  }

  function rangeText(range, dec) {
    return '표준 ' + fmt(range[0], dec) + '~' + fmt(range[1], dec);
  }

  function fmt(v, dec) {
    if (v == null) return '—';
    if (dec === 0) return UI.n0(v);
    if (dec === 2) return UI.n2(v);
    return UI.n1(v);
  }
  function fmtSigned(v, dec) {
    if (v == null) return '—';
    var s = v > 0 ? '+' : (v < 0 ? '−' : '');
    return s + fmt(Math.abs(v), dec);
  }

  /* 측정 시각 — 결과지의 현지 시각을 그대로 읽는다 (기기 표준시 변환 없음) */
  function timeOf(iso) {
    var m = /T(\d{2}):(\d{2})/.exec(String(iso || ''));
    if (!m) return '시각 미상';
    var hh = parseInt(m[1], 10);
    var ap = hh < 12 ? '오전' : '오후';
    var h12 = hh % 12; if (h12 === 0) h12 = 12;
    return ap + ' ' + h12 + ':' + m[2];
  }

  /* history.js 와 같은 규칙 */
  function sourceLabel(src) {
    if (src === 'ocr') return '사진 판독';
    if (src === 'manual-photo') return '사진 보고 입력';
    if (src === 'manual') return '직접 입력';
    if (src === 'sheet') return '결과지 전체';
    if (src === 'chart') return '그래프 복원';
    return '출처 미상';
  }
})(window);
