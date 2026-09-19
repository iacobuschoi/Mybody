/* P04 — 인바디 판독 결과 확인/수정
 *
 * 이 화면의 존재 이유: OCR은 절대 완벽하지 않다.
 * 사람이 눈으로 훑고 고칠 수 있어야 그 다음 계산 전부가 신뢰를 얻는다.
 * 그래서 (1) 못 읽은 값과 자신 없는 값을 위로 올리고,
 *        (2) 숫자끼리 서로 안 맞으면 모달이 아니라 화면 안에서 바로 지적하고,
 *        (3) 계산으로 고칠 수 있는 건 버튼 한 번으로 고친다.
 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 예전에 여기 OCR 신뢰도 문턱(0.85 / 0.60)이 있었습니다. 지웠습니다.
     그 점수는 글자를 얼마나 선명하게 봤는지였고, 그 숫자가 맞는지와는
     거의 상관이 없었습니다 — 맞은 값 24.8 에 14점, 틀린 값 19.3 에 39점.
     지금 화면에 뜨는 점은 crosscheck.js 의 검산 상태입니다. */

  /* --- 필드 정의 ---------------------------------------------------------- */
  /* range: [min, max] — 벗어나면 경고만 한다(저장은 막지 않는다)
     dec:   표시 소수 자릿수 (기본 1)
     derivable: 비워두면 저장 시 핵심 3종에서 계산해 채운다 */
  var CORE = [
    { key: 'weightKg', uid: 'P04-F01', label: '체중', unit: 'kg', step: 0.1,
      range: [20, 300], hint: '결과지 상단 "체중" 값' },
    { key: 'smmKg', uid: 'P04-F02', label: '골격근량 (SMM)', unit: 'kg', step: 0.1,
      range: [5, 70], hint: '근력이 아니라 근육의 무게입니다' },
    { key: 'bfmKg', uid: 'P04-F03', label: '체지방량 (BFM)', unit: 'kg', step: 0.1,
      range: [1, 120], hint: '체지방률(%)이 아니라 kg 값' }
  ];
  var DERIVED = [
    { key: 'pbfPct', uid: 'P04-F04', label: '체지방률 (PBF)', unit: '%', step: 0.1,
      range: [3, 60], derivable: true, hint: '비워두면 체지방량 ÷ 체중으로 채웁니다' },
    { key: 'bmi', uid: 'P04-F05', label: 'BMI', unit: '', step: 0.1,
      range: [10, 50], derivable: true, hint: '비워두면 체중 ÷ 키²로 채웁니다' },
    { key: 'ffmKg', uid: 'P04-F06', label: '제지방량 (FFM)', unit: 'kg', step: 0.1,
      range: [15, 130], derivable: true, hint: '비워두면 체중 − 체지방량으로 채웁니다' },
    { key: 'visceralFatLevel', uid: 'P04-F07', label: '내장지방 레벨', unit: '레벨', step: 1,
      range: [1, 30], dec: 0 },
    { key: 'bmrKcal', uid: 'P04-F08', label: '기초대사량 (BMR)', unit: 'kcal', step: 1,
      range: [800, 4000], dec: 0 },
    { key: 'whr', uid: 'P04-F09', label: '복부지방률 (WHR)', unit: '', step: 0.01,
      range: [0.6, 1.3], dec: 2, hint: '보통 0.7 ~ 1.1 사이입니다. 소수점 위치를 특히 잘 보세요.' },
    { key: 'inbodyScore', uid: 'P04-F10', label: 'InBody 점수', unit: '점', step: 1,
      range: [20, 110], dec: 0 }
  ];
  var COMPOSITION = [
    { key: 'tbwL', uid: 'P04-F11', label: '체수분 (TBW)', unit: 'L', step: 0.1, range: [10, 80] },
    { key: 'proteinKg', uid: 'P04-F12', label: '단백질', unit: 'kg', step: 0.1, range: [3, 25] },
    { key: 'mineralKg', uid: 'P04-F13', label: '무기질', unit: 'kg', step: 0.01, range: [1, 10], dec: 2 }
  ];
  var ALL_FIELDS = CORE.concat(DERIVED, COMPOSITION);

  A.register('P04', {
    title: '판독 결과 확인', label: '인바디 판독 검수',
    render: function (wrap, ctx) {
      var p = (ctx && ctx.params) || {};
      var st = S.get();
      var prof = st.profile || global.MB_DATA.SEED_PROFILE;
      var heightM = (prof.heightCm || 170) / 100;

      /* 존재하지 않는 기록을 고치러 온 경우 — 막다른 길로 두지 않는다 */
      if (p.scanId && !S.scanById(p.scanId)) {
        wrap.appendChild(h('div.empty', { uid: 'P04-S02', uidLabel: '기록 없음 빈 상태' }, [
          h('div.empty__ico', { text: '🗂' }),
          h('div.empty__t', { text: '그 측정 기록을 찾을 수 없습니다' }),
          h('div.empty__d', { text: '이미 지웠거나, 다른 기기에서 만든 기록일 수 있습니다.' }),
          h('div.btn-row', [
            h('button.btn', { text: '직접 입력하기', uid: 'P04-B11', uidLabel: '직접 입력으로 시작',
              onClick: function () { A.go('P04', { manual: true }, { replace: true }); } }),
            h('button.btn.btn--primary', { text: '인바디 올리기', uid: 'P04-B12',
              uidLabel: '인바디 올리기', onClick: function () { A.go('P03'); } })
          ])
        ]));
        return;
      }

      var src = loadSource(p, st);
      var mode = src.mode;          // 'ocr' | 'manual' | 'edit'
      var v = src.values;           // key -> number|null, measuredAt(string), device(string)
      var origin = src.origin;      // 편집 중인 원본 스캔 (없으면 null)

      var touched = {};             // 사람이 손댄 필드 = 확인된 필드
      var savedOnce = false;        // 저장하고 나면 더 지킬 것이 없습니다

      /* 고치던 것을 두고 나가려 하면 물어봅니다.
         탭바 · 뒤로가기 · 화면 안 버튼 어느 쪽으로 나가든 라우터가
         이걸 물어봅니다 — 나가는 길마다 따로 막으면 한 군데는 꼭
         빠지고, 거기로 나갈 때만 조용히 사라집니다. */
      A.confirmLeave(function () {
        if (savedOnce) return false;
        return Object.keys(touched).length > 0;
      });
      var rows = {};                // key -> {input, dot, note, err}
      var groups = {};              // uid -> {open, body, badge, btn}
      var warnHost, stateHost, saveBtn, laterBtn;
      /* 1층 검산 결과. revalidate() 가 매번 새로 계산합니다.
         화면 곳곳(점 · 칸 밑 문구 · 배너)이 같은 하나를 봅니다 —
         따로 계산하면 점은 초록인데 배너는 빨간 일이 생깁니다. */
      var check = null;

      /* 검산이 기댈 지난 측정. 편집 중인 스캔 자신은 빼야 합니다 —
         자기 자신과 비교하면 변화량이 늘 0 이라 아무것도 못 잡습니다. */
      var prevScan = (function () {
        var list = (st.scans || []).filter(function (x) {
          return !src.origin || x.id !== src.origin.id;
        });
        return list.length ? list[list.length - 1] : null;
      })();
      var mounted = false;          // 첫 렌더가 끝났는지 (배지 재스캔 범위 결정용)

      /* --- C01 원본 결과지 -------------------------------------------------
         사진이 있으면 띄웁니다. 검수의 요점은 "화면의 숫자와 결과지의
         숫자가 같은가" 인데, 결과지를 다시 꺼내 봐야 한다면 검수를
         건너뛰게 됩니다. 여기 있으면 눈만 움직이면 됩니다. */
      var photo = src.photoId ? global.MB_PHOTO.get(src.photoId) : null;
      wrap.appendChild(h('div.card', { uid: 'P04-C01', uidLabel: '원본 결과지' }, [
        h('div.card__head', [
          h('div.card__title', { text: '원본 결과지' }),
          h('span.badge' + (mode === 'ocr' ? '.badge--accent' : ''), { text: modeBadge(src) })
        ]),
        photo
          ? h('img', {
              src: photo.dataUrl, alt: '올린 결과지',
              uid: 'P04-B15', uidLabel: '사진 크게 보기',
              style: { width: '100%', borderRadius: '10px', display: 'block',
                       marginBottom: '8px', cursor: 'zoom-in', background: 'var(--bg-2)' },
              onClick: function () { global.MB_MODALS.photoZoom(photo.dataUrl); }
            })
          : h('div.muted', { style: { marginBottom: '8px' },
              text: '올린 사진이 없습니다. 결과지를 보면서 숫자를 대조해 주세요.' }),
        photo ? h('div.muted', { text: '눌러서 크게 보기 · 이 사진은 이 기기에만 있습니다' }) : null,
        h('div.muted', { text: originLine(src) })
      ]));

      /* --- C02 자동 검증 배너 --------------------------------------------- */
      warnHost = h('div.card', { uid: 'P04-C02', uidLabel: '자동 검증 배너' });
      wrap.appendChild(warnHost);

      /* --- C03 핵심 3종 ---------------------------------------------------- */
      var core = h('div.card.card--accent', { uid: 'P04-C03', uidLabel: '핵심 3종 입력 카드' }, [
        h('div.card__head', [
          h('div.card__title', { text: '핵심 3종' }),
          h('div.card__sub', { text: '이 세 개만 있으면 계획을 만들 수 있습니다' })
        ])
      ]);
      orderFields(CORE).forEach(function (f) { core.appendChild(fieldRow(f)); });
      wrap.appendChild(core);

      /* --- C04 파생/보조 (기본 펼침) --------------------------------------- */
      wrap.appendChild(groupCard('P04-C04', '파생 · 보조 항목', '결과지에 인쇄된 값 그대로 넣어 주세요',
        DERIVED, true, 'P04-B06', '보조 항목 펼치기/접기'));

      /* --- C05 체성분 구성 (기본 접힘) ------------------------------------- */
      wrap.appendChild(groupCard('P04-C05', '체성분 구성', '체수분 · 단백질 · 무기질 (없어도 계획은 나옵니다)',
        COMPOSITION, false, 'P04-B08', '체성분 구성 펼치기/접기'));

      /* --- C06 측정 정보 ---------------------------------------------------- */
      var infoCard = h('div.card', { uid: 'P04-C06', uidLabel: '측정 정보 카드' }, [
        h('div.card__head', [h('div.card__title', { text: '측정 정보' })])
      ]);
      infoCard.appendChild(dateRow());
      infoCard.appendChild(deviceRow());
      wrap.appendChild(infoCard);

      /* --- 상태(S01) + 액션 -------------------------------------------------- */
      stateHost = h('div');
      wrap.appendChild(stateHost);

      saveBtn = h('button.btn.btn--primary.btn--block', {
        text: '저장하고 목표 설정 →', uid: 'P04-B01', uidLabel: '저장하고 목표 설정',
        onClick: function () { save('next'); }
      });
      laterBtn = h('button.btn.btn--ghost', {
        text: '나중에 (저장만)', uid: 'P04-B04', uidLabel: '나중에 저장만 하기',
        onClick: function () { save('later'); }
      });

      wrap.appendChild(h('div.btn-row.btn-row--stack', { style: { marginTop: '4px' } }, [
        saveBtn,
        h('div.btn-row', [
          h('button.btn', {
            text: '전부 직접 입력으로', uid: 'P04-B02', uidLabel: '전부 직접 입력으로 전환',
            onClick: function () {
              savedOnce = true;   // 이미 "버리겠다" 고 확인한 뒤입니다
              global.MB_MODALS.switchToManual(function () {
                A.go('P04', { manual: true }, { replace: true });
              });
            }
          }),
          h('button.btn', {
            text: '사진 다시 올리기', uid: 'P04-B03', uidLabel: '사진 다시 올리기',
            onClick: function () { A.go('P03'); }
          })
        ]),
        h('div.btn-row', [
          laterBtn,
          h('button.btn.btn--ghost', {
            text: '용어가 뭐예요?', uid: 'P04-B05', uidLabel: '용어 사전 열기',
            onClick: function () { global.MB_MODALS.glossary(); }
          })
        ])
      ]));

      wrap.appendChild(h('div.muted', { style: { marginTop: '10px', textAlign: 'center' },
        text: '판독은 도우미일 뿐입니다. 결과지의 숫자가 최종입니다.' }));

      revalidate();
      mounted = true;

      /* ==================================================================== */
      /* 그리기 조각                                                           */
      /* ==================================================================== */

      /** 낮은 신뢰도 항목을 그룹 맨 위로 (안정 정렬: 순서 뒤집히지 않게 분리 후 연결) */
      function orderFields(list) {
        if (mode === 'manual') return list.slice();
        var low = [], rest = [];
        list.forEach(function (f) { (isLow(f.key) ? low : rest).push(f); });
        return low.concat(rest);
      }

      function fieldRow(f) {
        var dec = f.dec == null ? 1 : f.dec;
        var dot = h('span.dot-conf.' + dotClass(f.key));
        var input = h('input.input.input--num', {
          type: 'number', step: f.step, inputmode: 'decimal',
          value: fmt(v[f.key], dec),
          placeholder: f.derivable ? '비우면 자동 계산' : '',
          uid: f.uid, uidLabel: f.label,
          onInput: function () {
            v[f.key] = parseNum(input.value);
            markTouched(f.key);
            revalidate();
          }
        });
        var note = h('div');
        var err = h('div.field__err', { style: { display: 'none' } });

        rows[f.key] = { input: input, dot: dot, note: note, err: err, def: f, dec: dec };

        var row = h('div.field', [
          h('div.field__label', { style: { display: 'flex', alignItems: 'center', gap: '6px' } }, [
            mode === 'manual' ? null : dot,
            h('span', { text: f.label })
          ]),
          h('div.input-unit', [input, f.unit ? h('span.input-unit__u', { text: f.unit }) : null]),
          f.hint ? h('div.field__hint', { text: f.hint }) : null,
          note,
          err
        ]);
        paintNote(f.key);
        return row;
      }

      function dateRow() {
        var input = h('input.input', {
          type: 'datetime-local', value: isoToLocalInput(v.measuredAt),
          uid: 'P04-F14', uidLabel: '측정일시',
          onChange: function () {
            v.measuredAt = localInputToISO(input.value, src.rawMeasuredAt);
            markTouched('measuredAt');
            revalidate();
          }
        });
        var dot = h('span.dot-conf.' + dotClass('measuredAt'));
        rows.measuredAt = { input: input, dot: dot, note: h('div'), err: h('div.field__err'), def: null };
        return h('div.field', [
          h('div.field__label', { style: { display: 'flex', alignItems: 'center', gap: '6px' } }, [
            mode === 'manual' ? null : dot,
            h('span', { text: '측정일시' })
          ]),
          input,
          h('div.field__hint', { text: '결과지에 인쇄된 측정 시각을 그대로 넣으면 추이가 정확해집니다' })
        ]);
      }

      function deviceRow() {
        var input = h('input.input', {
          type: 'text', value: v.device || '', placeholder: 'InBody270',
          uid: 'P04-F15', uidLabel: '측정 기기',
          onInput: function () { v.device = input.value; }
        });
        return h('div.field', [
          h('div.field__label', { text: '측정 기기' }),
          input,
          h('div.field__hint', { text: '기기가 바뀌면 값이 조금 튈 수 있어 기록해 둡니다' })
        ]);
      }

      /** 접이식 그룹 카드 */
      function groupCard(uid, title, sub, list, openByDefault, btnUid, btnLabel) {
        var body = h('div');
        orderFields(list).forEach(function (f) { body.appendChild(fieldRow(f)); });

        var badge = h('span.badge.badge--bad', { style: { display: 'none' } });
        /* 버튼 글자는 자식 span으로 둔다 — btn.textContent 로 갈아끼우면
           uid.js가 버튼 안에 넣어둔 배지까지 같이 지워진다 */
        var btnText = h('span', { text: openByDefault ? '접기' : '펼치기' });
        var btn = h('button.btn.btn--ghost.btn--sm', {
          uid: btnUid, uidLabel: btnLabel,
          onClick: function () {
            var g = groups[uid];
            g.open = !g.open;
            g.body.style.display = g.open ? '' : 'none';
            g.btnText.textContent = g.open ? '접기' : '펼치기';
          }
        }, [btnText]);

        groups[uid] = { open: openByDefault, body: body, badge: badge, btn: btn, btnText: btnText };
        body.style.display = openByDefault ? '' : 'none';

        return h('div.card', { uid: uid, uidLabel: title }, [
          h('div.card__head', [
            h('div', [
              h('div.card__title', { text: title }),
              h('div.card__sub', { text: sub })
            ]),
            h('div', { style: { display: 'flex', alignItems: 'center', gap: '6px' } }, [badge, btn])
          ]),
          body
        ]);
      }

      /* ==================================================================== */
      /* 검증 · 갱신                                                           */
      /* ==================================================================== */

      function revalidate() {
        /* 0) 검산을 먼저 돌립니다. 아래 전부가 이 결과 하나를 봅니다. */
        check = global.MB_CHECK.run(v, prof, prevScan);

        /* 1) 필드별 범위 경고 */
        ALL_FIELDS.forEach(function (f) {
          var r = rows[f.key];
          if (!r) return;
          var val = v[f.key];
          var msg = '';
          if (val != null && f.range) {
            if (val < f.range[0] || val > f.range[1]) {
              msg = '보통 ' + fmt(f.range[0], f.dec == null ? 1 : f.dec) + ' ~ ' +
                    fmt(f.range[1], f.dec == null ? 1 : f.dec) + (f.unit ? f.unit : '') +
                    ' 범위입니다. 다시 확인해 주세요. (저장은 됩니다)';
            }
          }
          r.err.textContent = msg;
          r.err.style.display = msg ? '' : 'none';
        });

        /* 2) 점 · 칸 밑 문구 — 검산 결과가 바뀌면 같이 바뀌어야 합니다 */
        Object.keys(rows).forEach(function (k) {
          var r = rows[k];
          if (r && r.dot) r.dot.className = 'dot-conf ' + dotClass(k);
          paintNote(k);
        });

        /* 3) 검산 배너 */
        drawWarnings();

        /* 4) 그룹 헤더의 "확인 필요" 개수 */
        updateGroupBadge('P04-C04', DERIVED);
        updateGroupBadge('P04-C05', COMPOSITION);

        /* 5) 필수 3종 + 저장 버튼 */
        drawState();

        /* 다시 그린 조각에 배지를 다시 붙인다 (첫 렌더는 app.js가 통째로 스캔한다).
           warnHost가 아니라 wrap 기준으로 훑는다 — UI.clear(warnHost) 는
           uid.js가 warnHost(P04-C02) 안에 넣어둔 자기 배지까지 같이 지우는데,
           scan(warnHost) 는 자손만 보기 때문에 그 배지가 다시 생기지 않는다.
           이미 배지가 붙은 요소는 attachBadge 가 곧바로 반환하므로 비용은 거의 없다. */
        if (mounted && global.MB_UID) global.MB_UID.scan(wrap);
      }

      function drawWarnings() {
        UI.clear(warnHost);
        warnHost.appendChild(h('div.card__head', [
          h('div.card__title', { text: '검산' }),
          h('div.card__sub', { text: '결과지 안에서 숫자끼리 맞아떨어지는지 따져 봤습니다' })
        ]));

        var r = check;
        if (!r) return;

        /* 어긋난 검산 — 무엇과 무엇이 안 맞는지 식으로 보여 줍니다.
           "확인해 주세요" 만 있으면 무엇을 확인하라는 건지 모릅니다. */
        var broken = r.checks.filter(function (c) { return !c.ok; });
        broken.forEach(function (c) {
          var box = h('div.note.note--bad', { style: { marginBottom: '8px' } }, [
            h('b', { text: c.label }),
            h('div', { style: { marginTop: '4px' }, text: c.why })
          ]);
          if (c.fix) {
            box.appendChild(h('button.btn.btn--sm', {
              text: global.MB_CHECK.obj(fieldLabelOf(c.fix.field)) + ' ' + c.fix.value + ' 로 고치기',
              style: { marginTop: '8px' },
              uid: 'P04-B07', uidLabel: '계산값으로 맞추기',
              onClick: function () { setValue(c.fix.field, c.fix.value); }
            }));
          }
          warnHost.appendChild(box);
        });

        /* 자릿수 복구 제안 — 되돌렸을 때 검산이 전부 맞는 후보가 딱
           하나일 때만 올라옵니다. 둘 이상이면 무엇이 맞는지 모르는
           것이고, 그때 하나를 고르는 건 추측입니다. */
        r.suggestions.forEach(function (sg) {
          warnHost.appendChild(h('div.note.note--warn', { style: { marginBottom: '8px' } }, [
            h('b', { text: '자릿수를 잘못 읽었을 수 있습니다' }),
            h('div', { style: { marginTop: '4px' }, text: sg.why }),
            h('button.btn.btn--sm', {
              text: sg.from + ' → ' + sg.to + ' 로 고치기', style: { marginTop: '8px' },
              uid: 'P04-B13', uidLabel: '복구 제안 적용',
              onClick: function () { setValue(sg.field, sg.to); }
            })
          ]));
        });

        /* 범위·변화량 — 검산은 아니지만 같은 자리에서 말합니다 */
        r.rangeIssues.concat(r.deltaIssues).forEach(function (i2) {
          warnHost.appendChild(h('div.note.note--' + (i2.level === 'bad' ? 'bad' : 'warn'),
            { style: { marginBottom: '8px' } }, [h('div', { text: i2.why })]));
        });

        /* 맞아떨어진 것들은 접어 둡니다. 다 맞았을 때 여덟 줄이 올라오면
           정작 봐야 할 게 묻힙니다. */
        var okChecks = r.checks.filter(function (c) { return c.ok; });
        if (okChecks.length) {
          var open = false;
          var list = h('div', { style: { display: 'none', marginTop: '6px' } },
            okChecks.map(function (c) {
              return h('div.muted', { style: { fontSize: '12px', marginTop: '3px' },
                text: '✓ ' + c.why });
            }));
          warnHost.appendChild(h('div.note' + (broken.length ? '' : '.note--ok'), [
            h('div', { style: { display: 'flex', justifyContent: 'space-between',
                                alignItems: 'center', gap: '8px' } }, [
              h('b', { text: broken.length
                ? '나머지 ' + okChecks.length + '개는 맞아떨어집니다'
                : '검산 ' + okChecks.length + '개가 전부 맞아떨어집니다' }),
              h('button.btn.btn--ghost.btn--sm', {
                text: '자세히', uid: 'P04-B14', uidLabel: '검산 상세 펼치기',
                onClick: function (e) {
                  open = !open;
                  list.style.display = open ? '' : 'none';
                  e.currentTarget.textContent = open ? '접기' : '자세히';
                }
              })
            ]),
            list
          ]));
        } else if (!broken.length) {
          warnHost.appendChild(h('div.note', {
            text: '검산할 짝이 아직 없습니다. 체중 · 체지방량이 들어오면 여기서 바로 따집니다.' }));
        }

        /* 손봐야 하는 칸 바로가기 — 접힌 그룹 안에 숨지 않게 */
        var lowKeys = ALL_FIELDS.filter(function (f) { return isLow(f.key); })
          .map(function (f) { return f.key; });
        if (mode !== 'manual' && lowKeys.length) {
          warnHost.appendChild(h('div', { style: { marginTop: '10px' } }, [
            h('div.section-title', { text: lowWord() + ' ' + lowKeys.length + '개' }),
            h('div.chips', lowKeys.map(function (k) {
              var f = fieldDef(k);
              var why = checkState(k) === 'conflict' ? ' · 어긋남'
                      : (v[k] == null ? ' · 비어 있음' : '');
              return h('button.chip', {
                text: f.label + why,
                uid: 'P04-B09', uidLabel: '확인 필요 항목 바로가기',
                onClick: function () { focusField(k); }
              });
            }))
          ]));
        }

        if (mode !== 'manual') {
          /* 예전엔 여기에 "● 초록: 잘 읽음" 이라고 적혀 있었습니다.
             OCR 신뢰도를 가리키는 말이었는데, 그 점수는 글자를 얼마나
             선명하게 봤는지일 뿐 그 숫자가 맞는지가 아니었습니다.
             (맞은 값 24.8 에 14점, 틀린 값 19.3 에 39점) */
          warnHost.appendChild(h('div.muted', { style: { marginTop: '10px' },
            text: '● 초록: 다른 칸과 맞아떨어짐 · 회색: 검산할 짝이 없음 · 빨강: 다른 칸과 어긋남' }));
        }
      }

      function drawState() {
        UI.clear(stateHost);
        var missing = CORE.filter(function (f) { return v[f.key] == null; });
        var ok = missing.length === 0;

        if (!ok) {
          stateHost.appendChild(h('div.note.note--bad',
            { uid: 'P04-S01', uidLabel: '필수 3종 미입력 오류' }, [
            h('b', { text: '핵심 3종을 채워야 저장할 수 있습니다' }),
            h('div', { style: { marginTop: '4px' },
              text: '비어 있음: ' + missing.map(function (f) { return f.label; }).join(' · ') }),
            h('button.btn.btn--sm', {
              text: missing[0].label + ' 입력하러 가기', style: { marginTop: '8px' },
              uid: 'P04-B10', uidLabel: '미입력 항목으로 이동',
              onClick: function () { focusField(missing[0].key); }
            })
          ]));
        }
        saveBtn.disabled = !ok;
        laterBtn.disabled = !ok;
      }

      function updateGroupBadge(uid, list) {
        var g = groups[uid];
        if (!g) return;
        var n = list.filter(function (f) { return isLow(f.key); }).length;
        if (mode === 'manual' || n === 0) { g.badge.style.display = 'none'; return; }
        g.badge.style.display = '';
        g.badge.className = 'badge ' + (mode === 'ocr' ? 'badge--bad' : 'badge--warn');
        g.badge.textContent = lowWord() + ' ' + n;
      }

      /* ==================================================================== */
      /* 값 조작                                                               */
      /* ==================================================================== */

      function setValue(key, val) {
        v[key] = val;
        var r = rows[key];
        if (r) r.input.value = fmt(val, r.dec);
        markTouched(key);
        revalidate();
      }

      function markTouched(key) {
        touched[key] = true;
        var r = rows[key];
        if (!r) return;
        r.dot.className = 'dot-conf ' + dotClass(key);
        paintNote(key);
      }

      /** 확인 필요 / 직접 확인함 표시 */
      function paintNote(key) {
        var r = rows[key];
        if (!r || !r.note) return;
        if (mode === 'manual') { r.note.className = ''; r.note.textContent = ''; return; }
        if (touched[key]) {
          r.note.className = 'field__hint';
          r.note.textContent = mode === 'ocr' ? '직접 확인함' : '수정함';
          return;
        }
        var st2 = checkState(key);
        if (st2 === 'conflict') {
          r.note.className = 'field__err';
          r.note.textContent = '이 칸이 결과지의 다른 칸과 어긋납니다 — 위의 검산을 보세요.';
          return;
        }
        if (v[key] == null) {
          r.note.className = 'field__hint';
          r.note.textContent = mode === 'ocr'
            ? '판독하지 못했습니다. 결과지에 있으면 넣어 주세요 — 없어도 저장됩니다.'
            : '비어 있음 — 결과지에 있으면 채워 주세요. 없어도 저장됩니다.';
          return;
        }
        if (st2 === 'verified') {
          r.note.className = 'field__hint';
          r.note.textContent = '검산됨 — 다른 칸과 맞아떨어집니다.';
          return;
        }
        r.note.className = '';
        r.note.textContent = '';
      }

      function focusField(key) {
        // 접힌 그룹 안에 있으면 먼저 펼친다
        Object.keys(groups).forEach(function (uid) {
          var list = uid === 'P04-C04' ? DERIVED : COMPOSITION;
          var inside = list.some(function (f) { return f.key === key; });
          if (inside && !groups[uid].open) {
            groups[uid].open = true;
            groups[uid].body.style.display = '';
            groups[uid].btnText.textContent = '접기';
          }
        });
        var r = rows[key];
        if (!r) return;
        if (r.input.scrollIntoView) r.input.scrollIntoView({ block: 'center' });
        r.input.focus();
      }

      /* 손봐야 하는 칸: 비어 있거나, 검산에서 다른 칸과 어긋난 칸.
         예전엔 OCR 신뢰도로 골랐는데, 그 점수는 맞은 값 24.8 에 14점,
         틀린 값 19.3 에 39점을 줬습니다. 글자를 선명하게 봤는지와
         그 숫자가 맞는지는 거의 상관이 없습니다. */
      function isLow(key) {
        if (checkState(key) === 'conflict') return true;
        if (mode === 'manual') return false;
        // 빈 칸 전부를 "확인 필요" 로 올리면 목록이 열 줄이 됩니다.
        // 없어도 계획이 나오는 칸은 비어 있어도 문제가 아닙니다.
        return v[key] == null && CORE.some(function (f) { return f.key === key; });
      }
      /** 빨간 항목을 부르는 말 */
      function lowWord() { return '확인 필요'; }

      /** 이 칸이 검산에서 어떤 상태인가 — verified | conflict | unchecked */
      function checkState(key) {
        if (!check) return 'unchecked';
        return check.fields[key] || 'unchecked';
      }

      function dotClass(key) {
        var st2 = checkState(key);
        if (st2 === 'conflict') return 'ck-bad';
        if (st2 === 'verified') return 'ck-ok';
        return 'ck-none';
      }

      /* ==================================================================== */
      /* 저장                                                                  */
      /* ==================================================================== */

      function save(where) {
        if (v.weightKg == null || v.smmKg == null || v.bfmKg == null) {
          global.MB_UID.toast('핵심 3종(체중 · 골격근량 · 체지방량)을 먼저 채워 주세요');
          return;
        }
        var scan = buildScan();

        /* 물리적으로 불가능한 값을 저장하지 않습니다.
           예전엔 체지방 90kg / 체중 70kg 같은 입력이 조용히 통과해서
           제지방 -20kg 짜리 계획이 만들어졌습니다.
           거부가 아니라 확인입니다 — 진짜 그 값이면 그대로 저장할 수 있어야 합니다. */
        /* 이전 측정을 같이 넘깁니다. 골격근량은 결과지 안에 짝이 없어서
           단독으로는 19.9kg 폭이 통째로 통과했습니다 — 그 안에서 목표일이
           2년 넘게 벌어져도 경고가 없었습니다. */
        var prevScans = S.sortedScans();
        var prev = prevScans.length ? prevScans[prevScans.length - 1] : null;
        var bad = E.validateScan(scan, prev);
        if (bad && !save.forced) {
          global.MB_MODALS.confirmScan(bad, function () {
            save.forced = true;
            save(where);
          });
          return;
        }
        save.forced = false;
        S.addScan(scan);

        /* 저장이 실제로 기기에 쓰였는지 확인하고 나서 말합니다.
           예전에는 무조건 "저장되었습니다" 라고 했는데, 저장소가 꽉 차면
           조용히 실패했습니다. 사용자는 토스트를 보고 나갔다가 다음에
           들어와서 그 측정이 없는 걸 보게 됩니다 — 앱을 의심하기 전에
           자기 기억을 의심하는 종류의 실패입니다. */
        if (!S.saved()) {
          global.MB_MODALS.saveFailed(v);
          return;
        }
        savedOnce = true;
        S.set({ draft: null });
        global.MB_DRAFT = null;
        global.MB_UID.toast('측정이 저장되었습니다');

        if (where === 'later') { A.go('P02'); return; }
        A.go(S.get().goal ? 'P06' : 'P05');
      }

      function buildScan() {
        var w = v.weightKg, bfm = v.bfmKg;
        var pbf = v.pbfPct, ffm = v.ffmKg, bmi = v.bmi;
        if (pbf == null && w > 0) pbf = round(bfm / w * 100, 1);
        if (ffm == null) ffm = round(w - bfm, 1);
        if (bmi == null && heightM > 0) bmi = round(w / (heightM * heightM), 1);

        return {
          id: makeId(),
          measuredAt: v.measuredAt || nowISO(),
          device: (v.device || '').replace(/^\s+|\s+$/g, '') || null,
          weightKg: w,
          smmKg: v.smmKg,
          bfmKg: bfm,
          pbfPct: pbf,
          bmi: bmi,
          ffmKg: ffm,
          bmrKcal: v.bmrKcal,
          visceralFatLevel: v.visceralFatLevel,
          whr: v.whr,
          inbodyScore: v.inbodyScore,
          tbwL: v.tbwL,
          proteinKg: v.proteinKg,
          mineralKg: v.mineralKg,
          source: origin ? (origin.source || 'manual')
                         : (src.source || (mode === 'ocr' ? 'ocr' : 'manual')),
          /* 사진은 기록에 딸려 다닙니다 — 나중에 기록 화면에서 "그때
             결과지가 어떻게 생겼더라" 를 다시 볼 수 있게. 사진 자체는
             photo.js 의 저장소에 있고 여기엔 열쇠만 둡니다. */
          photoId: src.photoId || (origin && origin.photoId) || null
        };
      }

      /** 'scan-' + 측정일시 숫자 (같은 날 재측정이면 시·분까지 붙인다) */
      function makeId() {
        if (origin && origin.id) return origin.id;
        var digits = String(v.measuredAt || nowISO()).replace(/[^0-9]/g, '');
        if (!digits) digits = String(Date.now());
        var id = 'scan-' + digits.slice(0, 8);

        /* 같은 날 두 번 재는 일은 드물지 않습니다 — 주인 실측만 해도
           하루에 07:36 · 08:35 · 11:09 세 번이 있습니다.
           예전 규칙은 "충돌했는데 측정시각이 다르면" 시·분을 붙였습니다.
           그런데 사진에 EXIF 가 없으면(카톡으로 받은 사진 · 스크린샷 ·
           PNG) 측정시각이 둘 다 'T09:00:00' 으로 똑같이 박혀서, 조건이
           안 맞고 같은 id 가 나왔습니다. 두 번째가 첫 번째를 말없이
           덮어썼습니다.

           지금은 새 측정이면(편집이 아니면) 충돌하는 순간 무조건
           번호를 늘립니다. 덮어쓰기는 "이 기록을 고친다" 고 명시적으로
           들어왔을 때만 일어나야 합니다. */
        var n = 0;
        while (S.scanById(id)) {
          n++;
          id = n === 1 ? 'scan-' + digits.slice(0, 12) : 'scan-' + digits.slice(0, 12) + '-' + n;
          if (n > 50) { id = 'scan-' + digits.slice(0, 12) + '-' + String(S.get().scans.length + 1); break; }
        }
        return id;
      }

      function fieldDef(key) {
        var found = null;
        ALL_FIELDS.forEach(function (f) { if (f.key === key) found = f; });
        return found || { key: key, label: key };
      }

      /** 검산이 가리키는 칸의 한국어 이름 (괄호 약어는 버튼에서 뺍니다) */
      function fieldLabelOf(key) {
        return String(fieldDef(key).label).replace(/\s*\(.*\)\s*$/, '');
      }
    }
  });

  /* ======================================================================== */
  /* 소스 로딩                                                                 */
  /* ======================================================================== */

  /**
   * ctx.params 에 따라 세 가지 진입을 만든다.
   *   scanId → 기존 기록 수정 (신뢰도 전부 1)
   *   ocr    → 판독 초안 (upload.js 의 draft, 없으면 STUB_OCR_RESULT 직접 변환)
   *   manual → 빈 폼 (신뢰도 없음)
   */
  function loadSource(p, st) {
    var values = blankValues();

    if (p.scanId) {
      var scan = S.scanById(p.scanId);
      if (scan) {
        Object.keys(values).forEach(function (k) {
          if (scan[k] != null) values[k] = scan[k];
        });
        return { mode: 'edit', values: values, origin: scan,
                 photoId: scan.photoId || null,
                 rawMeasuredAt: scan.measuredAt, fileName: null, parseMs: null };
      }
    }

    if (p.manual) {
      values.measuredAt = nowISO();
      return { mode: 'manual', values: values, origin: null,
               rawMeasuredAt: values.measuredAt, fileName: null, parseMs: null };
    }

    var draft = (st && st.draft) || global.MB_DRAFT || null;
    if (!draft && p.ocr) draft = draftFromStub(global.MB_DATA.STUB_OCR_RESULT);
    if (draft) {
      Object.keys(values).forEach(function (k) {
        if (draft[k] != null) values[k] = draft[k];
      });
      return { mode: 'ocr', values: values, origin: null,
               photoId: draft.photoId || null,
               /* 같은 검수 화면을 쓰지만 숫자가 어디서 왔는지는 다릅니다.
                  'manual-photo' = 사진을 보면서 사람이 옮겨 적음 (0층)
                  'ocr'          = 서버가 읽어 준 초안 (2층) */
               source: draft.source || 'ocr',
               rawMeasuredAt: draft.measuredAt,
               fileName: draft.ocr && draft.ocr.fileName,
               parseMs: draft.ocr && draft.ocr.parseMs };
    }

    // 아무 단서도 없이 들어온 경우 — 빈 폼으로 취급한다 (막다른 길 방지)
    values.measuredAt = nowISO();
    return { mode: 'manual', values: values, origin: null,
             rawMeasuredAt: values.measuredAt, fileName: null, parseMs: null };
  }

  function blankValues() {
    return {
      measuredAt: null, device: null,
      weightKg: null, smmKg: null, bfmKg: null,
      pbfPct: null, bmi: null, ffmKg: null,
      visceralFatLevel: null, bmrKcal: null, whr: null, inbodyScore: null,
      tbwL: null, proteinKg: null, mineralKg: null
    };
  }

  /** upload.js 를 거치지 않고 P04 로 바로 들어온 경우를 위한 변환 */
  function draftFromStub(ocr) {
    var f = (ocr && ocr.fields) || {};
    var out = { confidence: {}, ocr: { fileName: '내장 샘플 (InBody270 결과지)',
                                       parseMs: (ocr && ocr.parseMs) || null } };
    Object.keys(f).forEach(function (k) {
      out[k] = f[k].value;
      out.confidence[k] = f[k].confidence;
    });
    out.device = 'InBody270';
    return out;
  }

  /* ======================================================================== */
  /* 잡다한 도우미                                                             */
  /* ======================================================================== */

  function modeBadge(src) {
    if (src.mode === 'edit') return '기록 수정';
    if (src.mode !== 'ocr') return '직접 입력';
    // 0층과 2층은 같은 화면을 쓰지만 숫자의 출처가 다릅니다.
    return src.source === 'manual-photo' ? '사진 보고 입력' : '사진 판독';
  }

  function originLine(src) {
    if (src.mode === 'ocr') {
      if (src.source === 'manual-photo') {
        return (src.fileName || '사진') + ' · 숫자는 직접 넣은 것입니다';
      }
      return (src.fileName || '판독본') +
             (src.parseMs ? ' · 판독 ' + (Math.round(src.parseMs / 100) / 10) + '초' : '');
    }
    if (src.mode === 'edit') return '이미 저장된 측정을 고치는 중입니다';
    return '사진 없이 결과지를 보고 직접 넣는 중입니다';
  }

  function parseNum(s) {
    if (s == null) return null;
    var t = String(s).replace(/^\s+|\s+$/g, '');
    if (t === '') return null;
    var n = parseFloat(t);
    return isNaN(n) ? null : n;
  }
  function round(x, d) {
    var m = Math.pow(10, d == null ? 1 : d);
    return Math.round(x * m) / m;
  }
  function fmt(x, dec) {
    if (x == null) return '';
    var d = dec == null ? 1 : dec;
    return String(round(x, d));
  }

  /** ISO → datetime-local 입력값. 시트에 인쇄된 벽시계 시각을 그대로 보여 준다. */
  function isoToLocalInput(iso) {
    if (!iso) return '';
    var m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(String(iso));
    if (m) return m[1] + '-' + m[2] + '-' + m[3] + 'T' + m[4] + ':' + m[5];
    var d = new Date(iso);
    if (isNaN(d.getTime())) return '';
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
           'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }
  /** datetime-local 입력값 → ISO. 원본에 시간대가 있었으면 그 시간대를 유지한다. */
  function localInputToISO(val, rawIso) {
    if (!val) return null;
    var off = /([+-]\d{2}:\d{2}|Z)$/.exec(String(rawIso || ''));
    var suffix = off ? off[1] : tzSuffix();
    var base = val.length === 16 ? val + ':00' : val;
    return base + suffix;
  }
  function tzSuffix() {
    var m = -new Date().getTimezoneOffset();
    var s = m < 0 ? '-' : '+';
    m = Math.abs(m);
    return s + pad(Math.floor(m / 60)) + ':' + pad(m % 60);
  }
  function nowISO() {
    var d = new Date();
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
           'T' + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':00' + tzSuffix();
  }
  function pad(n) { return (n < 10 ? '0' : '') + n; }
})(window);
