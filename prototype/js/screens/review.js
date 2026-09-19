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

  var CONF_HI = 0.85;      // 이상 → 초록
  var CONF_MID = 0.60;     // 이상 → 노랑, 미만 → 빨강(확인 필요)

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
      var conf = src.conf;          // key -> 0~1 | null
      var origin = src.origin;      // 편집 중인 원본 스캔 (없으면 null)

      var touched = {};             // 사람이 손댄 필드 = 확인된 필드
      var rows = {};                // key -> {input, dot, note, err}
      var groups = {};              // uid -> {open, body, badge, btn}
      var warnHost, stateHost, saveBtn, laterBtn;
      var mounted = false;          // 첫 렌더가 끝났는지 (배지 재스캔 범위 결정용)

      /* --- C01 원본 이미지 자리 ------------------------------------------- */
      wrap.appendChild(h('div.card', { uid: 'P04-C01', uidLabel: '원본 결과지 미리보기 자리' }, [
        h('div.card__head', [
          h('div.card__title', { text: '원본 결과지' }),
          h('span.badge' + (mode === 'ocr' ? '.badge--accent' : ''), { text: modeBadge(mode) })
        ]),
        h('div.skeleton', { style: { height: '120px', marginBottom: '8px' } }),
        h('div.muted', { text: '원본 미리보기 (프로토타입에서는 생략)' }),
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

        /* 2) 자동 검증 배너 */
        drawWarnings();

        /* 3) 그룹 헤더의 "확인 필요" 개수 */
        updateGroupBadge('P04-C04', DERIVED);
        updateGroupBadge('P04-C05', COMPOSITION);

        /* 4) 필수 3종 + 저장 버튼 */
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
          h('div.card__title', { text: '자동 검증' }),
          h('div.card__sub', { text: '숫자끼리 서로 맞는지 계산해 봤습니다' })
        ]));

        var W = computeWarnings();
        if (W.length) {
          W.forEach(function (w) {
            warnHost.appendChild(h('div.note.note--' + (w.bad ? 'bad' : 'warn'),
              { style: { marginBottom: '8px' } }, [
              h('b', { text: w.title }),
              h('div', { style: { marginTop: '4px' }, text: w.detail }),
              h('button.btn.btn--sm', {
                text: '계산값으로 맞추기', style: { marginTop: '8px' },
                uid: 'P04-B07', uidLabel: '계산값으로 맞추기',
                onClick: w.fix
              })
            ]));
          });
        } else if (v.weightKg != null && v.bfmKg != null) {
          warnHost.appendChild(h('div.note.note--ok',
            { text: '숫자끼리 서로 맞습니다. 판독값과 계산값 사이에 모순이 없습니다.' }));
        } else {
          warnHost.appendChild(h('div.note',
            { text: '체중과 체지방량이 들어오면 나머지 숫자와 맞는지 여기서 바로 검사합니다.' }));
        }

        /* 확인 필요 항목 바로가기 — 못 읽은 값이 접힌 그룹 안에 숨지 않게 */
        var lowKeys = ALL_FIELDS.filter(function (f) { return isLow(f.key); })
          .map(function (f) { return f.key; });
        if (mode !== 'manual' && lowKeys.length) {
          warnHost.appendChild(h('div', { style: { marginTop: '10px' } }, [
            h('div.section-title', { text: lowWord() + ' ' + lowKeys.length + '개' }),
            h('div.chips', lowKeys.map(function (k) {
              var f = fieldDef(k);
              var why = mode === 'ocr'
                ? (v[k] == null ? ' · 못 읽음' : ' · 신뢰도 낮음')
                : ' · 비어 있음';
              return h('button.chip', {
                text: f.label + why,
                uid: 'P04-B09', uidLabel: '확인 필요 항목 바로가기',
                onClick: function () { focusField(k); }
              });
            }))
          ]));
        }

        if (mode === 'ocr') {
          warnHost.appendChild(h('div.muted', { style: { marginTop: '10px' },
            text: '● 신뢰도 — 초록: 잘 읽음 · 노랑: 보통 · 빨강: 확인 필요' }));
        } else if (mode === 'edit') {
          warnHost.appendChild(h('div.muted', { style: { marginTop: '10px' },
            text: '● 초록: 값이 들어 있음 · 빨강: 아직 비어 있음 (판독한 기록이 아니라 저장된 기록입니다)' }));
        }
      }

      /** 판독값 vs 계산값 모순 — 모달이 아니라 화면 안에서 바로 지적한다 */
      function computeWarnings() {
        var W = [];
        var w = v.weightKg, smm = v.smmKg, bfm = v.bfmKg;
        var pbf = v.pbfPct, ffm = v.ffmKg, bmi = v.bmi;

        // (1) 체지방률 ↔ 체지방량/체중
        if (w != null && w > 0 && bfm != null && pbf != null) {
          var calcPbf = bfm / w * 100;
          if (Math.abs(pbf - calcPbf) > 2.0) {
            W.push({
              title: '체지방률이 계산값과 어긋납니다',
              detail: '체지방량 ' + UI.n1(bfm) + 'kg ÷ 체중 ' + UI.n1(w) + 'kg = ' +
                      UI.n1(calcPbf) + '% 인데, 입력된 체지방률은 ' + UI.n1(pbf) + '% 입니다 (' +
                      UI.n1(Math.abs(pbf - calcPbf)) + '%p 차이).',
              fix: function () { setValue('pbfPct', round(calcPbf, 1)); }
            });
          }
        }

        // (2) 제지방량 ↔ 체중 − 체지방량
        if (w != null && bfm != null && ffm != null) {
          var calcFfm = w - bfm;
          if (Math.abs(ffm - calcFfm) > 1.0) {
            W.push({
              title: '제지방량이 계산값과 어긋납니다',
              detail: '체중 ' + UI.n1(w) + 'kg − 체지방량 ' + UI.n1(bfm) + 'kg = ' +
                      UI.n1(calcFfm) + 'kg 인데, 입력된 제지방량은 ' + UI.n1(ffm) + 'kg 입니다 (' +
                      UI.n1(Math.abs(ffm - calcFfm)) + 'kg 차이).',
              fix: function () { setValue('ffmKg', round(calcFfm, 1)); }
            });
          }
        }

        // (3) 골격근량 > 제지방량 — 있을 수 없는 값
        if (smm != null && ffm != null && smm > ffm) {
          W.push({
            bad: true,
            title: '골격근량이 제지방량보다 큽니다',
            detail: '골격근량 ' + UI.n1(smm) + 'kg 은 제지방량 ' + UI.n1(ffm) +
                    'kg 안에 포함되는 값이라 더 클 수 없습니다. 둘 중 하나를 잘못 읽었습니다.',
            fix: function () {
              if (v.weightKg != null && v.bfmKg != null) {
                var recalc = round(v.weightKg - v.bfmKg, 1);
                setValue('ffmKg', recalc);
                if (v.smmKg != null && v.smmKg > recalc) {
                  focusField('smmKg');
                  global.MB_UID.toast('제지방량을 다시 계산해도 골격근량이 더 큽니다 — 골격근량을 결과지와 대조해 주세요');
                }
              } else {
                focusField('smmKg');
                global.MB_UID.toast('체중·체지방량이 있어야 제지방량을 계산할 수 있습니다');
              }
            }
          });
        }

        // (4) BMI ↔ 체중 / 키²
        if (w != null && bmi != null && heightM > 0) {
          var calcBmi = w / (heightM * heightM);
          if (Math.abs(bmi - calcBmi) > 1.0) {
            W.push({
              title: 'BMI가 계산값과 어긋납니다',
              detail: '키 ' + UI.n0(prof.heightCm) + 'cm · 체중 ' + UI.n1(w) + 'kg 이면 BMI는 ' +
                      UI.n1(calcBmi) + ' 인데, 입력된 BMI는 ' + UI.n1(bmi) + ' 입니다. ' +
                      '프로필의 키가 ' + UI.n0(prof.heightCm) + 'cm가 맞는지도 확인해 주세요.',
              fix: function () { setValue('bmi', round(calcBmi, 1)); }
            });
          }
        }
        return W;
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
        conf[key] = 1;
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
        if (isLow(key)) {
          /* 'ocr' 은 판독이 실패한 칸, 'edit' 은 애초에 안 들어 있던 칸 —
             같은 빨간 점이라도 사실이 다르므로 말도 달라야 한다 */
          if (mode === 'ocr') {
            r.note.className = 'field__err';
            r.note.textContent = v[key] == null
              ? '확인 필요 — 판독하지 못했습니다. 결과지를 보고 직접 넣어 주세요.'
              : '확인 필요 — 자신 있게 읽지 못한 값입니다.';
          } else {
            r.note.className = 'field__hint';
            r.note.textContent = '비어 있음 — 결과지에 있으면 채워 주세요. 없어도 저장됩니다.';
          }
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

      /* --- 신뢰도 ---------------------------------------------------------- */
      function confOf(key) {
        if (v[key] == null || v[key] === '') return 0;       // 값이 없으면 확인 필요
        var c = conf[key];
        if (c == null) return CONF_MID;                       // 판독 대상이 아니었던 값
        return c;
      }
      function isLow(key) { return mode !== 'manual' && confOf(key) < CONF_MID; }
      /** 빨간 항목을 부르는 말 — 판독본이면 '확인 필요', 저장된 기록이면 '비어 있음' */
      function lowWord() { return mode === 'ocr' ? '확인 필요' : '비어 있음'; }
      function dotClass(key) {
        var c = confOf(key);
        return c >= CONF_HI ? 'hi' : (c >= CONF_MID ? 'mid' : 'lo');
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
        S.addScan(scan);
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
          source: origin ? (origin.source || 'manual') : (mode === 'ocr' ? 'ocr' : 'manual')
        };
      }

      /** 'scan-' + 측정일시 숫자 (같은 날 재측정이면 시·분까지 붙인다) */
      function makeId() {
        if (origin && origin.id) return origin.id;
        var digits = String(v.measuredAt || nowISO()).replace(/[^0-9]/g, '');
        if (!digits) digits = String(Date.now());
        var id = 'scan-' + digits.slice(0, 8);
        var clash = S.scanById(id);
        if (clash && clash.measuredAt !== v.measuredAt) id = 'scan-' + digits.slice(0, 12);
        return id;
      }

      function fieldDef(key) {
        var found = null;
        ALL_FIELDS.forEach(function (f) { if (f.key === key) found = f; });
        return found || { key: key, label: key };
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
    var conf = {};

    if (p.scanId) {
      var scan = S.scanById(p.scanId);
      if (scan) {
        Object.keys(values).forEach(function (k) {
          if (scan[k] != null) values[k] = scan[k];
        });
        Object.keys(values).forEach(function (k) { conf[k] = scan[k] == null ? null : 1; });
        return { mode: 'edit', values: values, conf: conf, origin: scan,
                 rawMeasuredAt: scan.measuredAt, fileName: null, parseMs: null };
      }
    }

    if (p.manual) {
      Object.keys(values).forEach(function (k) { conf[k] = null; });
      values.measuredAt = nowISO();
      return { mode: 'manual', values: values, conf: conf, origin: null,
               rawMeasuredAt: values.measuredAt, fileName: null, parseMs: null };
    }

    var draft = (st && st.draft) || global.MB_DRAFT || null;
    if (!draft && p.ocr) draft = draftFromStub(global.MB_DATA.STUB_OCR_RESULT);
    if (draft) {
      Object.keys(values).forEach(function (k) {
        if (draft[k] != null) values[k] = draft[k];
        conf[k] = draft.confidence && draft.confidence[k] != null ? draft.confidence[k] : null;
      });
      conf.measuredAt = draft.confidence && draft.confidence.measuredAt != null
        ? draft.confidence.measuredAt : null;
      return { mode: 'ocr', values: values, conf: conf, origin: null,
               rawMeasuredAt: draft.measuredAt,
               fileName: draft.ocr && draft.ocr.fileName,
               parseMs: draft.ocr && draft.ocr.parseMs };
    }

    // 아무 단서도 없이 들어온 경우 — 빈 폼으로 취급한다 (막다른 길 방지)
    Object.keys(values).forEach(function (k) { conf[k] = null; });
    values.measuredAt = nowISO();
    return { mode: 'manual', values: values, conf: conf, origin: null,
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

  function modeBadge(mode) {
    if (mode === 'ocr') return '사진 판독';
    if (mode === 'edit') return '기록 수정';
    return '직접 입력';
  }

  function originLine(src) {
    if (src.mode === 'ocr') {
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
