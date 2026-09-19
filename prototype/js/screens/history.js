/* P10 — 측정 히스토리 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 화면 상태 (다시 들어와도 유지) */
  var sortDesc = true;          // true = 최신순, false = 오래된순
  var filterKey = 'all';        // all | photo | manual

  var FILTERS = [
    { key: 'all',    label: '전체' },
    { key: 'photo',  label: '사진판독' },
    { key: 'manual', label: '직접입력' }
  ];

  /* 스캔 출처 표기.
     upload.js 는 'manual-photo'(사진 보며 직접) 또는 'ocr'(서버 판독),
     review.js 는 'manual', 시드 데이터는 'sheet'(전체 결과지) /
     'chart'(신체변화 그래프 복원) 를 쓴다. */
  function sourceLabel(src) {
    if (src === 'ocr') return '사진 판독';
    if (src === 'manual-photo') return '사진 보고 입력';
    if (src === 'manual') return '직접 입력';
    if (src === 'sheet') return '결과지 전체';
    if (src === 'chart') return '그래프 복원';
    return '출처 미상';
  }
  /* 사람이 숫자를 친 것(직접 입력 · 사진 보고 입력)과 기계가 읽은 것을
     가릅니다. 사진이 있었는지가 아니라 숫자가 어디서 왔는지가 기준입니다. */
  function matchesFilter(scan, key) {
    if (key === 'all') return true;
    if (key === 'manual') return scan.source === 'manual' || scan.source === 'manual-photo';
    return scan.source !== 'manual';
  }

  A.register('P10', {
    title: '기록', label: '측정 히스토리',
    render: function (wrap, ctx) {
      var st = S.get();
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var asc = S.sortedScans();            // 오래된 → 최신

      /* --- S01 빈 상태 --------------------------------------------------- */
      if (!asc.length) {
        wrap.appendChild(h('div.empty', { uid: 'P10-S01', uidLabel: '기록 없음 빈 상태' }, [
          h('div.empty__ico', { text: '🗂' }),
          h('div.empty__t', { text: '아직 기록이 없습니다' }),
          h('div.empty__d', { text: '인바디를 한 번 올리면 여기에 쌓이고, 두 번째부터 변화가 보입니다.' }),
          h('button.btn.btn--primary', {
            text: '새 측정 추가', uid: 'P10-B04', uidLabel: '새 측정 추가',
            onClick: function () { A.go('P03'); }
          })
        ]));
        return;
      }

      /* 파생값은 한 번만 계산해서 재사용 */
      var rows = asc.map(function (s) { return { scan: s, d: E.derive(s, prof) }; });
      var first = rows[0], last = rows[rows.length - 1];
      var spanDays = Math.round(
        (new Date(last.scan.measuredAt) - new Date(first.scan.measuredAt)) / 86400000);

      /* --- C01 요약 헤더 -------------------------------------------------- */
      var head = h('div.card', { uid: 'P10-C01', uidLabel: '기록 요약 헤더' }, [
        h('div.card__head', [
          h('div.card__title', { text: '측정 기록' }),
          h('span.badge.badge--accent', { text: '총 ' + rows.length + '회' })
        ]),
        h('div.kv', [
          h('span.kv__k', { text: '기간' }),
          h('span.kv__v', { text: UI.dateK(first.scan.measuredAt) + ' ~ ' + UI.dateK(last.scan.measuredAt) })
        ]),
        h('div.kv', [
          h('span.kv__k', { text: '경과' }),
          h('span.kv__v', { text: rows.length < 2 ? '—'
            : (spanDays + '일 (약 ' + Math.max(1, Math.round(spanDays / 7)) + '주)') })
        ])
      ]);

      if (rows.length >= 2) {
        head.appendChild(h('hr.sep'));
        head.appendChild(h('div.section-title', { text: '그 사이 총 변화' }));
        head.appendChild(h('div.stats', [
          changeStat('체중', first.d.weightKg, last.d.weightKg, 'kg', ''),
          changeStat('골격근량', first.d.smmKg, last.d.smmKg, 'kg', 'muscle'),
          changeStat('체지방률', first.d.pbfPct, last.d.pbfPct, '%', 'fat')
        ]));
      } else {
        head.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: '측정이 2회 이상 쌓이면 이 자리에 변화량이 표시됩니다.' }));
      }
      wrap.appendChild(head);

      /* --- C02 + G01~G03 추이 스파크라인 ---------------------------------- */
      var trend = h('div.card', { uid: 'P10-C02', uidLabel: '추이 스파크라인 카드' }, [
        h('div.card__head', [
          h('div.card__title', { text: '추이' }),
          h('button.btn.btn--ghost.btn--sm', {
            text: '자세히 ›', uid: 'P10-B06', uidLabel: '추이 화면으로',
            onClick: function () { A.go('P09'); }
          })
        ])
      ]);
      if (rows.length >= 2) {
        trend.appendChild(h('div', {
          style: { display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: '10px' }
        }, [
          sparkBox('P10-G01', '체중', pick(rows, 'weightKg'), 'var(--weight)', 'kg'),
          sparkBox('P10-G02', '골격근', pick(rows, 'smmKg'), 'var(--muscle)', 'kg'),
          sparkBox('P10-G03', '체지방률', pick(rows, 'pbfPct'), 'var(--fat)', '%')
        ]));
        trend.appendChild(h('div.muted', { style: { marginTop: '8px' },
          text: UI.dateShort(first.scan.measuredAt) + ' ~ ' + UI.dateShort(last.scan.measuredAt) +
                ' · 처음 대비 변화' }));
      } else {
        trend.appendChild(h('div.muted', { text: '측정이 2회 이상이면 추이선이 그려집니다.' }));
      }
      wrap.appendChild(trend);

      /* --- C03 정렬 · 필터 · 동작 ----------------------------------------- */
      var counts = {};
      FILTERS.forEach(function (f) {
        counts[f.key] = rows.filter(function (r) { return matchesFilter(r.scan, f.key); }).length;
      });

      wrap.appendChild(h('div.card.card--flat', { uid: 'P10-C03', uidLabel: '정렬·필터 바' }, [
        h('div', { style: { display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                            gap: '8px', flexWrap: 'wrap' } }, [
          h('div.chips', { uid: 'P10-B02', uidLabel: '출처 필터' },
            FILTERS.map(function (f) {
              return h('button.chip' + (filterKey === f.key ? '.is-on' : ''), {
                text: f.label + ' ' + counts[f.key],
                onClick: function () { filterKey = f.key; A.refresh(); }
              });
            })),
          h('button.btn.btn--sm', {
            text: sortDesc ? '최신순 ↓' : '오래된순 ↑', uid: 'P10-B01', uidLabel: '정렬 토글',
            onClick: function () { sortDesc = !sortDesc; A.refresh(); }
          })
        ]),
        h('div.btn-row', { style: { marginTop: '10px' } }, [
          h('button.btn.btn--sm', {
            text: '전체 내보내기', uid: 'P10-B03', uidLabel: '전체 내보내기',
            onClick: function () { global.MB_MODALS.exportData(); }
          }),
          h('button.btn.btn--sm.btn--primary', {
            text: '새 측정 추가', uid: 'P10-B04', uidLabel: '새 측정 추가',
            onClick: function () { A.go('P03'); }
          })
        ])
      ]));

      /* --- L01 측정 리스트 ------------------------------------------------- */
      /* 델타는 화면 정렬과 무관하게 '시간상 직전 측정' 기준으로 계산한다. */
      var shown = rows.filter(function (r) { return matchesFilter(r.scan, filterKey); });
      if (sortDesc) shown = shown.slice().reverse();   // 기본 최신순, 끄면 오래된순

      var list = h('div', { uid: 'P10-L01', uidLabel: '측정 리스트' });

      if (!shown.length) {
        list.appendChild(h('div.empty', [
          h('div.empty__t', { text: '이 필터에 해당하는 기록이 없습니다' }),
          h('div.empty__d', { text: '필터를 전체로 바꾸면 모든 기록이 보입니다.' })
        ]));
      }

      shown.forEach(function (r, i) {
        var idx = rows.indexOf(r);
        var prev = idx > 0 ? rows[idx - 1] : null;
        list.appendChild(scanRow(r, prev, i));
      });

      wrap.appendChild(list);
    }
  });

  /* --- 행 ---------------------------------------------------------------- */
  function scanRow(r, prev, index) {
    var s = r.scan, d = r.d, p = prev ? prev.d : null;
    var n = (index == null ? 1 : index + 1);

    function open() { A.go('P11', { scanId: s.id }); }

    return h('div.card', {
      uid: 'P10-L02#' + n, uidLabel: '측정 기록 행 ' + n,
      role: 'button', tabindex: '0',
      style: { cursor: 'pointer' },
      onClick: open,
      onKeydown: function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open(); }
      }
    }, [
      h('div.card__head', [
        h('div', { style: { minWidth: '0' } }, [
          h('div.card__title', { text: UI.dateK(s.measuredAt) }),
          h('div.card__sub', { text: (s.device || '기기 미상') + ' · ' + sourceLabel(s.source) })
        ]),
        h('div', { style: { display: 'flex', alignItems: 'center', gap: '6px', flex: 'none' } }, [
          s.partial ? h('span.badge.badge--warn', { text: '부분 데이터' }) : null,
          h('button.btn.btn--danger.btn--sm', {
            text: '삭제', uid: 'P10-B05#' + n, uidLabel: '이 측정 삭제 ' + n,
            onClick: function (e) {
              e.stopPropagation();
              global.MB_MODALS.deleteScan(s, function () { A.refresh(); });
            }
          })
        ])
      ]),
      h('div.stats', [
        valueStat('체중', d.weightKg, 'kg', p ? d.weightKg - p.weightKg : null, ''),
        valueStat('골격근량', d.smmKg, 'kg', p ? d.smmKg - p.smmKg : null, 'muscle'),
        valueStat('체지방량', d.bfmKg, 'kg', p ? d.bfmKg - p.bfmKg : null, 'fat')
      ]),
      h('div.muted', { style: { marginTop: '8px' },
        text: prev ? ('직전 대비 · ' + UI.dateShort(prev.scan.measuredAt) + ' 기준') : '첫 측정' })
    ]);
  }

  /* --- 작은 조각들 -------------------------------------------------------- */
  function pick(rows, key) {
    return rows.map(function (r) { return r.d[key]; });
  }

  /* 값 + 직전 대비 델타 (▲ 증가 / ▼ 감소 — home.js 와 같은 색 규칙) */
  function valueStat(label, val, unit, delta, mod) {
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(val) }), h('span.stat__u', { text: unit })]),
      delta != null && Math.abs(delta) >= 0.05
        ? h('div.stat__d' + (delta > 0 ? '.up' : '.down'),
            { text: (delta > 0 ? '▲ ' : '▼ ') + UI.n1(Math.abs(delta)) + unit })
        : h('div.stat__d.muted', { text: delta == null ? '—' : '변화 없음' })
    ]);
  }

  /* 처음 → 마지막 총 변화 */
  function changeStat(label, from, to, unit, mod) {
    var diff = to - from;
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.sign(diff) }), h('span.stat__u', { text: unit })]),
      h('div.stat__d' + (Math.abs(diff) < 0.05 ? '' : (diff > 0 ? '.up' : '.down')),
        { text: UI.n1(from) + ' → ' + UI.n1(to) + unit })
    ]);
  }

  function sparkBox(uid, label, values, color, unit) {
    var diff = values[values.length - 1] - values[0];
    return h('div', { uid: uid, uidLabel: label + ' 추이 스파크라인' }, [
      h('div.stat__k', { text: label }),
      UI.sparkline(values, color, 30),
      h('div', { style: { fontSize: '11px', fontWeight: '700', color: color } },
        [UI.sign(diff) + unit])
    ]);
  }
})(window);
