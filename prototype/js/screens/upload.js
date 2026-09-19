/* P03 — 인바디 결과지 업로드 (판독은 아직 스텁)
 *
 * 실제 OCR은 없다. 이 화면은 idle → parsing → (성공 P04 / 실패 S02) 흐름만
 * 진짜처럼 보여주는 것이 목적이다. 판독 결과는 MB_DATA.STUB_OCR_RESULT 고정.
 */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  var MAX_BYTES = 10 * 1024 * 1024;          // 10MB
  var STEP_MS = 700;                          // 단계당 체감 시간
  var STEPS = ['이미지 보정', '표 영역 검출', '숫자 인식', '검증'];
  var LOW_CONF = 0.70;                        // 이 아래는 검수 화면에서 확인받는다

  var FIELD_LABELS = {
    measuredAt: '측정일시', weightKg: '체중', smmKg: '골격근량', bfmKg: '체지방량',
    pbfPct: '체지방률', bmi: 'BMI', ffmKg: '제지방량', bmrKcal: '기초대사량',
    visceralFatLevel: '내장지방 레벨', whr: '복부지방률', inbodyScore: 'InBody 점수',
    tbwL: '체수분', proteinKg: '단백질', mineralKg: '무기질', idealWeightKg: '적정체중'
  };

  /* --- 화면 로컬 상태 (render() 진입 때마다 초기화) ------------------------ */
  var mode = 'idle';        // idle | parsing | error
  var step = 0;             // 진행 중인 단계 인덱스
  var sourceName = '';      // 판독 대상 표시용 이름
  var timers = [];          // 진행 타이머 — 재렌더/취소 시 반드시 전부 정리

  function clearTimers() {
    while (timers.length) { clearTimeout(timers.pop()); }
  }

  A.register('P03', {
    title: '인바디 올리기', label: '인바디 사진 업로드',
    render: function (wrap, ctx) {
      /* 재진입·재렌더 시 남은 타이머를 먼저 죽인다 (유령 진행 방지) */
      clearTimers();
      mode = 'idle'; step = 0; sourceName = '';

      var fileInput = null;
      var body = h('div');
      wrap.appendChild(body);
      draw();

      /* --- 그리기 --------------------------------------------------------- */
      function draw() {
        UI.clear(body);

        if (mode === 'parsing') drawParsing();
        else if (mode === 'error') drawError();
        else drawIdle();

        /* C03 개인정보 안내 — 모든 상태에서 계속 보인다 */
        body.appendChild(h('div.note', {
          uid: 'P03-C03', uidLabel: '개인정보 안내',
          text: '사진과 수치는 이 기기에만 저장되고 서버로 전송되지 않습니다.'
        }));

        /* C04 최근 측정 요약 — 판독 중에는 숨긴다 */
        if (mode !== 'parsing') {
          var last = S.latestScan();
          if (last) body.appendChild(recentCard(last));
        }

        if (global.MB_UID) global.MB_UID.scan(body);
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
            fileInput.value = '';     // 같은 파일 다시 골라도 반응하게
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
            h('div.empty__t', { text: '여기에 결과지를 끌어다 놓으세요' }),
            h('div.empty__d', { text: 'JPG · PNG · HEIC · 10MB 이하. 눌러서 골라도 됩니다.' }),
            fileInput
          ])
        ]);
        body.appendChild(zone);

        /* C02 촬영 가이드 */
        body.appendChild(h('div.card', { uid: 'P03-C02', uidLabel: '촬영 가이드 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: '잘 찍는 법' }),
            h('div.card__sub', { text: '판독 성공률이 여기서 갈립니다' })
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

        /* 업로드 방식 */
        body.appendChild(h('div.btn-row.btn-row--stack', [
          h('button.btn.btn--primary.btn--block', {
            text: '내장 샘플로 판독 (프로토타입)',
            uid: 'P03-B03', uidLabel: '내장 샘플로 판독',
            onClick: function () { startParsing('내장 샘플 (InBody270 결과지)'); }
          }),
          h('div.btn-row', [
            h('button.btn', {
              text: '📷 사진 촬영', uid: 'P03-B01', uidLabel: '사진 촬영',
              onClick: function () {
                global.MB_MODALS.cameraGuide(function () { startParsing('카메라 촬영본'); });
              }
            }),
            h('button.btn', {
              text: '📁 파일 선택', uid: 'P03-B02', uidLabel: '파일 선택',
              onClick: function () { fileInput.click(); }
            })
          ]),
          h('button.btn.btn--ghost.btn--block', {
            text: '사진 없이 직접 입력', uid: 'P03-B04', uidLabel: '사진 없이 직접 입력',
            onClick: goManual
          })
        ]));

        /* 프로토타입 전용: 실패 경로를 오너가 직접 눌러볼 수 있게 */
        body.appendChild(h('div', { style: { textAlign: 'center', marginTop: '2px' } }, [
          h('button.btn.btn--ghost.btn--sm', {
            text: '판독 실패 화면 보기 (프로토타입)',
            uid: 'P03-B09', uidLabel: '판독 실패 시연',
            onClick: fail
          })
        ]));
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
          h('div.muted', { text: '보통 3~6초 걸립니다. 이 기기 안에서만 처리됩니다.' }),
          h('button.btn.btn--ghost.btn--block', {
            text: '취소', uid: 'P03-B05', uidLabel: '판독 취소',
            style: { marginTop: '12px' },
            onClick: function () {
              clearTimers();
              mode = 'idle'; step = 0;
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
          h('div.empty__d', { text: '초점이 흐리거나 표 일부가 잘렸을 가능성이 높습니다.' }),
          h('div.btn-row', [
            h('button.btn', {
              text: '다시 올리기', uid: 'P03-B07', uidLabel: '다시 올리기',
              onClick: function () { mode = 'idle'; step = 0; draw(); }
            }),
            h('button.btn.btn--primary', {
              text: '직접 입력', uid: 'P03-B08', uidLabel: '직접 입력으로 전환',
              onClick: goManual
            })
          ])
        ]));
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
                                     'MB 입니다. 10MB 이하만 올릴 수 있습니다.');
          return;
        }
        startParsing(file.name || '선택한 사진');
      }

      function startParsing(name) {
        clearTimers();
        sourceName = name || '내장 샘플';
        mode = 'parsing'; step = 0;
        draw();
        for (var i = 1; i <= STEPS.length; i++) tick(i);
      }

      function tick(n) {
        timers.push(setTimeout(function () {
          step = n;
          if (n < STEPS.length) draw(); else finish();
        }, STEP_MS * n));
      }

      function finish() {
        clearTimers();
        mode = 'idle'; step = 0;

        var draft = buildDraft(global.MB_DATA.STUB_OCR_RESULT, sourceName);
        S.set({ draft: draft });
        global.MB_DRAFT = draft;          // 검수 화면이 아직 없을 때를 위한 대기 자리

        var before = A.current;
        A.go('P04', { ocr: true });
        if (A.current === before) {       // P04 미등록 — 프로토타입 조립 중
          draw();
          global.MB_UID.toast('판독 결과를 저장했습니다 — 검수 화면(P04)은 준비 중입니다');
        }
      }

      function fail() {
        clearTimers();
        mode = 'error'; step = 0;
        draw();
        global.MB_MODALS.parseFailed(
          function () { mode = 'idle'; draw(); },
          goManual
        );
      }
    }
  });

  /* --- 조각 --------------------------------------------------------------- */

  function goManual() {
    navigate('P04', { manual: true }, '직접 입력 화면(P04)은 준비 중입니다');
  }

  /** 아직 등록되지 않은 화면으로 보내려 할 때 막다른 길이 되지 않게 */
  function navigate(id, params, fallbackMsg) {
    var before = A.current;
    A.go(id, params);
    if (A.current === before && fallbackMsg) global.MB_UID.toast(fallbackMsg);
  }

  function isImage(file) {
    if (!file) return false;
    if (file.type && file.type.indexOf('image/') === 0) return true;
    // HEIC/HEIF는 브라우저가 MIME 타입을 비워두는 경우가 흔하다
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
      bfmKg = Math.round(weightKg * pbfPct / 100 * 10) / 10;   // 파생 (판독 실패분 보충)
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
      confidence: confidence,              // 필드별 0~1
      lowConfidenceFields: low,            // 사람이 꼭 확인해야 하는 항목 (한글 라벨)
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
})(window);
