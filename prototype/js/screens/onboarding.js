/* P01 — 온보딩 / 프로필 입력 (3단계 위저드, 한 화면 안에서 단계 전환) */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE, A = global.MB_APP;
  var h = UI.h;

  /* 단계 · 입력값은 화면 밖(클로저)에 둔다 — A.refresh()로 다시 그려도 유지된다 */
  var step = 0;          // 0 | 1 | 2
  var draft = null;
  var draftFrom = null;  // 초안을 만들 때 저장소에 있던 프로필 (초기화·시드로 바뀌면 다시 만든다)

  var STEPS = [
    { t: '기본 정보',   d: '칼로리 계산의 기준이 되는 값입니다' },
    { t: '활동 · 운동', d: '실제로 지킬 수 있는 선에서 고르세요' },
    { t: '환경 · 제약', d: '못 하는 것을 먼저 빼야 계획이 남습니다' }
  ];

  var SEX = [['male', '남'], ['female', '여']];
  var SESSION_MIN = [30, 45, 60, 90];
  var ENVIRONMENT = [['gym', '헬스장'], ['home', '홈트'], ['hybrid', '혼합']];
  var DIET_FLAGS = [
    ['vegetarian', '채식'], ['lactoseFree', '유당불내증'], ['shellfish', '갑각류'],
    ['nuts', '견과'], ['halal', '할랄']
  ];
  var MEALS = [[2, '2식'], [3, '3식'], [4, '3식+간식']];

  /* 건너뛰기 기본값 — M22 팝업 문구(남성 / 30세 / 175cm / 보통 활동)와 같아야 한다 */
  function skipProfile() {
    return {
      sex: 'male', age: 30, heightCm: 175,
      activityLevel: 'moderate', trainingAge: 'novice',
      daysPerWeek: 3, sessionMinutes: 60,
      environment: 'gym', injuries: '', dietFlags: [],
      mealsPerDay: 3, cookingLevel: 'simple', hadPriorPeak: false
    };
  }

  function newDraft(st) {
    var p = st.profile;
    return {
      sex: p && p.sex ? p.sex : 'male',
      age: p && p.age != null ? p.age : null,
      heightCm: p && p.heightCm != null ? p.heightCm : null,
      activityLevel: p && p.activityLevel ? p.activityLevel : 'moderate',
      trainingAge: p && p.trainingAge ? p.trainingAge : 'novice',
      daysPerWeek: p && p.daysPerWeek ? p.daysPerWeek : 4,
      sessionMinutes: p && p.sessionMinutes ? p.sessionMinutes : 60,
      environment: p && p.environment ? p.environment : 'gym',
      injuries: p && p.injuries ? p.injuries : '',
      dietFlags: p && p.dietFlags ? p.dietFlags.slice() : [],
      mealsPerDay: p && p.mealsPerDay ? p.mealsPerDay : 3,
      cookingLevel: p && p.cookingLevel ? p.cookingLevel : 'simple',
      hadPriorPeak: p ? !!p.hadPriorPeak : false
    };
  }

  function toProfile(d) {
    return {
      sex: d.sex, age: d.age, heightCm: d.heightCm,
      activityLevel: d.activityLevel, trainingAge: d.trainingAge,
      daysPerWeek: d.daysPerWeek, sessionMinutes: d.sessionMinutes,
      environment: d.environment, injuries: d.injuries, dietFlags: d.dietFlags.slice(),
      mealsPerDay: d.mealsPerDay, cookingLevel: d.cookingLevel, hadPriorPeak: d.hadPriorPeak
    };
  }

  /* --- 검증 (키 100~250, 나이 10~100) ------------------------------------- */
  function validate(d) {
    var errs = [];
    if (d.age == null || isNaN(d.age)) errs.push({ f: 'age', m: '나이를 입력해 주세요' });
    else if (d.age < 10 || d.age > 100) errs.push({ f: 'age', m: '나이는 10~100 사이여야 합니다 (입력: ' + d.age + ')' });
    if (d.heightCm == null || isNaN(d.heightCm)) errs.push({ f: 'heightCm', m: '키를 입력해 주세요' });
    else if (d.heightCm < 100 || d.heightCm > 250) errs.push({ f: 'heightCm', m: '키는 100~250cm 사이여야 합니다 (입력: ' + d.heightCm + ')' });
    return errs;
  }
  function errOf(errs, field) {
    for (var i = 0; i < errs.length; i++) if (errs[i].f === field) return errs[i].m;
    return null;
  }

  A.register('P01', {
    title: '프로필', label: '온보딩 · 프로필', hideTabs: true,
    render: function (wrap, ctx) {
      var st = S.get();
      /* 저장된 프로필이 밖에서 바뀌었다면(전체 초기화·시드 주입) 초안을 다시 만든다.
         사용자의 입력은 draft에만 쌓이므로 편집 중에 덮어써지지 않는다 */
      var profileKey = JSON.stringify(st.profile || null);
      if (!draft || draftFrom !== profileKey) {
        draft = newDraft(st);
        draftFrom = profileKey;
        step = 0;
      }
      var d = draft;
      var scan = S.latestScan();

      /* 인바디가 이미 있으면 활동/경력 선택지에 실제 숫자를 붙여 보여준다.
         나이·키를 고치면 값이 달라지므로 draw()마다 다시 계산한다 */
      var bmr = null, weightKg = null;
      function recompute() {
        bmr = null; weightKg = null;
        if (!scan) return;
        try {
          var der = E.derive(scan, Object.assign({}, toProfile(d), {
            age: d.age || 30, heightCm: d.heightCm || 175
          }));
          bmr = der.bmrKcal; weightKg = der.weightKg;
        } catch (e) { bmr = null; weightKg = null; }
      }

      var body = h('div');
      wrap.appendChild(body);

      /* 라이브 검증용 노드 참조 (입력 중에는 다시 그리지 않고 이 노드들만 갱신) */
      var errNodes = {}, errBox = null, errBoxText = null, advanceBtn = null;

      draw();

      function draw() {
        UI.clear(body);
        errNodes = {}; errBox = null; errBoxText = null; advanceBtn = null;
        recompute();

        var errs = validate(d);

        /* --- C01 진행 표시 --- */
        body.appendChild(h('div.card.card--flat', { uid: 'P01-C01', uidLabel: '진행 표시' }, [
          h('div.card__head', [
            h('div.card__title', { text: (step + 1) + '/3 · ' + STEPS[step].t }),
            h('span.badge.badge--accent', { text: Math.round((step + 1) / 3 * 100) + '%' })
          ]),
          h('div.bar', [h('div.bar__fill', { style: { width: ((step + 1) / 3 * 100) + '%' } })]),
          h('div.progress-steps', STEPS.map(function (s, i) {
            return h('div.pstep' + (i < step ? '.is-done' : ''), {
              style: i === step ? { color: 'var(--text)', fontWeight: '700' } : null
            }, [
              h('div.pstep__dot', { text: i < step ? '✓' : '' }),
              h('span', { text: (i + 1) + '. ' + s.t })
            ]);
          })),
          h('div.card__sub', { text: STEPS[step].d })
        ]));

        if (step === 0) drawStep1(errs);
        if (step === 1) drawStep2();
        if (step === 2) drawStep3();

        /* --- S01 검증 오류 상태 --- */
        errBoxText = h('div');
        errBox = h('div.note.note--bad', { uid: 'P01-S01', uidLabel: '검증 오류 상태' }, [
          h('b', { text: '입력을 확인해 주세요' }), errBoxText
        ]);
        body.appendChild(errBox);

        /* --- 버튼 --- */
        var row = h('div.btn-row', { style: { marginTop: '4px' } });
        if (step > 0) {
          row.appendChild(h('button.btn', {
            text: '← 이전', uid: 'P01-B02', uidLabel: '이전',
            onClick: function () { step -= 1; draw(); }
          }));
        }
        if (step < 2) {
          advanceBtn = h('button.btn.btn--primary', {
            text: '다음 →', uid: 'P01-B01', uidLabel: '다음',
            onClick: function () {
              if (validate(d).length) { step = 0; draw(); return; }
              step += 1; draw();
            }
          });
        } else {
          advanceBtn = h('button.btn.btn--primary', {
            text: '완료', uid: 'P01-B03', uidLabel: '완료',
            onClick: complete
          });
        }
        row.appendChild(advanceBtn);
        body.appendChild(row);

        /* --- 보조 동작 --- */
        body.appendChild(h('div.btn-row', { style: { marginTop: '10px' } }, [
          h('button.btn.btn--ghost.btn--sm', {
            text: '건너뛰기', uid: 'P01-B04', uidLabel: '건너뛰기',
            onClick: function () {
              global.MB_MODALS.skipOnboarding(function () {
                S.set({ profile: skipProfile(), onboarded: true });
                draft = null; draftFrom = null; step = 0;
                global.MB_MODALS.disclaimer();
                A.go('P03');
              });
            }
          }),
          /* 이 버튼은 개발 빌드 전용입니다.
             누르면 주인의 실제 인바디 3건과 프로필이 통째로 들어오고,
             seed() 가 disclaimerAccepted 까지 켭니다 — 남의 몸 숫자를
             자기 것으로 받고, 의학적 고지를 읽지도 않은 채 승낙한
             상태가 됩니다. 배포본에 있으면 안 됩니다. */
          global.MB_BUILD.tools ? h('button.btn.btn--ghost.btn--sm', {
            text: '내 실제 인바디로 바로 시작 (개발용)', uid: 'P01-B05',
            uidLabel: '실제 인바디로 바로 시작',
            onClick: function () {
              S.seed();
              draft = null; draftFrom = null; step = 0;
              global.MB_UID.toast('실제 인바디 3건과 프로필을 불러왔습니다');
              A.go('P02');
            }
          }) : null
        ]));

        body.appendChild(h('div.muted', { style: { marginTop: '10px', textAlign: 'center' },
          text: '입력값은 이 기기에 저장됩니다. 나중에 로그인하면 내가 지정한 서버로도 올라갑니다.' }));

        syncErrors();
        if (global.MB_UID && global.MB_UID.scan) global.MB_UID.scan(body);
      }

      /* ===================== 1/3 기본 정보 ===================== */
      function drawStep1(errs) {
        var card = h('div.card', { uid: 'P01-C02', uidLabel: '1단계 기본 정보' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '기본 정보' }),
          h('div.card__sub', { text: '기초대사량 추정에 쓰입니다' })
        ]));

        /* F01 성별 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '성별' }),
          h('div.chips', { uid: 'P01-F01', uidLabel: '성별 선택' }, SEX.map(function (o) {
            return h('button.chip' + (d.sex === o[0] ? '.is-on' : ''), {
              text: o[1],
              onClick: function () { d.sex = o[0]; draw(); }
            });
          })),
          h('div.field__hint', { text: '체지방률 기준선과 칼로리 공식이 달라집니다.' })
        ]));

        /* F02 나이 */
        card.appendChild(numField('P01-F02', '나이', 'age', '세', 10, 100, 1,
          '만 나이 기준. 10~100 사이만 받습니다.', errOf(errs, 'age')));

        /* F03 키 */
        card.appendChild(numField('P01-F03', '키', 'heightCm', 'cm', 100, 250, 0.5,
          'BMI 계산에 쓰입니다. 인바디 결과지의 키와 맞추세요.', errOf(errs, 'heightCm')));

        body.appendChild(card);
      }

      /* ===================== 2/3 활동 · 운동 ===================== */
      function drawStep2() {
        var card = h('div.card', { uid: 'P01-C03', uidLabel: '2단계 활동 · 운동' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '활동 · 운동' }),
          h('div.card__sub', { text: '여기서 부풀리면 계획 전체가 어긋납니다' })
        ]));

        /* F04 활동 수준 */
        var palKeys = ['sedentary', 'light', 'moderate', 'active', 'veryActive'];
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '활동 수준' }),
          h('div.radio-cards', { uid: 'P01-F04', uidLabel: '활동 수준 선택' }, palKeys.map(function (k) {
            var p = E.PAL[k];
            var desc = '활동대사량 × ' + p.mult.toFixed(3).replace(/0+$/, '').replace(/\.$/, '');
            if (bmr) desc += ' · 하루 약 ' + comma(bmr * p.mult) + ' kcal';
            return h('label.radio-card' + (d.activityLevel === k ? '.is-on' : ''), {
              onClick: function () { d.activityLevel = k; draw(); }
            }, [
              h('div', [
                h('div.radio-card__t', { text: p.label }),
                h('div.radio-card__d', { text: desc })
              ])
            ]);
          })),
          h('div.field__hint', { text: bmr
            ? '운동을 뺀 평소 생활 기준으로 고르세요. 운동량은 아래에서 따로 받습니다.'
            : '인바디를 올리면 여기에 예상 유지 칼로리가 같이 표시됩니다.' })
        ]));

        /* F05 운동 경력 */
        var mbKeys = ['novice', 'intermediate', 'advanced', 'elite'];
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '운동 경력' }),
          h('div.radio-cards', { uid: 'P01-F05', uidLabel: '운동 경력 선택' }, mbKeys.map(function (k) {
            var m = E.MUSCLE_BASE[k];
            var desc = '근육 증가 한계 약 체중의 ' + m.pct + '%/월';
            if (weightKg) desc += ' (' + UI.n1(weightKg) + 'kg 기준 월 ' + UI.n1(weightKg * m.pct / 100) + 'kg)';
            return h('label.radio-card' + (d.trainingAge === k ? '.is-on' : ''), {
              onClick: function () { d.trainingAge = k; draw(); }
            }, [
              h('div', [
                h('div.radio-card__t', { text: m.label }),
                h('div.radio-card__d', { text: desc })
              ])
            ]);
          })),
          h('div.field__hint', { text: '위 숫자는 잘 먹고 잘 자는 최상 조건의 상한입니다. 감량 중에는 이보다 훨씬 느려집니다.' })
        ]));

        /* F06 주당 가능 운동 일수 */
        var daysOut = h('span.num', { style: { fontWeight: '800' }, text: d.daysPerWeek + '일' });
        var daysHint = h('div.field__hint', { text: daysHintText(d.daysPerWeek) });
        card.appendChild(h('div.field', [
          h('div.field__label', { style: { display: 'flex', justifyContent: 'space-between' } }, [
            h('span', { text: '주당 가능 운동 일수' }), daysOut
          ]),
          h('input.range', {
            type: 'range', min: 2, max: 6, step: 1, value: d.daysPerWeek,
            uid: 'P01-F06', uidLabel: '주당 가능 운동 일수',
            onInput: function (e) {
              d.daysPerWeek = parseInt(e.target.value, 10);
              daysOut.textContent = d.daysPerWeek + '일';
              daysHint.textContent = daysHintText(d.daysPerWeek);
            }
          }),
          h('div.muted', { style: { display: 'flex', justifyContent: 'space-between', fontSize: '11px' } }, [
            h('span', { text: '2일' }), h('span', { text: '6일' })
          ]),
          daysHint
        ]));

        /* F07 회당 가능 시간 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '회당 가능 시간' }),
          h('div.chips', { uid: 'P01-F07', uidLabel: '회당 가능 시간 선택' }, SESSION_MIN.map(function (m) {
            return h('button.chip' + (d.sessionMinutes === m ? '.is-on' : ''), {
              text: m + '분',
              onClick: function () { d.sessionMinutes = m; draw(); }
            });
          })),
          h('div.field__hint', { text: '이동·샤워 시간 빼고, 실제로 운동하는 시간입니다.' })
        ]));

        body.appendChild(card);
      }

      /* ===================== 3/3 환경 · 제약 ===================== */
      function drawStep3() {
        var card = h('div.card', { uid: 'P01-C04', uidLabel: '3단계 환경 · 제약' });
        card.appendChild(h('div.card__head', [
          h('div.card__title', { text: '환경 · 제약' }),
          h('div.card__sub', { text: '종목과 식단 후보를 거르는 데 쓰입니다' })
        ]));

        /* F08 운동 환경 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '운동 환경' }),
          h('div.chips', { uid: 'P01-F08', uidLabel: '운동 환경 선택' }, ENVIRONMENT.map(function (o) {
            return h('button.chip' + (d.environment === o[0] ? '.is-on' : ''), {
              text: o[1],
              onClick: function () { d.environment = o[0]; draw(); }
            });
          })),
          h('div.field__hint', { text: '홈트를 고르면 바벨 종목 대신 덤벨·맨몸 종목으로 바뀝니다.' })
        ]));

        /* F09 부상 · 질환 메모 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '부상 · 질환 메모 (선택)' }),
          h('textarea.textarea', {
            rows: 3, text: d.injuries,
            placeholder: '예) 왼쪽 어깨 충돌증후군, 무릎 반월상연골 수술 이력',
            uid: 'P01-F09', uidLabel: '부상 · 질환 메모',
            onInput: function (e) { d.injuries = e.target.value; }
          }),
          h('div.field__hint', { text: '적어두면 해당 부위 종목에 대안이 함께 표시됩니다. 진단·치료를 대신하지는 않습니다.' })
        ]));

        /* F10 식단 제약 (복수 선택) */
        var none = d.dietFlags.length === 0;
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '식단 제약 (복수 선택)' }),
          h('div.chips', { uid: 'P01-F10', uidLabel: '식단 제약 선택' }, DIET_FLAGS.map(function (o) {
            var on = d.dietFlags.indexOf(o[0]) >= 0;
            return h('button.chip' + (on ? '.is-on' : ''), {
              text: o[1],
              onClick: function () {
                if (on) d.dietFlags = d.dietFlags.filter(function (x) { return x !== o[0]; });
                else d.dietFlags = d.dietFlags.concat([o[0]]);
                draw();
              }
            });
          }).concat([
            h('button.chip' + (none ? '.is-on' : ''), {
              text: '없음',
              onClick: function () { d.dietFlags = []; draw(); }
            })
          ])),
          h('div.field__hint', { text: '고른 항목이 들어간 식단은 후보에서 빠지고 단백질원이 대체됩니다.' })
        ]));

        /* F11 식사 횟수 */
        card.appendChild(h('div.field', [
          h('div.field__label', { text: '하루 식사 횟수' }),
          h('div.chips', { uid: 'P01-F11', uidLabel: '식사 횟수 선택' }, MEALS.map(function (o) {
            return h('button.chip' + (d.mealsPerDay === o[0] ? '.is-on' : ''), {
              text: o[1],
              onClick: function () { d.mealsPerDay = o[0]; draw(); }
            });
          })),
          h('div.field__hint', { text: '총량이 같으면 횟수 자체가 결과를 바꾸지는 않습니다. 지키기 쉬운 쪽으로 고르세요.' })
        ]));

        body.appendChild(card);

        /* C05 입력 요약 */
        body.appendChild(h('div.card.card--flat', { uid: 'P01-C05', uidLabel: '입력 요약' }, [
          h('div.card__head', [h('div.card__title', { text: '입력 요약' })]),
          kv('성별 · 나이 · 키', labelOf(SEX, d.sex) + ' · ' +
            (d.age != null ? d.age + '세' : '—') + ' · ' +
            (d.heightCm != null ? UI.n1(d.heightCm) + 'cm' : '—')),
          kv('활동 수준', (E.PAL[d.activityLevel] || {}).label || '—'),
          kv('운동 경력', (E.MUSCLE_BASE[d.trainingAge] || {}).label || '—'),
          kv('운동량', '주 ' + d.daysPerWeek + '일 · 회당 ' + d.sessionMinutes + '분'),
          kv('환경', labelOf(ENVIRONMENT, d.environment)),
          kv('식단 제약', d.dietFlags.length
            ? d.dietFlags.map(function (f) { return labelOf(DIET_FLAGS, f); }).join(', ') : '없음'),
          kv('식사 횟수', labelOf(MEALS, d.mealsPerDay)),
          kv('부상 메모', d.injuries ? d.injuries : '없음')
        ]));

        body.appendChild(h('div.note', { uid: 'P01-C06', uidLabel: '다음 단계 안내',
          text: '완료하면 인바디 결과지를 올리는 화면으로 넘어갑니다. 프로필은 설정에서 언제든 고칠 수 있습니다.' }));
      }

      /* --- 입력 중 검증 갱신 (포커스를 잃지 않도록 다시 그리지 않는다) --------- */
      function syncErrors() {
        var errs = validate(d);
        ['age', 'heightCm'].forEach(function (f) {
          var node = errNodes[f];
          if (!node) return;
          var msg = errOf(errs, f);
          node.textContent = msg || '';
          node.style.display = msg ? '' : 'none';
        });
        if (errBox) {
          errBox.style.display = errs.length ? '' : 'none';
          if (errBoxText) {
            UI.clear(errBoxText);
            errs.forEach(function (e) {
              errBoxText.appendChild(h('div', { text: '· ' + e.m }));
            });
            if (errs.length && step > 0) {
              errBoxText.appendChild(h('div', { style: { marginTop: '4px' },
                text: '1단계로 돌아가 고쳐야 계속할 수 있습니다.' }));
            }
          }
        }
        if (advanceBtn) {
          if (errs.length) advanceBtn.setAttribute('disabled', '');
          else advanceBtn.removeAttribute('disabled');
        }
      }

      function complete() {
        if (validate(d).length) { step = 0; draw(); return; }
        S.set({ profile: toProfile(d), onboarded: true });
        draft = null; draftFrom = null; step = 0;
        global.MB_MODALS.disclaimer();
        A.go('P03');
      }

      /* --- 숫자 입력 필드 (라이브 검증) --------------------------------------- */
      function numField(uid, label, key, unit, min, max, stepSize, hint, err) {
        var input = h('input.input.input--num', {
          type: 'number', min: min, max: max, step: stepSize,
          value: d[key] != null ? d[key] : '',
          inputmode: 'decimal', placeholder: min + '~' + max,
          uid: uid, uidLabel: label,
          onInput: function () {
            var v = parseFloat(input.value);
            d[key] = (input.value === '' || isNaN(v)) ? null : v;
            syncErrors();
          }
        });
        var errNode = h('div.field__err', { text: err || '', style: { display: err ? '' : 'none' } });
        errNodes[key] = errNode;
        return h('div.field', [
          h('div.field__label', { text: label }),
          h('div.input-unit', [input, h('span.input-unit__u', { text: unit })]),
          errNode,
          hint ? h('div.field__hint', { text: hint }) : null
        ]);
      }
    }
  });

  /* --- 작은 헬퍼 ----------------------------------------------------------- */
  function daysHintText(days) {
    if (days <= 2) return '주 2일은 계획 엔진의 하한(3일)보다 적습니다. 플랜은 3일 기준으로 만들어집니다.';
    if (days === 3) return '주 3일이면 전신 분할로 충분히 굴러갑니다.';
    if (days >= 6) return '주 6일은 회복이 병목이 됩니다. 실제로 지킬 수 있을 때만 고르세요.';
    return '주 ' + days + '일이면 상·하체 분할까지 가능합니다.';
  }

  function labelOf(pairs, value) {
    for (var i = 0; i < pairs.length; i++) if (pairs[i][0] === value) return pairs[i][1];
    return '—';
  }

  function kv(k, v) {
    return h('div.kv', [h('span.kv__k', { text: k }), h('span.kv__v', { text: v })]);
  }

  function comma(n) {
    return String(Math.round(n)).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  }
})(window);
