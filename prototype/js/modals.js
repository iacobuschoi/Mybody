/* =============================================================================
 * modals.js — 모달/팝업 전체 (M01 ~ M25). 모달은 전역 시민이라 화면에 종속시키지 않는다.
 * ========================================================================== */
(function (global) {
  'use strict';
  var UI = global.MB_UI, S = global.MB_STORE, E = global.MB_ENGINE;
  var h = UI.h;
  var M = {};

  /* M01 촬영 가이드 */
  M.cameraGuide = function (onPick) {
    UI.openModal({
      uid: 'M01', title: '결과지 촬영 요령',
      body: [
        h('ul', { style: { paddingLeft: '18px', margin: '0 0 10px' } }, [
          h('li', { text: '표 전체가 프레임 안에 들어오게' }),
          h('li', { text: '정면에서, 기울이지 말고' }),
          h('li', { text: '형광등 반사·그림자 피하기' }),
          h('li', { text: '영수증형(감열지)은 빛바램이 심하니 바로 촬영' })
        ]),
        h('div.note', { text: '프로토타입에서는 실제 카메라 대신 내장 샘플로 판독을 흉내 냅니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '샘플로 진행', kind: 'primary', onClick: function () { if (onPick) onPick(); } }
      ]
    });
  };

  /* M02 파일 오류 */
  M.fileError = function (msg) {
    UI.openModal({
      uid: 'M02', title: '이 파일은 쓸 수 없습니다',
      body: h('div', { text: msg || 'JPG · PNG · HEIC 형식, 10MB 이하만 올릴 수 있습니다.' }),
      actions: [{ label: '확인', kind: 'primary' }]
    });
  };

  /* M03 판독 실패 */
  M.parseFailed = function (onRetry, onManual) {
    UI.openModal({
      uid: 'M03', title: '결과지를 찾지 못했습니다',
      body: [
        h('p', { text: '아래 중 하나일 가능성이 높습니다.' }),
        h('ul', { style: { paddingLeft: '18px' } }, [
          h('li', { text: '초점이 흐리거나 손떨림' }),
          h('li', { text: '표 일부가 잘림' }),
          h('li', { text: '조명 반사로 숫자가 날아감' })
        ])
      ],
      actions: [
        { label: '다시 올리기', onClick: onRetry },
        { label: '직접 입력', kind: 'primary', onClick: onManual }
      ]
    });
  };

  /* M04 판독 신뢰도 낮음 */
  M.lowConfidence = function (fields, onGo) {
    UI.openModal({
      uid: 'M04', title: '확실히 읽지 못한 항목이 있습니다',
      body: [
        h('p', { text: fields.length + '개 항목을 자신 있게 읽지 못했습니다. 직접 확인해 주세요.' }),
        h('div.chips', fields.map(function (f) { return h('span.chip', { text: f }); }))
      ],
      actions: [{ label: '확인하러 가기', kind: 'primary', onClick: onGo }]
    });
  };

  /* M05 직접 입력 전환 */
  M.switchToManual = function (onConfirm) {
    UI.openModal({
      uid: 'M05', title: '직접 입력으로 바꿀까요?',
      body: h('div', { text: '판독된 값이 모두 지워지고 빈 폼에서 시작합니다.' }),
      actions: [{ label: '취소', kind: 'ghost' },
                { label: '계속', kind: 'primary', onClick: onConfirm }]
    });
  };

  /* M06 용어 사전 */
  var GLOSSARY = [
    ['골격근량 (SMM)', '팔·다리·몸통의 골격근 무게. 흔히 말하는 "근육량"이 이것입니다. 근력(드는 무게)과는 다릅니다.'],
    ['체지방량 (BFM)', '몸에 저장된 지방의 총 무게.'],
    ['체지방률 (PBF)', '체중 대비 체지방 비율. 남성 10~20%가 표준, 15% 전후가 흔한 목표입니다.'],
    ['제지방량 (FFM)', '체중에서 지방을 뺀 나머지 전부 (근육·뼈·수분·장기).'],
    ['기초대사량 (BMR)', '아무것도 안 하고 누워만 있어도 쓰는 하루 열량.'],
    ['내장지방 레벨 (VFL)', '복부 장기 주변 지방 지표. 10 이상이면 관리 대상입니다.'],
    ['복부지방률 (WHR)', '허리/엉덩이 둘레 비. 남성 0.90 이상이면 복부비만 경향.'],
    ['TDEE', 'BMR에 활동량을 곱한 하루 총 소비 열량. 식단 계산의 기준선입니다.'],
    ['리컴프', '체지방을 줄이면서 동시에 근육을 늘리는 것. 초보자·복귀자·체지방이 높은 사람에게 잘 됩니다.'],
    ['RPE', '체감 난이도 10점 척도. RPE 8이면 "2회 더 할 수 있었다" 정도.']
  ];
  M.glossary = function (focus) {
    UI.openModal({
      uid: 'M06', title: '용어 사전',
      body: h('div', GLOSSARY.map(function (g) {
        var hit = focus && g[0].indexOf(focus) >= 0;
        return h('div', { style: { marginBottom: '12px',
          background: hit ? 'var(--accent-sub)' : 'transparent', borderRadius: '8px',
          padding: hit ? '8px' : '0' } }, [
          h('div', { style: { fontWeight: '800', fontSize: '13px' }, text: g[0] }),
          h('div', { style: { fontSize: '12.5px', color: 'var(--text-2)' }, text: g[1] })
        ]);
      })),
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };

  /* M07 위험한 목표 (필수지방 미만 등) */
  M.unsafeGoal = function (info, essentialFat) {
    UI.openModal({
      uid: 'M07', title: '이 목표는 설정할 수 없습니다', dismissable: true,
      body: [
        h('div.note.note--bad', [
          h('b', { text: '목표 체지방률 ' + UI.n1(info.targetPbfPct) + '%' }),
          ' 는 필수지방(약 ' + essentialFat + '%) 아래입니다.'
        ]),
        h('p', { text: '이 구간에서는 호르몬 이상, 면역 저하, 수행능력 급락이 흔하게 보고됩니다. ' +
                       '보디빌딩 대회 직전 며칠만 유지하는 수준이고, 목표로 삼을 상태가 아닙니다.' })
      ],
      actions: [{ label: '목표 다시 정하기', kind: 'primary' }]
    });
  };

  /* M08 목표 숫자 불일치 */
  M.inconsistentGoal = function (info, onFix) {
    UI.openModal({
      uid: 'M08', title: '세 숫자가 서로 안 맞습니다',
      body: [
        h('p', { text: '체중 = 제지방량 + 체지방량 입니다. 입력하신 골격근량과 체지방량으로 계산하면 ' +
                       '체중은 약 ' + UI.n1(info.impliedWeightKg) + 'kg이 됩니다.' }),
        h('div.note.note--warn', { text: '입력한 목표 체중과 ' + UI.sign(info.mismatchKg) + 'kg 차이납니다.' })
      ],
      actions: [
        { label: '체중 맞추고 진행', kind: 'primary', onClick: onFix },
        { label: '돌아가서 수정', kind: 'ghost' }
      ]
    });
  };

  /* M09 강도 상세 */
  M.levelDetail = function (r, cmp) {
    var traj = r.sim.trajectory;
    UI.openModal({
      uid: 'M09', title: '강도 ' + r.label + ' · ' + r.title,
      sub: UI.weeksToHuman(r.weeks) + ' · 목표일 ' + UI.dateK(r.targetDate),
      body: [
        h('div.note', { text: r.sim.strategyDesc }),
        UI.lineChart({
          uid: 'M09-G01', label: '이 강도의 궤적', height: 150,
          series: [
            { key: 'w', label: '체중', color: 'var(--weight)', dots: false,
              points: traj.map(function (t) { return { x: t.week, y: t.weightKg }; }) },
            { key: 's', label: '골격근량', color: 'var(--muscle)', dots: false,
              points: traj.map(function (t) { return { x: t.week, y: t.smmKg }; }) },
            { key: 'f', label: '체지방량', color: 'var(--fat)', dots: false,
              points: traj.map(function (t) { return { x: t.week, y: t.bfmKg }; }) }
          ],
          xTickFmt: function (v) { return Math.round(v) + '주'; }
        }),
        h('hr.sep'),
        kv('주당 체중 변화', UI.sign(r.weeklyRateKg, 2) + 'kg (' + UI.n2(r.weeklyRatePct) + '%)'),
        kv('주당 체지방 변화', UI.sign(r.weeklyFatKg, 2) + 'kg'),
        kv('주당 골격근 변화', UI.sign(r.weeklySmmKg, 2) + 'kg'),
        kv('하루 섭취', r.macros.intakeKcal + ' kcal'),
        kv('유지 칼로리', r.macros.tdeeKcal + ' kcal'),
        kv('단백질', r.macros.proteinG + 'g (' + r.macros.proteinPerBW + ' g/kg)'),
        kv('운동', '주 ' + r.daysPerWeek + '회 · ' + r.sessionMin + '분'),
        kv('유산소', '주 ' + r.cardioMin + '분'),
        kv('근육군당 주간 세트', r.setsPerMuscle + '세트'),
        kv('기록 요구', r.tracking),
        kv('외식/치팅', r.cheatMeals === 0 ? '사실상 불가' : '주 ' + r.cheatMeals + '회'),
        kv('근손실 위험', r.muscleLossRisk),
        r.sim.alternative ? h('div.note', { style: { marginTop: '10px' },
          text: '같은 강도로 ' + r.sim.alternative.strategyLabel + ' 전략을 쓰면 ' +
                r.sim.alternative.weeks + '주가 걸립니다. 엔진은 더 빠른 쪽을 골랐습니다.' }) : null,
        r.capNote ? h('div.note.note--warn', { text: r.capNote }) : null,
        r.floorNote ? h('div.note.note--warn', { text: r.floorNote }) : null
      ],
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };

  /* M10 강도 변경 확인 */
  M.changeLevel = function (onPick) {
    UI.openModal({
      uid: 'M10', title: '강도를 바꿀까요?',
      body: h('div', { text: '현재 플랜이 새 강도로 교체됩니다. 측정 기록과 체크인 기록은 그대로 남습니다.' }),
      actions: [
        { label: '상', onClick: function () { onPick('high'); } },
        { label: '중', onClick: function () { onPick('mid'); } },
        { label: '하', onClick: function () { onPick('low'); } },
        { label: '취소', kind: 'ghost' }
      ]
    });
  };

  /* M11 플랜 재생성 */
  M.regeneratePlan = function () {
    UI.openModal({
      uid: 'M11', title: '플랜을 다시 만들까요?',
      body: h('div', { text: '가장 최근 측정값을 기준으로 새로 계산합니다. 지금까지의 체크인 기록은 남습니다.' }),
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '다시 만들기', kind: 'primary', onClick: function () {
            var st = S.get(), scan = S.latestScan();
            var prof = st.profile || global.MB_DATA.SEED_PROFILE;
            if (!scan || !st.goal) return;
            var cmp = E.compareLevels(scan, prof, st.goal, todayISO(), st.goal.deadlineWeeks || null);
            var plan = E.buildPlan(cmp, st.plan ? st.plan.level : 'mid', scan, prof);
            S.setPlan(plan);
            global.MB_UID.toast('플랜을 다시 만들었습니다');
            global.MB_APP.refresh();
          } }
      ]
    });
  };

  /* M12 운동 상세 */
  M.exerciseDetail = function (ex) {
    UI.openModal({
      uid: 'M12', title: ex.name,
      sub: ex.sets + '세트 × ' + ex.reps + '회 · RPE ' + ex.rpe + ' · 휴식 ' + ex.restSec + '초',
      body: [
        ex.note ? h('div.note', { text: '폼 포인트: ' + ex.note }) : null,
        kv('장비', ({ barbell: '바벨', dumbbell: '덤벨', machine: '머신/케이블',
                      bodyweight: '맨몸' })[ex.equip] || ex.equip),
        kv('목표 부위', ({ chest: '가슴', back: '등', shoulder: '어깨', arms: '팔',
                          quads: '대퇴사두', hamsGlutes: '햄스트링·둔근', core: '코어' })[ex.group] || ex.group),
        h('p', { style: { marginTop: '10px' },
          text: '목표 반복 수 상단(' + String(ex.reps).split('-')[1] + '회)을 모든 세트에서 채우면 ' +
                '다음 세션에 중량을 2.5~5kg 올립니다.' })
      ],
      actions: [
        { label: '대체 종목', onClick: function () { M.swapExercise(ex); } },
        { label: '닫기', kind: 'primary' }
      ]
    });
  };

  /* M13 대체 운동 */
  M.swapExercise = function (ex) {
    var pool = (global.MB_DATA.EXERCISES[ex.group] || []).filter(function (x) { return x.name !== ex.name; });
    UI.openModal({
      uid: 'M13', title: '대체 종목',
      sub: '같은 부위를 자극하는 다른 선택지',
      body: pool.length ? h('div', pool.map(function (x) {
        return h('div.radio-card', { onClick: function () {
          global.MB_UID.toast('프로토타입에서는 교체가 저장되지 않습니다');
        } }, [
          h('div', [h('div.radio-card__t', { text: x.name }),
                    h('div.radio-card__d', { text: x.note || x.equip })])
        ]);
      })) : h('div.empty', { text: '대체 종목이 없습니다' }),
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };

  /* M14 식단 상세 / M15 음식 교체 */
  M.mealDetail = function (meal) {
    UI.openModal({
      uid: 'M14', title: meal.name,
      sub: meal.kcal + ' kcal · P' + meal.proteinG + ' C' + meal.carbG + ' F' + meal.fatG,
      body: meal.options.map(function (o) {
        return h('div', { style: { marginBottom: '10px' } }, [
          h('div', { style: { fontWeight: '700' }, text: o.label }),
          h('ul', { style: { paddingLeft: '18px', margin: '4px 0' } },
            o.items.map(function (i) { return h('li', { text: i }); }))
        ]);
      }),
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };
  M.swapMeal = function (meal) {
    var F = global.MB_DATA.FOODS;
    UI.openModal({
      uid: 'M15', title: meal.name + ' 교체',
      sub: '목표 ' + meal.kcal + ' kcal · 단백질 ' + meal.proteinG + 'g',
      body: h('div', F.filter(function (f) { return f.tags.indexOf('protein') >= 0; }).map(function (f) {
        return h('div.radio-card', { onClick: function () {
          global.MB_UID.toast('프로토타입에서는 교체가 저장되지 않습니다');
        } }, [
          h('div', [h('div.radio-card__t', { text: f.name }),
                    h('div.radio-card__d', { text: f.unit + ' · ' + f.kcal + 'kcal · 단백질 ' + f.p + 'g' })])
        ]);
      })),
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };

  /* M16 리마인더 */
  M.reminder = function () {
    UI.openModal({
      uid: 'M16', title: '체크인 알림',
      body: [
        h('p', { text: '매주 같은 요일·시간에 측정하면 수분 변동에 덜 속습니다.' }),
        h('div.chips', ['월', '화', '수', '목', '금', '토', '일'].map(function (d, i) {
          return h('button.chip' + (i === 0 ? '.is-on' : ''), { text: d });
        })),
        h('div.note', { style: { marginTop: '10px' },
          text: '프로토타입에서는 실제 알림이 가지 않습니다.' })
      ],
      actions: [{ label: '취소', kind: 'ghost' }, { label: '저장', kind: 'primary' }]
    });
  };

  /* M17 재조정 제안 */
  M.adjust = function (advice, onApply) {
    UI.openModal({
      uid: 'M17', title: '계획을 조정할까요?',
      sub: ({ onTrack: '예상 범위 안', slow: '예상보다 느림', fast: '예상보다 빠름',
              adherence: '순응도 문제' })[advice.status] || '',
      body: advice.suggestions.map(function (s) {
        return h('div.radio-card', { style: { marginBottom: '6px' } }, [
          h('div', [h('div.radio-card__t', { text: s.title }),
                    h('div.radio-card__d', { text: s.detail })])
        ]);
      }),
      actions: [
        { label: '이번엔 유지', kind: 'ghost' },
        { label: '적용', kind: 'primary', onClick: onApply }
      ]
    });
  };

  /* M18 전체 초기화 */
  M.resetAll = function () {
    var input;
    UI.openModal({
      uid: 'M18', title: '모든 데이터를 지울까요?',
      body: [
        h('div.note.note--bad', { text: '측정 기록, 목표, 플랜, 체크인이 전부 삭제되며 되돌릴 수 없습니다.' }),
        h('p', { text: '확인을 위해 아래에 "초기화" 라고 입력해 주세요.' }),
        input = h('input.input', { placeholder: '초기화' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '삭제', kind: 'danger', onClick: function () {
            if (input.value.trim() !== '초기화') {
              global.MB_UID.toast('"초기화" 라고 정확히 입력해 주세요');
              return true;   // 닫지 않음
            }
            S.reset(); global.MB_UID.toast('모두 지웠습니다'); global.MB_APP.go('P01');
          } }
      ]
    });
  };

  /* M19 스캔 삭제 */
  M.deleteScan = function (scan, onDone) {
    UI.openModal({
      uid: 'M19', title: '이 측정을 삭제할까요?',
      body: h('div', { text: UI.dateK(scan.measuredAt) + ' 측정이 삭제되고 추이 그래프가 바뀝니다.' }),
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '삭제', kind: 'danger', onClick: function () {
            S.removeScan(scan.id); global.MB_UID.toast('삭제했습니다'); if (onDone) onDone();
          } }
      ]
    });
  };

  /* M20 내보내기 */
  M.exportPlan = function (plan) {
    var text = planToText(plan);
    UI.openModal({
      uid: 'M20', title: '플랜 내보내기',
      body: h('textarea.textarea', { rows: 12, readonly: true, value: text }),
      actions: [
        { label: '닫기', kind: 'ghost' },
        { label: '복사', kind: 'primary', onClick: function () {
            navigator.clipboard && navigator.clipboard.writeText(text);
            global.MB_UID.toast('복사했습니다');
          } }
      ]
    });
  };
  M.exportData = function () {
    var text = S.exportJSON();
    UI.openModal({
      uid: 'M20', title: '데이터 내보내기',
      sub: '전체 상태를 JSON으로',
      body: h('textarea.textarea', { rows: 12, readonly: true, value: text }),
      actions: [
        { label: '닫기', kind: 'ghost' },
        { label: '복사', kind: 'primary', onClick: function () {
            navigator.clipboard && navigator.clipboard.writeText(text);
            global.MB_UID.toast('복사했습니다');
          } }
      ]
    });
  };

  /* M21 단위 변경 */
  M.unitChange = function () {
    UI.openModal({
      uid: 'M21', title: '단위를 바꿀까요?',
      body: h('div', { text: '저장된 값이 환산되어 표시됩니다. 프로토타입은 kg/cm만 지원합니다.' }),
      actions: [{ label: '확인', kind: 'primary' }]
    });
  };

  /* M22 온보딩 건너뛰기 */
  M.skipOnboarding = function (onSkip) {
    UI.openModal({
      uid: 'M22', title: '기본값으로 시작할까요?',
      body: h('div', { text: '키·나이·성별이 없으면 칼로리 계산이 부정확해집니다. ' +
                             '남성 / 30세 / 175cm / 보통 활동으로 시작합니다.' }),
      actions: [{ label: '계속 입력', kind: 'ghost' },
                { label: '건너뛰기', kind: 'primary', onClick: onSkip }]
    });
  };

  /* M23 저장되지 않은 변경 */
  M.unsaved = function (onLeave) {
    UI.openModal({
      uid: 'M23', title: '저장하지 않고 나갈까요?',
      body: h('div', { text: '수정한 내용이 사라집니다.' }),
      actions: [{ label: '계속 편집', kind: 'ghost' },
                { label: '나가기', kind: 'danger', onClick: onLeave }]
    });
  };

  /* M24 의학적 고지 */
  M.disclaimer = function () {
    UI.openModal({
      uid: 'M24', title: '시작하기 전에', dismissable: false,
      body: [
        h('div.note.note--warn', [
          h('b', { text: '이 앱은 의료기기가 아닙니다. ' }),
          '진단·치료·예방을 목적으로 하지 않으며, 제공되는 운동·식단은 일반적인 정보입니다.'
        ]),
        h('ul', { style: { paddingLeft: '18px', fontSize: '13px', color: 'var(--text-2)' } }, [
          h('li', { text: '기저질환, 임신·수유 중, 섭식장애 이력이 있다면 반드시 전문가와 상의하세요.' }),
          h('li', { text: '인바디(생체전기임피던스)는 수분 상태에 민감해 하루 중에도 값이 흔들립니다.' }),
          h('li', { text: '모든 데이터는 이 기기에만 저장되며 서버로 전송되지 않습니다.' })
        ])
      ],
      actions: [{ label: '이해했습니다', kind: 'primary', onClick: function () {
        S.set({ disclaimerAccepted: true });
      } }]
    });
  };

  /* M25 상강도 경고 */
  M.hardIntensityWarn = function (r, onConfirm) {
    UI.openModal({
      uid: 'M25', title: '강도 ' + r.label + ' 는 짧게만 쓰세요',
      body: [
        h('div.note.note--warn', [
          h('b', { text: '근손실 위험: ' + r.muscleLossRisk + '. ' }),
          '외식은 ' + (r.cheatMeals === 0 ? '사실상 불가능하고' : '주 ' + r.cheatMeals + '회로 제한되고') +
          ', ' + r.tracking + '가 필요합니다.'
        ]),
        h('p', { text: '이 강도를 오래 끌면 대사적응과 번아웃이 옵니다. ' +
                       '중간에 유지기를 넣는 것을 전제로 선택하세요.' })
      ],
      actions: [
        { label: '다시 고르기', kind: 'ghost' },
        { label: '그래도 진행', kind: 'primary', onClick: onConfirm }
      ]
    });
  };

  /* M33 목표 변경 확인 — 지금 플랜을 어떻게 할지 고르게 한다 */
  M.changeGoal = function (opts) {
    var oldG = opts.oldGoal, newG = opts.newGoal, plan = opts.plan;
    function row(label, a, b, unit) {
      var d = b - a;
      return h('div.kv', [
        h('span.kv__k', { text: label }),
        h('span.kv__v', [
          UI.n1(a) + unit + ' → ',
          h('span', { style: { color: 'var(--accent)' }, text: UI.n1(b) + unit }),
          h('span', { style: { color: 'var(--text-3)', fontWeight: '600', marginLeft: '6px',
                               fontSize: '11.5px' },
                      text: Math.abs(d) < 0.05 ? '그대로' : '(' + UI.sign(d) + unit + ')' })
        ])
      ]);
    }
    UI.openModal({
      uid: 'M33', title: '목표를 바꿀까요?',
      sub: plan ? '지금 플랜은 이전 목표로 만든 것입니다' : null,
      body: [
        row('체중', oldG.weightKg, newG.weightKg, 'kg'),
        row('골격근량', oldG.smmKg, newG.smmKg, 'kg'),
        row('체지방량', oldG.bfmKg, newG.bfmKg, 'kg'),
        plan ? h('div.note', { style: { marginTop: '12px' } }, [
          h('b', { text: '지금 플랜: ' }),
          plan.label + ' 강도 · ' + UI.dateK(plan.targetDate) + ' 목표'
        ]) : null,
        h('div.muted', { style: { marginTop: '8px' },
          text: '측정 기록과 체크인은 그대로 남습니다. 이전 목표도 기록에 남습니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        plan ? { label: '강도 유지', uid: 'M33-B02',
                 onClick: function () { opts.onKeepLevel(); } } : null,
        { label: plan ? '강도 다시 고르기' : '계속', kind: 'primary', uid: 'M33-B03',
          onClick: function () { opts.onPickLevel(); } }
      ].filter(Boolean)
    });
  };

  /* M34 목표 달성 — 다음 단계를 고르게 한다 */
  M.goalReached = function (opts) {
    UI.openModal({
      uid: 'M34', title: '목표에 도달했습니다',
      sub: opts.summary,
      body: [
        h('div.note.note--ok', { text: '여기서 멈추면 되돌아오기 쉽습니다. 다음을 정해두는 편이 낫습니다.' }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '감량을 마쳤다면 바로 다음 감량으로 넘어가지 말고, 2~4주 유지로 한 번 쉬어가는 것이 좋습니다.' })
      ],
      actions: [
        { label: '나중에', kind: 'ghost' },
        { label: '유지로 전환', uid: 'M34-B02', onClick: function () { opts.onMaintain(); } },
        { label: '새 목표 정하기', kind: 'primary', uid: 'M34-B03', onClick: function () { opts.onNewGoal(); } }
      ]
    });
  };

  /* --- 조각 --- */
  function kv(k, v) {
    return h('div.kv', [h('span.kv__k', { text: k }), h('span.kv__v', { text: v })]);
  }
  function todayISO() {
    var d = new Date();
    return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' +
           String(d.getDate()).padStart(2, '0');
  }
  function planToText(plan) {
    var L = [];
    L.push('# Mybody 플랜 — 강도 ' + plan.label + ' (' + plan.title + ')');
    L.push('시작 ' + plan.startDate + ' → 목표 달성 예정 ' + plan.targetDate + ' (' + plan.weeks + '주)');
    L.push('전략: ' + plan.strategyLabel + ' — ' + plan.strategyDesc);
    L.push('');
    L.push('## 하루 목표');
    L.push('섭취 ' + plan.macros.intakeKcal + ' kcal / 단백질 ' + plan.macros.proteinG +
           'g / 탄수 ' + plan.macros.carbG + 'g / 지방 ' + plan.macros.fatG + 'g');
    L.push('');
    L.push('## 운동 — ' + plan.workout.splitName + ' (주 ' + plan.workout.daysPerWeek + '회)');
    plan.workout.sessions.forEach(function (s, i) {
      var d = ['월','화','수','목','금','토','일'][i];
      if (s.rest) { L.push('- ' + d + ': 휴식'); return; }
      L.push('- ' + d + ' · ' + s.label);
      s.exercises.forEach(function (e) {
        L.push('    · ' + e.name + ' ' + e.sets + '×' + e.reps + ' (RPE ' + e.rpe + ')');
      });
    });
    L.push('');
    L.push('## 식단');
    plan.diet.meals.forEach(function (m) {
      L.push('- ' + m.name + ': ' + m.kcal + 'kcal / 단백질 ' + m.proteinG + 'g');
      m.options.forEach(function (o) { L.push('    · ' + o.label + ': ' + o.items.join(', ')); });
    });
    L.push('');
    L.push('## 마일스톤');
    plan.milestones.forEach(function (ms) {
      L.push('- ' + ms.week + '주 (' + ms.date + '): 체중 ' + ms.weightKg + ' / 골격근 ' +
             ms.smmKg + ' / 체지방 ' + ms.bfmKg + ' (' + ms.pbfPct + '%)');
    });
    return L.join('\n');
  }

  global.MB_MODALS = M;
})(window);
