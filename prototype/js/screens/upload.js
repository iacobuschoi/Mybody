/* =============================================================================
 * P03 — 인바디 결과지 넣기
 *
 * 판독은 3층으로 되어 있고, 이 화면은 0층과 2층의 입구입니다.
 *
 *   0층  사진을 띄워 놓고 숫자 세 개를 손으로 넣는다   ← 바닥. 항상 된다.
 *   1층  넣은 값을 결과지 안의 다른 값과 검산한다      ← crosscheck.js
 *   2층  서버에 사진을 보내 초안을 받는다              ← 켜야만 돈다
 *
 * 왜 0층이 기본인가
 *   결과지에서 플래너가 실제로 쓰는 숫자는 세 개뿐입니다 — 체중,
 *   골격근량, 체지방량. 사진을 보면서 세 칸을 채우는 데 15초쯤
 *   걸립니다. 브라우저 OCR(tesseract)은 손에 든 사진 조건에서 31건 중
 *   0건, 13건 중 0건을 맞췄고 모델 파일만 10~15MB 입니다. 15초를
 *   아끼려고 그걸 받게 할 수는 없습니다.
 *
 *   그리고 2층이 아무리 좋아져도 0층은 남습니다. 서버가 죽어도,
 *   비행기 안이어도, 결과지가 처음 보는 양식이어도 숫자는 들어가야
 *   하니까요.
 *
 * 사진은 이 기기에만 남습니다. 2층을 사용자가 직접 켤 때만 나갑니다.
 * ========================================================================== */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var MAX_BYTES = 12 * 1024 * 1024;           // 고르는 단계의 한도 (줄이기 전)
  var STEP_MS = 700;
  var STEPS = ['이미지 보정', '표 영역 검출', '숫자 인식', '검산'];
  var LOW_CONF = 0.70;

  var FIELD_LABELS = {
    measuredAt: '측정일시', weightKg: '체중', smmKg: '골격근량', bfmKg: '체지방량',
    pbfPct: '체지방률', bmi: 'BMI', ffmKg: '제지방량', bmrKcal: '기초대사량',
    visceralFatLevel: '내장지방 레벨', whr: '복부지방률', inbodyScore: 'InBody 점수',
    tbwL: '체수분', proteinKg: '단백질', mineralKg: '무기질', idealWeightKg: '적정체중'
  };

  /* 0층이 묻는 세 칸. 결과지에서 순서대로 붙어 있는 칸들이라
     눈이 위에서 아래로 한 번만 내려가면 됩니다. */
  var QUICK = [
    { key: 'weightKg', uid: 'P03-F02', label: '체중', unit: 'kg', hint: '골격근·지방분석 맨 윗줄' },
    { key: 'smmKg', uid: 'P03-F03', label: '골격근량', unit: 'kg', hint: '그 아래, SMM' },
    { key: 'bfmKg', uid: 'P03-F04', label: '체지방량', unit: 'kg', hint: '그 아래, BFM — %가 아니라 kg' }
  ];

  /* --- 화면 로컬 상태 (render() 진입 때마다 초기화) ------------------------ */
  var mode = 'idle';        // idle | shot | parsing | error
  var step = 0;
  var sourceName = '';
  var timers = [];
  var shot = null;          // { dataUrl, w, h, bytes, name, exifAt, id }
  var quick = {};           // 빠른 입력 중인 값
  var quickAt = '';         // 측정일 (yyyy-mm-dd)

  function clearTimers() { while (timers.length) { clearTimeout(timers.pop()); } }

  A.register('P03', {
    title: '인바디 올리기', label: '인바디 사진 업로드',
    render: function (wrap, ctx) {
      clearTimers();
      mode = 'idle'; step = 0; sourceName = '';
      shot = null; quick = {}; quickAt = todayLocal();

      var fileInput = null;
      var serverExtra = null;     // 2층이 돌려준 나머지 칸들 (검수 화면으로 넘어감)
      var body = h('div');
      wrap.appendChild(body);
      draw();

      /* --- 그리기 --------------------------------------------------------- */
      function draw() {
        UI.clear(body);

        if (mode === 'parsing') drawParsing();
        else if (mode === 'error') drawError();
        else if (mode === 'shot') drawShot();
        else drawIdle();

        /* C03 개인정보 안내 — 모든 상태에서 계속 보인다 */
        body.appendChild(h('div.note', {
          uid: 'P03-C03', uidLabel: '개인정보 안내',
          text: privacyLine()
        }));

        if (mode !== 'parsing' && mode !== 'shot') {
          var last = S.latestScan();
          if (last) body.appendChild(recentCard(last));
        }

        if (global.MB_UID && body.isConnected) global.MB_UID.scan(body);
      }

      /* --- idle ----------------------------------------------------------- */
      function drawIdle() {
        var zone;

        fileInput = h('input.input', {
          type: 'file', accept: 'image/*',
          uid: 'P03-F01', uidLabel: '결과지 파일 입력',
          style: { marginTop: '10px', fontSize: '12px' },
          onChange: function () {
            var f = fileInput.files && fileInput.files[0];
            fileInput.value = '';
            handleFile(f);
          }
        });

        zone = h('div.card.card--flat', {
          uid: 'P03-C01', uidLabel: '드래그앤드롭 존',
          style: { border: '2px dashed var(--border)', cursor: 'pointer' },
          onClick: function (e) { if (e.target !== fileInput) fileInput.click(); },
          onDragOver: function (e) { e.preventDefault(); zone.style.borderColor = 'var(--accent)'; },
          onDragLeave: function () { zone.style.borderColor = 'var(--border)'; },
          onDrop: function (e) {
            e.preventDefault();
            zone.style.borderColor = 'var(--border)';
            var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
            if (!f) { global.MB_MODALS.fileError('끌어다 놓은 항목에서 사진을 찾지 못했습니다.'); return; }
            handleFile(f);
          }
        }, [
          h('div.empty', { style: { padding: '22px 8px' } }, [
            h('div.empty__ico', { text: '🖼️' }),
            h('div.empty__t', { text: '결과지 사진을 넣으세요' }),
            h('div.empty__d', { text: '사진을 띄워 놓고 숫자 세 개만 옮겨 적으면 끝입니다. 15초쯤 걸립니다.' }),
            fileInput
          ])
        ]);
        body.appendChild(zone);

        body.appendChild(h('div.card', { uid: 'P03-C02', uidLabel: '촬영 가이드 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '잘 찍는 법' }),
            h('div.card__sub', { text: '나중에 다시 볼 사진입니다' })
          ]),
          h('ul', { style: { paddingLeft: '18px', margin: '0',
                             fontSize: '13px', color: 'var(--text-2)' } }, [
            h('li', { text: '표 전체가 프레임 안에 들어오게' }),
            h('li', { text: '정면에서, 기울이지 말고' }),
            h('li', { text: '형광등 반사·그림자 없이' })
          ]),
          h('div.note', { style: { marginTop: '10px' },
            text: '영수증형(감열지) 결과지는 시간이 지나면 글씨가 날아갑니다. 받은 날 바로 찍어두세요.' })
        ]));

        body.appendChild(h('div.btn-row.btn-row--stack', [
          h('div.btn-row', [
            h('button.btn.btn--primary', {
              text: '📷 사진 촬영', uid: 'P03-B01', uidLabel: '사진 촬영',
              onClick: function () {
                global.MB_MODALS.cameraGuide(function () { fileInput.click(); });
              }
            }),
            h('button.btn.btn--primary', {
              text: '📁 파일 선택', uid: 'P03-B02', uidLabel: '파일 선택',
              onClick: function () { fileInput.click(); }
            })
          ]),
          h('button.btn.btn--block', {
            text: '사진 없이 직접 입력', uid: 'P03-B04', uidLabel: '사진 없이 직접 입력',
            onClick: goManual
          }),
          h('button.btn.btn--ghost.btn--block', {
            text: '내장 샘플로 판독 (프로토타입)',
            uid: 'P03-B03', uidLabel: '내장 샘플로 판독',
            onClick: function () { startParsing('내장 샘플 (InBody270 결과지)'); }
          })
        ]));

        body.appendChild(h('div', { style: { textAlign: 'center', marginTop: '2px' } }, [
          h('button.btn.btn--ghost.btn--sm', {
            text: '판독 실패 화면 보기 (프로토타입)',
            uid: 'P03-B09', uidLabel: '판독 실패 시연',
            onClick: fail
          })
        ]));
      }

      /* --- shot: 0층 ------------------------------------------------------ */
      function drawShot() {
        /* 사진 — 누르면 크게. 숫자를 옮겨 적는 동안 계속 보여야 합니다. */
        body.appendChild(h('div.card.card--flat', {
          uid: 'P03-C05', uidLabel: '결과지 사진',
          style: { padding: '8px' }
        }, [
          h('img', {
            src: shot.dataUrl, alt: '올린 결과지',
            uid: 'P03-B14', uidLabel: '사진 크게 보기',
            style: { width: '100%', borderRadius: '10px', display: 'block',
                     cursor: 'zoom-in', background: 'var(--bg-2)' },
            onClick: function () { global.MB_MODALS.photoZoom(shot.dataUrl); }
          }),
          h('div', { style: { display: 'flex', justifyContent: 'space-between',
                              alignItems: 'center', marginTop: '6px' } }, [
            h('span.muted', { style: { fontSize: '11px' },
              text: shot.w + '×' + shot.h + ' · ' + Math.round(shot.bytes / 1024) + 'KB · 이 기기에만' }),
            h('div.btn-row', { style: { margin: '0' } }, [
              h('button.btn.btn--ghost.btn--sm', {
                text: '바꾸기', uid: 'P03-B10', uidLabel: '사진 바꾸기',
                onClick: function () { mode = 'idle'; shot = null; draw(); }
              }),
              h('button.btn.btn--ghost.btn--sm', {
                text: '빼기', uid: 'P03-B11', uidLabel: '사진 빼기',
                onClick: function () {
                  if (shot && shot.id) global.MB_PHOTO.remove(shot.id);
                  shot = null; mode = 'idle'; draw();
                  global.MB_UID.toast('사진을 지웠습니다');
                }
              })
            ])
          ])
        ]));

        /* 빠른 입력 — 세 칸 */
        var checkHost = h('div', { style: { marginTop: '4px' } });
        var card = h('div.card.card--accent', { uid: 'P03-C06', uidLabel: '빠른 입력 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '숫자 세 개만' }),
            h('div.card__sub', { text: '사진을 보면서 옮겨 적으세요. 나머지는 다음 화면에서.' })
          ])
        ]);
        QUICK.forEach(function (f) { card.appendChild(quickRow(f, refreshCheck)); });
        card.appendChild(dateRow());
        card.appendChild(checkHost);
        card.appendChild(h('button.btn.btn--primary.btn--block', {
          text: '검수 화면으로 →', uid: 'P03-B12', uidLabel: '빠른 입력 저장',
          style: { marginTop: '10px' },
          onClick: function () { toReview(); }
        }));
        body.appendChild(card);

        /* 2층 — 서버에 맡기기. 켜져 있을 때만 버튼이 나옵니다. */
        body.appendChild(serverCard());

        refreshCheck();

        function refreshCheck() {
          UI.clear(checkHost);
          var st = S.get();
          var prof = st.profile || global.MB_DATA.SEED_PROFILE;
          var filled = QUICK.filter(function (f) { return quick[f.key] != null; }).length;
          if (filled < 2) {
            checkHost.appendChild(h('div.muted', { style: { fontSize: '12px' },
              text: '두 칸 이상 채우면 결과지 안에서 서로 맞는지 바로 검산합니다.' }));
            return;
          }
          var draft = { measuredAt: quickISO() };
          QUICK.forEach(function (f) { if (quick[f.key] != null) draft[f.key] = quick[f.key]; });
          var prev = S.latestScan();
          var r = global.MB_CHECK.run(draft, prof, prev);
          checkHost.appendChild(checkSummary(r, 'P03-G01', '검산 요약'));
        }
      }

      function quickRow(f, onChange) {
        var input = h('input.input', {
          type: 'text', inputMode: 'decimal',
          uid: f.uid, uidLabel: f.label,
          placeholder: '0.0',
          value: quick[f.key] != null ? String(quick[f.key]) : '',
          style: { textAlign: 'right', fontSize: '20px', fontWeight: '700',
                   fontVariantNumeric: 'tabular-nums' },
          onInput: function () {
            var raw = input.value.replace(/[^\d.]/g, '');
            if (raw !== input.value) input.value = raw;
            var x = parseFloat(raw);
            quick[f.key] = isFinite(x) && raw !== '' ? x : null;
            onChange();
          }
        });
        return h('div.field', [
          h('label.field__l', { text: f.label }),
          h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, [
            input,
            h('span.muted', { style: { fontSize: '14px', minWidth: '24px' }, text: f.unit })
          ]),
          h('div.field__hint', { text: f.hint })
        ]);
      }

      function dateRow() {
        var input = h('input.input', {
          type: 'date', value: quickAt, uid: 'P03-F05', uidLabel: '측정일',
          onChange: function () { quickAt = input.value || todayLocal(); }
        });
        return h('div.field', [
          h('label.field__l', { text: '측정일' }),
          input,
          h('div.field__hint', {
            text: shot && shot.exifAt
              ? '사진을 찍은 날(' + UI.dateShort(shot.exifAt) + ')로 채웠습니다. 다르면 고쳐 주세요.'
              : '결과지에 찍힌 날짜입니다. 오늘이 아니면 고쳐 주세요.'
          })
        ]);
      }

      /* --- parsing -------------------------------------------------------- */
      function drawParsing() {
        body.appendChild(h('div.card', { uid: 'P03-S01', uidLabel: '판독 중 상태' }, [
          h('div.card__head', [
            h('div.card__title', { text: '판독 중…' }),
            h('div.card__sub', { text: sourceName })
          ]),
          h('div.skeleton', { style: { height: '84px' } }),
          h('div.progress-steps', { uid: 'P03-L01', uidLabel: '판독 단계 목록' },
            STEPS.map(function (label, i) {
              var cls = i < step ? '.is-done' : (i === step ? '.is-active' : '');
              return h('div.pstep' + cls, [
                h('div.pstep__dot', { text: i < step ? '✓' : String(i + 1) }),
                h('span', { text: (i + 1) + '. ' + label })
              ]);
            })),
          h('div.muted', { text: '판독이 끝나도 검수 화면에서 한 번 보셔야 합니다.' }),
          h('button.btn.btn--ghost.btn--block', {
            text: '취소', uid: 'P03-B05', uidLabel: '판독 취소',
            style: { marginTop: '12px' },
            onClick: function () {
              clearTimers();
              mode = shot ? 'shot' : 'idle'; step = 0;
              draw();
              global.MB_UID.toast('판독을 취소했습니다');
            }
          })
        ]));
      }

      /* --- error ---------------------------------------------------------- */
      function drawError() {
        body.appendChild(h('div.empty', { uid: 'P03-S02', uidLabel: '판독 실패 상태' }, [
          h('div.empty__ico', { text: '🔍' }),
          h('div.empty__t', { text: '결과지를 찾지 못했습니다' }),
          h('div.empty__d', { text: '초점이 흐리거나 표 일부가 잘렸을 가능성이 높습니다. 숫자는 직접 넣으면 됩니다.' }),
          h('div.btn-row', [
            h('button.btn', {
              text: '다시 올리기', uid: 'P03-B07', uidLabel: '다시 올리기',
              onClick: function () { mode = 'idle'; step = 0; shot = null; draw(); }
            }),
            h('button.btn.btn--primary', {
              text: shot ? '사진 보며 직접 넣기' : '직접 입력',
              uid: 'P03-B08', uidLabel: '직접 입력으로 전환',
              onClick: function () {
                if (shot) { mode = 'shot'; draw(); } else goManual();
              }
            })
          ])
        ]));
      }

      /* --- 2층: 서버 판독 -------------------------------------------------- */
      function serverCard() {
        var can = global.MB_SYNC && global.MB_SYNC.canOcr && global.MB_SYNC.canOcr();
        if (!can) {
          return h('div.note', { uid: 'P03-S03', uidLabel: '서버 판독 꺼짐 안내' }, [
            h('b', { text: '자동 판독은 꺼져 있습니다' }),
            h('div', { style: { marginTop: '4px' },
              text: '켜면 사진이 내가 지정한 서버로 올라가고, 거기서 숫자 초안을 만들어 돌려줍니다. ' +
                    '설정 → 서버에서 켤 수 있습니다. 켜도 검수 화면은 그대로 거칩니다.' })
          ]);
        }
        return h('div.card.card--flat', { uid: 'P03-C07', uidLabel: '서버 판독 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '자동으로 읽어 볼까요' }),
            h('div.card__sub', { text: '사진이 내 서버로 올라갑니다' })
          ]),
          h('div.muted', { style: { marginBottom: '8px' },
            text: '돌려받은 숫자는 그대로 쓰지 않습니다. 결과지 안에서 검산이 맞는 것만 초록으로 표시하고, ' +
                  '어긋나면 그 칸을 짚어 줍니다.' }),
          h('button.btn.btn--block', {
            text: '서버에 판독 맡기기', uid: 'P03-B13', uidLabel: '서버에 판독 맡기기',
            onClick: askServer
          })
        ]);
      }

      function askServer() {
        if (!shot) return;
        clearTimers();
        sourceName = '서버 판독 · ' + (shot.name || '사진');
        mode = 'parsing'; step = 0;
        draw();
        // 진행 표시는 앞 단계까지만 올려 두고, 마지막 칸은 응답이 채웁니다.
        for (var i = 1; i < STEPS.length; i++) tick(i, true);

        global.MB_SYNC.ocr(shot.dataUrl, function (err, fields) {
          clearTimers();
          if (A.current !== 'P03' || !body.isConnected) return;
          if (err) {
            mode = 'shot'; draw();
            global.MB_UID.toast('자동 판독에 실패했습니다 — 직접 넣으시면 됩니다');
            return;
          }
          QUICK.forEach(function (f) {
            if (fields[f.key] != null) quick[f.key] = fields[f.key];
          });
          if (fields.measuredAt) quickAt = String(fields.measuredAt).slice(0, 10);
          serverExtra = fields;
          mode = 'shot'; draw();
          global.MB_UID.toast('판독했습니다 — 사진과 대조해 주세요');
        });
      }

      /* --- 상태 전환 ------------------------------------------------------- */
      function handleFile(file) {
        if (!file) return;
        if (!isImage(file)) {
          global.MB_MODALS.fileError('JPG · PNG · HEIC 형식의 사진만 올릴 수 있습니다.');
          return;
        }
        if (file.size > MAX_BYTES) {
          global.MB_MODALS.fileError('이 파일은 ' + UI.n1(file.size / 1024 / 1024) +
                                     'MB 입니다. 12MB 이하만 올릴 수 있습니다.');
          return;
        }
        global.MB_PHOTO.fromFile(file, function (err, out) {
          if (A.current !== 'P03' || !body.isConnected) return;
          if (err) { global.MB_MODALS.fileError(err.message); return; }
          var id = 'shot-' + Date.now();
          global.MB_PHOTO.save(id, out.dataUrl, { w: out.w, h: out.h, name: out.name });
          shot = { dataUrl: out.dataUrl, w: out.w, h: out.h, bytes: out.bytes,
                   name: out.name, exifAt: out.exifAt || null, id: id };
          if (out.exifAt) quickAt = String(out.exifAt).slice(0, 10);
          serverExtra = null;
          mode = 'shot'; step = 0;
          draw();
        });
      }

      function startParsing(name) {
        clearTimers();
        sourceName = name || '내장 샘플';
        mode = 'parsing'; step = 0;
        draw();
        for (var i = 1; i <= STEPS.length; i++) tick(i);
      }

      function tick(n, hold) {
        timers.push(setTimeout(function () {
          if (A.current !== 'P03' || !body.isConnected) { clearTimers(); return; }
          step = n;
          if (n < STEPS.length || hold) draw(); else finish();
        }, STEP_MS * n));
      }

      function finish() {
        clearTimers();
        mode = 'idle'; step = 0;

        var draft = buildDraft(global.MB_DATA.STUB_OCR_RESULT, sourceName);
        S.set({ draft: draft });
        global.MB_DRAFT = draft;

        var before = A.current;
        A.go('P04', { ocr: true });
        if (A.current === before) {
          draw();
          global.MB_UID.toast('판독 결과를 저장했습니다 — 검수 화면(P04)은 준비 중입니다');
        }
      }

      /** 0층 → 검수 화면. 세 칸 중 둘만 있어도 넘어갑니다 — 나머지는 거기서. */
      function toReview() {
        var have = QUICK.filter(function (f) { return quick[f.key] != null; });
        if (!have.length) {
          global.MB_UID.toast('숫자를 하나라도 넣어 주세요');
          return;
        }
        var draft = {
          id: 'scan-' + compactDate(quickISO()),
          measuredAt: quickISO(),
          source: 'manual-photo',
          device: '',
          partial: false,
          photoId: shot ? shot.id : null,
          confidence: {},
          lowConfidenceFields: [],
          ocr: shot ? { fileName: shot.name || '사진', rawText: '',
                        parseMs: 0, parsedAt: new Date().toISOString() } : null
        };
        QUICK.forEach(function (f) { draft[f.key] = quick[f.key] != null ? quick[f.key] : null; });
        /* 2층이 읽어 준 나머지 칸들도 같이 넘깁니다. 핵심 세 칸은 위에서
           덮어썼으니, 사용자가 고친 값이 서버 값을 이깁니다. */
        if (serverExtra) {
          Object.keys(FIELD_LABELS).forEach(function (k) {
            if (draft[k] == null && serverExtra[k] != null) draft[k] = serverExtra[k];
          });
          draft.source = 'ocr';
        }
        S.set({ draft: draft });
        global.MB_DRAFT = draft;
        var before = A.current;
        A.go('P04', { ocr: true });
        if (A.current === before) global.MB_UID.toast('검수 화면(P04)은 준비 중입니다');
      }

      function fail() {
        clearTimers();
        mode = 'error'; step = 0;
        draw();
        global.MB_MODALS.parseFailed(
          function () { mode = 'idle'; shot = null; draw(); },
          function () { if (shot) { mode = 'shot'; draw(); } else goManual(); }
        );
      }

      function quickISO() {
        var d = quickAt || todayLocal();
        // 사진에서 시각까지 읽었으면 그대로 씁니다 — 같은 날 두 번 잰
        // 경우에 순서가 살아납니다.
        if (shot && shot.exifAt && String(shot.exifAt).slice(0, 10) === d) return shot.exifAt;
        return d + 'T09:00:00';
      }
    }
  });

  /* --- 조각 --------------------------------------------------------------- */

  /** 1층 결과를 한 덩어리로 — 0층에서도, 검수 화면에서도 같은 말을 합니다. */
  function checkSummary(r, uid, uidLabel) {
    var tone = r.status === 'conflict' ? '.note--bad'
             : (r.status === 'review' ? '.note--warn' : '.note--ok');
    var bad = r.checks.filter(function (c) { return !c.ok; });
    var box = h('div.note' + tone, uid ? { uid: uid, uidLabel: uidLabel || '검산 요약' } : {}, [
      h('b', { text: r.status === 'conflict' ? '결과지 안에서 숫자가 어긋납니다'
                   : (r.status === 'review' ? '한 번 확인해 주세요'
                   : '검산 ' + r.counts.pass + '개가 맞아떨어집니다') })
    ]);
    bad.slice(0, 2).forEach(function (c) {
      box.appendChild(h('div', { style: { marginTop: '4px', fontSize: '12px' },
        text: '· ' + c.why }));
    });
    r.rangeIssues.concat(r.deltaIssues).slice(0, 2).forEach(function (i) {
      box.appendChild(h('div', { style: { marginTop: '4px', fontSize: '12px' },
        text: '· ' + i.why }));
    });
    if (r.status === 'ok' && r.counts.pass) {
      box.appendChild(h('div', { style: { marginTop: '4px', fontSize: '12px' },
        text: r.checks.filter(function (c) { return c.ok; })
               .map(function (c) { return c.label; }).slice(0, 3).join(' · ') }));
    }
    return box;
  }

  function privacyLine() {
    var on = global.MB_SYNC && global.MB_SYNC.canOcr && global.MB_SYNC.canOcr();
    return on
      ? '사진은 이 기기에 저장되고, 자동 판독을 누를 때만 내 서버로 올라갑니다. 수치는 로그인했다면 내 서버로 올라갑니다.'
      : '사진은 이 기기에만 저장됩니다. 수치는 로그인했다면 내가 지정한 서버로 올라갑니다.';
  }

  function todayLocal() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') +
           '-' + String(d.getDate()).padStart(2, '0');
  }

  function goManual() {
    navigate('P04', { manual: true }, '직접 입력 화면(P04)은 준비 중입니다');
  }

  function navigate(id, params, fallbackMsg) {
    var before = A.current;
    A.go(id, params);
    if (A.current === before && fallbackMsg) global.MB_UID.toast(fallbackMsg);
  }

  function isImage(file) {
    if (!file) return false;
    if (file.type && file.type.indexOf('image/') === 0) return true;
    return /\.(jpe?g|png|heic|heif|webp)$/i.test(file.name || '');
  }

  /** STUB_OCR_RESULT → 검수 화면(P04)이 받을 스캔 초안 */
  function buildDraft(ocr, sourceName) {
    var f = (ocr && ocr.fields) || {};
    function val(k) { return f[k] && f[k].value != null ? f[k].value : null; }
    function conf(k) { return f[k] ? f[k].confidence : 0; }

    var measuredAt = val('measuredAt') || new Date().toISOString();
    var weightKg = val('weightKg');
    var pbfPct = val('pbfPct');
    var bfmKg = val('bfmKg');
    if (bfmKg == null && weightKg != null && pbfPct != null) {
      bfmKg = Math.round(weightKg * pbfPct / 100 * 10) / 10;
    }

    var confidence = {};
    var low = [];
    Object.keys(f).forEach(function (k) {
      confidence[k] = conf(k);
      if (val(k) == null || conf(k) < LOW_CONF) low.push(FIELD_LABELS[k] || k);
    });

    return {
      id: 'scan-' + compactDate(measuredAt),
      measuredAt: measuredAt,
      source: 'ocr',
      device: 'InBody270',
      partial: false,
      weightKg: weightKg,
      smmKg: val('smmKg'),
      bfmKg: bfmKg,
      pbfPct: pbfPct,
      ffmKg: val('ffmKg'),
      bmi: val('bmi'),
      bmrKcal: val('bmrKcal'),
      tbwL: val('tbwL'),
      proteinKg: val('proteinKg'),
      mineralKg: val('mineralKg'),
      inbodyScore: val('inbodyScore'),
      visceralFatLevel: val('visceralFatLevel'),
      whr: val('whr'),
      idealWeightKg: val('idealWeightKg'),
      confidence: confidence,
      lowConfidenceFields: low,
      ocr: {
        fileName: sourceName,
        rawText: (ocr && ocr.rawText) || '',
        parseMs: (ocr && ocr.parseMs) || STEPS.length * STEP_MS,
        parsedAt: new Date().toISOString()
      }
    };
  }

  function compactDate(iso) {
    var s = String(iso);
    var d = new Date(s.length <= 10 ? s + 'T00:00:00' : s);
    if (isNaN(d.getTime())) d = new Date();
    return d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0') +
           String(d.getDate()).padStart(2, '0');
  }

  function recentCard(last) {
    var st = S.get();
    var d = E.derive(last, st.profile || global.MB_DATA.SEED_PROFILE);
    return h('div.card.card--flat', { uid: 'P03-C04', uidLabel: '최근 측정 요약' }, [
      h('div.card__head', [
        h('div.card__title', { text: '최근 측정' }),
        h('div.card__sub', { text: UI.dateK(last.measuredAt) +
                                   (last.device ? ' · ' + last.device : '') })
      ]),
      h('div.stats', [
        stat('체중', d.weightKg, 'kg', ''),
        stat('골격근량', d.smmKg, 'kg', 'muscle'),
        stat('체지방량', d.bfmKg, 'kg', 'fat')
      ]),
      h('button.btn.btn--sm.btn--block', {
        text: '기록 보기', uid: 'P03-B06', uidLabel: '기록 보기',
        style: { marginTop: '10px' },
        onClick: function () { navigate('P10', null, '기록 화면(P10)은 준비 중입니다'); }
      })
    ]);
  }

  function stat(label, v, u, mod) {
    return h('div.stat' + (mod ? '.stat--' + mod : ''), [
      h('div.stat__k', { text: label }),
      h('div', [h('span.stat__v', { text: UI.n1(v) }), h('span.stat__u', { text: u })])
    ]);
  }

  global.MB_UPLOAD = { checkSummary: checkSummary };
})(window);
