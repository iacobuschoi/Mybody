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
      var camInput = null;        // capture 속성이 붙은 쪽 — 폰에서 바로 카메라
      var serverExtra = null;     // 2층이 돌려준 나머지 칸들 (검수 화면으로 넘어감)
      var serverAt = null;        // 서버가 결과지에서 읽은 측정 시각 (날짜만이 아니라)
      var cancelOcr = null;       // 판독을 실제로 멈추는 손잡이
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

        /* 촬영용 입력은 따로 둡니다. capture 가 붙어 있으면 폰에서
           앨범을 건너뛰고 카메라가 바로 열리는데, 그 속성이 붙은
           입력으로는 앨범에서 고를 수가 없습니다. 둘을 한 입력으로
           합치면 둘 중 하나가 불편해집니다. */
        /* 고유번호를 안 붙입니다 — 화면에 안 보이는 입력이라 가리킬 수가
           없고, 사용자가 누르는 것은 촬영 버튼(P03-B01) 쪽입니다. */
        camInput = h('input', {
          type: 'file', accept: 'image/*', capture: 'environment',
          style: { display: 'none' },
          onChange: function () {
            var f = camInput.files && camInput.files[0];
            camInput.value = '';
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
            h('div.empty__d', { text: ocrOn()
              ? '올리면 자동으로 읽어 드립니다. 읽은 숫자는 검수 화면에서 한 번 보시면 됩니다.'
              : '사진을 띄워 놓고 숫자 세 개만 옮겨 적으면 끝입니다. 15초쯤 걸립니다.' }),
            fileInput
          ])
        ]);
        body.appendChild(zone);
        body.appendChild(camInput);

        /* 사진을 올리기 전에도 자동 판독이 있는지 없는지를 말합니다.
         *
         * 예전엔 이 카드가 사진을 붙인 뒤에만 나왔습니다. 그래서 첫 화면만
         * 본 사람에게 이 앱은 "손으로 옮겨 적는 앱" 이었습니다 — 자동
         * 판독이 있다는 말이 어디에도 없었으니 맞는 결론이었습니다.
         * 실제로 그런 말을 들었습니다. */
        body.appendChild(serverCard());

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
                global.MB_MODALS.cameraGuide(function () { camInput.click(); });
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
          global.MB_BUILD.tools ? h('button.btn.btn--ghost.btn--block', {
            text: '내장 샘플로 판독 (프로토타입)',
            uid: 'P03-B03', uidLabel: '내장 샘플로 판독',
            onClick: function () { startParsing('내장 샘플 (InBody270 결과지)'); }
          }) : null
        ]));

        if (global.MB_BUILD.tools) {
          body.appendChild(h('div', { style: { textAlign: 'center', marginTop: '2px' } }, [
            h('button.btn.btn--ghost.btn--sm', {
              text: '판독 실패 화면 보기 (프로토타입)',
              uid: 'P03-B09', uidLabel: '판독 실패 시연',
              onClick: fail
            })
          ]));
        }
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
                onClick: function () {
                  if (cancelOcr) { cancelOcr(); cancelOcr = null; }
                  mode = 'idle'; shot = null; serverExtra = null; serverAt = null; draw();
                }
              }),
              h('button.btn.btn--ghost.btn--sm', {
                text: '빼기', uid: 'P03-B11', uidLabel: '사진 빼기',
                onClick: function () {
                  if (cancelOcr) { cancelOcr(); cancelOcr = null; }
                  if (shot && shot.id) global.MB_PHOTO.remove(shot.id);
                  shot = null; serverExtra = null; serverAt = null;
                  mode = 'idle'; draw();
                  global.MB_UID.toast('사진을 지웠습니다');
                }
              })
            ])
          ])
        ]));

        /* 자동 판독을 먼저 보여 줍니다.
         *
         * 예전엔 "숫자 세 개만 — 사진을 보면서 옮겨 적으세요" 가 사진
         * 바로 밑에 있고 자동 판독은 그 아래였습니다. 폰에서는 스크롤을
         * 더 내려야 나오는 자리라, 쓰는 사람 눈에는 이 앱에 자동 판독이
         * 아예 없는 것처럼 보였습니다. 실제로 그런 말을 들었습니다.
         *
         * 손으로 적는 길은 그대로 둡니다 — 자동이 안 되는 자리가 있고
         * (서버 없이 열었을 때), 자동이 틀릴 때도 있습니다. 다만 순서는
         * 자동이 먼저입니다. */
        body.appendChild(serverCard());

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
              /* 결과만 무시하는 게 아니라 업로드를 실제로 멈춥니다.
                 취소를 누르는 이유는 보통 느려서인데, 그때가 데이터와
                 돈이 제일 아까운 순간입니다. */
              if (cancelOcr) { cancelOcr(); cancelOcr = null; }
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
      /* 자동 판독이 왜 안 되는지를 정확히 말합니다.
       *
       * 예전엔 어느 경우든 "자동 판독은 꺼져 있습니다 · 설정에서 켤 수
       * 있습니다" 한 문장이었습니다. 서버가 아예 없는 자리(미리보기
       * 링크로 열었을 때)에서도 같은 말을 해서, 설정에 들어가 봐야
       * 켤 수 있는 스위치가 없었습니다. 막다른 길을 안내한 셈입니다.
       *
       * 세 가지는 서로 다른 상태이고 할 일도 다릅니다:
       *   서버 없음  — 미리보기입니다. 내 서버에서 열어야 됩니다.
       *   로그인 안 함 — 로그인하면 켤 수 있습니다.
       *   꺼 둠      — 여기서 바로 켤 수 있습니다. 설정까지 안 가도 됩니다. */
      function ocrOn() {
        var S2 = global.MB_SYNC;
        return !!(S2 && S2.canOcr && S2.canOcr());
      }

      function serverCard() {
        var S2 = global.MB_SYNC;
        var st = S2 && S2.status ? S2.status() : {};
        var can = S2 && S2.canOcr && S2.canOcr();

        if (!can) {
          var why, act = null;
          /* "주소가 적혀 있다" 와 "그 주소에 우리 서버가 있다" 는 다릅니다.
             미리보기 링크로 열면 앱이 그 주소(claude.ai)를 기본값으로 잡는데,
             거기엔 서버가 없습니다. reachable === false 가 그걸 말해 줍니다. */
          if (st.reachable === false && st.ownServer && st.serverKind === 'down') {
            /* 이 페이지를 준 게 그 서버인데 지금은 안 닿는다면, 미리보기가
               아니라 그냥 꺼진 것입니다. 여기서 "미리보기입니다, 주소를
               넣으세요" 라고 하면 사람은 주소를 바꿉니다 — 브라우저는
               주소마다 따로 저장하니까 그 순간 그동안의 기록이 안 보이게
               됩니다. 고치라고 시킨 것이 기록을 날립니다. */
            why = '서버에 닿지 않습니다. 컴퓨터가 꺼져 있거나 서버를 멈춘 것 같습니다. ' +
                  '주소는 그대로 두세요 — 서버가 다시 켜지면 그대로 됩니다. ' +
                  '그동안에도 숫자를 직접 넣는 것은 그대로 됩니다.';
            act = null;
          } else if (!st.configured || st.reachable === false) {
            why = '지금 보고 계신 주소에는 서버가 없습니다 — 미리보기로 연 화면입니다. ' +
                  '자동 판독은 사진을 서버로 보내서 읽는 기능이라, 내 서버에서 열 때만 됩니다. ' +
                  '그동안은 아래에 숫자 세 개만 옮겨 적으시면 나머지는 앱이 계산합니다. ' +
                  '옮겨 적는 것도 15초면 끝납니다.';
            act = h('button.btn.btn--block', {
              text: '서버 주소 넣기', uid: 'P03-B15', uidLabel: '서버 주소 넣기',
              onClick: function () { global.MB_MODALS.serverAddress(function () { draw(); }); }
            });
          } else if (!st.signedIn) {
            why = '로그인하면 자동 판독을 켤 수 있습니다. 사진이 내 서버를 거쳐 판독 서비스로 가고, ' +
                  '숫자 초안을 만들어 돌려줍니다.';
            act = h('button.btn.btn--block', {
              text: '로그인 / 가입', uid: 'P03-B16', uidLabel: '로그인',
              onClick: function () { global.MB_MODALS.signIn(function () { draw(); }); }
            });
          } else {
            why = '자동 판독이 꺼져 있습니다. 켜면 사진이 내 서버를 거쳐 판독 서비스로 가고, ' +
                  '숫자 초안을 만들어 돌려줍니다. 켜도 검수 화면은 그대로 거칩니다.';
            act = h('button.btn.btn--primary.btn--block', {
              text: '자동 판독 켜기', uid: 'P03-B17', uidLabel: '자동 판독 켜기',
              onClick: function () {
                global.MB_MODALS.enableOcr(function () {
                  S2.setOcr(true);
                  global.MB_UID.toast('자동 판독을 켰습니다');
                  draw();
                });
              }
            });
          }
          return h('div.card.card--flat', { uid: 'P03-C08', uidLabel: '자동 판독 안내' }, [
            h('div.card__head', [
              h('div.card__title', { text: '사진에서 자동으로 읽기' }),
              h('span.badge', { text: '꺼짐' })
            ]),
            h('div.muted', { style: { marginTop: '6px' }, text: why }),
            act ? h('div', { style: { marginTop: '10px' } }, [act]) : null
          ]);
        }
        return h('div.card.card--flat', { uid: 'P03-C07', uidLabel: '서버 판독 카드' }, [
          h('div.card__head', [
            h('div.card__title', { text: shot ? '자동으로 읽어 볼까요' : '자동 판독이 켜져 있습니다' }),
            h('div.card__sub', { text: '사진이 서버를 거쳐 외부 판독 서비스로 갑니다' })
          ]),
          h('div.muted', { style: { marginBottom: shot ? '8px' : '0' },
            text: '돌려받은 숫자는 그대로 쓰지 않습니다. 결과지 안에서 검산이 맞는 것만 초록으로 표시하고, ' +
                  '어긋나면 그 칸을 짚어 줍니다.' }),
          shot ? h('button.btn.btn--primary.btn--block', {
            text: '서버에 판독 맡기기', uid: 'P03-B13', uidLabel: '서버에 판독 맡기기',
            onClick: askServer
          }) : null
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

        /* 어느 사진에 대한 요청인지 기억해 둡니다.
           판독은 몇 초 걸리고, 그 사이에 사용자는 취소를 누르거나 ·
           사진을 빼거나 · 다른 사진으로 바꿀 수 있습니다. 예전에는
           화면이 P03 인지만 보고 그대로 적용했습니다:
             취소했는데 몇 초 뒤 값이 들어오고,
             사진을 뺐으면 shot 이 null 인데 drawShot 이 shot.dataUrl 을
             읽어 화면이 하얘지고,
             사진을 바꿨으면 이전 사진의 숫자가 새 사진 위에 덮였습니다.
           보낸 사진과 지금 사진이 같을 때만 받습니다. */
        var forShot = shot.id;

        cancelOcr = global.MB_SYNC.ocr(shot.dataUrl, function (err, fields) {
          cancelOcr = null;
          clearTimers();
          if (A.current !== 'P03' || !body.isConnected) return;
          if (!shot || shot.id !== forShot) return;   // 빼거나 바꿨습니다
          if (mode !== 'parsing') return;             // 취소했습니다

          if (err) {
            mode = 'shot'; draw();
            global.MB_UID.toast(err.notInBody
              ? '인바디 결과지로 보이지 않습니다 — 직접 넣으시면 됩니다'
              : '자동 판독에 실패했습니다 — 직접 넣으시면 됩니다');
            return;
          }
          var read = 0;
          QUICK.forEach(function (f) {
            if (fields[f.key] != null) { quick[f.key] = fields[f.key]; read++; }
          });
          /* 서버가 결과지 머리글에서 읽은 시각을 통째로 들고 있습니다.
             예전에는 slice(0, 10) 로 날짜만 남기고 시각을 버렸습니다.
             그러면 quickISO() 가 다시 정오나 지금 시각을 박는데, 그건
             결과지에 인쇄된 시각이 아닙니다. 같은 날 두 번 잰 경우
             순서도 잃고, "지난 측정과 며칠 차이" 도 어긋납니다.
             화면의 날짜 칸은 날짜만 받으니 거기엔 날짜를 넣고,
             시각은 따로 들고 있다가 저장할 때 씁니다. */
          if (fields.measuredAt) {
            var at = String(fields.measuredAt);
            quickAt = at.slice(0, 10);
            serverAt = /\d{2}:\d{2}/.test(at) ? at : null;
          }
          serverExtra = fields;
          mode = 'shot';

          /* 세 칸을 다 읽었으면 검수 화면으로 바로 넘깁니다.
           *
           * 예전엔 여기서 멈춰서, 채워진 칸을 보고 사용자가 "검수 화면으로"
           * 를 한 번 더 눌러야 했습니다. 그 한 번이 "자동으로 읽어 주는
           * 앱" 과 "읽어는 주는데 뭘 더 해야 하는 앱" 을 갈랐습니다.
           *
           * 검수를 건너뛰는 것이 아닙니다 — 넘어가는 곳이 바로 검수
           * 화면이고, 거기에 사진과 검산 결과가 같이 있습니다. 대조는
           * 여기보다 거기가 낫습니다.
           *
           * 덜 읽었으면 여기 남습니다. 빈 칸을 채우는 데는 사진이 바로
           * 위에 있는 이 화면이 낫습니다. */
          if (read === QUICK.length) {
            global.MB_UID.toast('판독했습니다 — 사진과 대조해 주세요');
            toReview();
            return;
          }
          draw();
          // 한 칸도 못 읽었으면 "판독했습니다" 는 거짓말입니다.
          global.MB_UID.toast(read
            ? '세 칸 중 ' + read + '칸만 읽었습니다 — 나머지는 직접 넣어 주세요'
            : '핵심 세 칸을 읽지 못했습니다 — 직접 넣어 주세요');
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
          serverExtra = null; serverAt = null;
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
        /* 시각의 출처는 셋이고, 믿을 만한 순서가 있습니다.
             1. 서버가 결과지에서 읽은 시각 — 결과지에 인쇄된 값입니다
             2. 사진의 EXIF 촬영 시각 — 잰 직후 찍었다면 거의 같습니다
             3. 없으면 지금 시각(오늘) 또는 정오(지난 날)
           앞의 둘은 사용자가 고른 날짜와 같은 날일 때만 씁니다 —
           날짜를 손으로 고쳤다면 그쪽이 우선입니다. */
        if (serverAt && serverAt.slice(0, 10) === d) return serverAt;
        if (shot && shot.exifAt && String(shot.exifAt).slice(0, 10) === d) return shot.exifAt;

        /* EXIF 가 없을 때 예전에는 'T09:00:00' 을 박았습니다. 카톡으로
           받은 사진은 EXIF 가 지워지고, 스크린샷과 PNG 에는 애초에
           없습니다 — 흔한 경우입니다. 그래서 같은 날 두 장을 넣으면
           측정시각이 글자 하나까지 같아졌고, 검산은 "같은 날" 이라며
           변화량 검사를 껐고, id 는 충돌했습니다.
           오늘이면 지금 시각을, 지난 날이면 정오를 씁니다. 정확한
           시각은 아니지만 서로 다르고, 사용자가 고칠 수 있습니다. */
        var now = new Date();
        if (d === todayLocal()) {
          return d + 'T' + String(now.getHours()).padStart(2, '0') + ':' +
                 String(now.getMinutes()).padStart(2, '0') + ':' +
                 String(now.getSeconds()).padStart(2, '0');
        }
        return d + 'T12:00:00';
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
    /* 로그인 상태에서 서버로 가는 것은 "수치" 전부가 아니라 주간 요약
       하나입니다(체중 · 골격근 · 체지방 · 체지방률의 최근값과 변화량).
       측정 기록 자체는 한 번도 안 올라갑니다. 뭉뚱그려 "수치가 올라간다"
       고 하면 백업이 되는 줄 알게 됩니다. */
    return on
      ? '사진은 이 기기에 저장되고, 자동 판독을 누를 때만 서버를 거쳐 외부 판독 서비스로 갑니다. ' +
        '로그인했다면 주간 요약(최근 체중·골격근·체지방)도 내 서버로 올라갑니다.'
      : '사진은 이 기기에만 저장됩니다. 로그인했다면 주간 요약(최근 체중·골격근·체지방)이 내 서버로 올라갑니다.';
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
