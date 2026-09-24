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
        /* "사진은 이 기기에만 저장됩니다" 를 고정으로 적어 뒀었습니다.
           자동 판독이 켜져 있으면 거짓입니다. 상태를 읽어서 말합니다. */
        h('div.note', { text: (global.MB_SYNC && global.MB_SYNC.canOcr && global.MB_SYNC.canOcr())
          ? '자동 판독이 켜져 있습니다 — 판독을 누르면 이 사진이 서버로 올라갑니다. 누르지 않으면 기기에만 남습니다.'
          : '사진은 이 기기에만 저장됩니다. 찍고 나면 사진을 보면서 숫자 세 개만 옮겨 적으면 됩니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '사진 고르기', kind: 'primary', onClick: function () { if (onPick) onPick(); } }
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
  /* @param floorPct  이 앱이 허용하는 하한 (남 8 · 여 15).
     필수지방과는 다른 숫자입니다 — 필수지방은 "이 밑으로는 살 수 없다",
     하한은 "이 앱은 여기까지만 도와준다" 입니다. 섞어 쓰면 한 화면에
     서로 다른 숫자가 나오고, 그러면 이 경고를 아무도 안 믿습니다. */
  M.unsafeGoal = function (info, floorPct) {
    UI.openModal({
      uid: 'M07', title: '이 목표는 설정할 수 없습니다', dismissable: true,
      body: [
        h('div.note.note--bad', [
          h('b', { text: '목표 체지방률 ' + UI.n1(info.targetPbfPct) + '%' }),
          ' 는 이 앱이 도와주는 하한(' + floorPct + '%) 아래입니다.'
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
                    h('div.radio-card__d', { text: f.unit + ' ' + f.g + 'g · ' + f.kcal +
                                                   'kcal · 단백질 ' + f.p + 'g' })])
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
  /* preview: 적용하면 실제로 바뀌는 숫자 한 줄(하한에 막히면 −150 이 아닐 수 있음).
     제안 제목만 보여 주면 "150kcal 줄이기" 에 동의했는데 44kcal 만 줄어듭니다. */
  M.adjust = function (advice, onApply, preview) {
    UI.openModal({
      uid: 'M17', title: '계획을 조정할까요?',
      sub: ({ onTrack: '계획대로', slow: '두 번 연속 계획보다 느림', fast: '두 번 연속 계획보다 빠름',
              heavy: '두 번 연속 계획보다 무거움', light: '두 번 연속 계획보다 가벼움',
              adherence: '순응도 문제' })[advice.status] || '',
      body: advice.suggestions.map(function (s) {
        return h('div.radio-card', { style: { marginBottom: '6px' } }, [
          h('div', [h('div.radio-card__t', { text: s.title }),
                    h('div.radio-card__d', { text: s.detail })])
        ]);
      }).concat(preview ? [h('div.note', { style: { marginTop: '8px' },
        text: '실제로 바뀌는 것 — ' + preview })] : []),
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
        h('div.note.note--bad', { text: '측정 기록, 목표, 플랜, 체크인, 운동 일정, 식단 기록, ' +
          '결과지 사진이 전부 삭제되며 되돌릴 수 없습니다.' }),
        /* 친구 쪽도 같이 지웁니다.
           이 기기에는 친구의 이름 · 프로필 사진 · 그 사람이 나에게 보여
           주기로 한 숫자가 거울로 남아 있습니다. "모두 지웠습니다" 를
           읽고 폰을 넘기는 사람에게, 남의 얼굴과 몸 숫자가 남아 있으면
           안 됩니다. 로그인 상태로 두면 다음 동기화에 그대로 다시
           내려오므로, 지우는 것과 로그아웃은 같이 가야 합니다. */
        h('div.note', { text: '이 기기에 받아 둔 친구 목록 · 프로필 사진 · 친구 소식도 같이 지우고 ' +
          '로그아웃합니다. 계정과 서버의 기록은 남아 있어서, 다시 로그인하면 친구는 돌아옵니다.' }),
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
            S.reset();
            /* 서버에 말은 걸어 보되, 기다리지 않습니다 — 오프라인이라고
               지우기가 안 되면 안 됩니다. 토큰과 거울은 어느 쪽이든
               이 기기에서 사라집니다. */
            var SY = global.MB_SYNC;
            var done = (SY && SY.status().signedIn)
              ? SY.signOut().catch(function () {})
              : Promise.resolve(global.MB_BACKEND && global.MB_BACKEND.reset());
            done.then(function () {
              global.MB_UID.toast('모두 지웠습니다');
              global.MB_APP.go('P01');
            });
          } }
      ]
    });
  };

  /* M19 스캔 삭제 */
  M.deleteScan = function (scan, onDone) {
    UI.openModal({
      uid: 'M19', title: '이 측정을 삭제할까요?',
      body: h('div', { text: UI.dateK(scan.measuredAt) + ' 측정이 삭제되고 추이 그래프가 바뀝니다.' +
        (scan.photoId ? ' 이 측정에 딸린 결과지 사진도 같이 지워집니다.' : '') }),
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
        { label: '복사', kind: 'primary', onClick: function () { UI.copyText(text); } }
      ]
    });
  };
  /* 측정 기록은 서버로 안 올라갑니다. 그러니까 여기가 유일한 백업입니다.
     그런데 "복사" 만 있으면 붙여넣을 곳을 미리 정해 둔 사람만 백업이
     남습니다 — 폰에서는 그게 대부분 아무 데도 아닙니다. 파일로 떨어뜨리면
     다운로드 폴더에 남고, 그건 기기를 정리해도 보통 살아남습니다. */
  M.exportData = function () {
    var text = S.exportJSON();
    var stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    var name = 'mybody-' + stamp + '.json';
    UI.openModal({
      uid: 'M43', title: '데이터 내보내기',
      sub: '측정 기록은 서버에 없습니다 — 이 파일이 유일한 백업입니다',
      body: [
        h('textarea.textarea', { rows: 10, readonly: true, value: text }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '기기를 바꾸거나 앱을 지우면 기록이 같이 사라집니다. ' +
                '새 기기에서 설정 → 가져오기로 이 파일을 넣으면 그대로 돌아옵니다.' })
      ],
      actions: [
        { label: '닫기', kind: 'ghost' },
        { label: '복사', onClick: function () { UI.copyText(text); } },
        { label: '파일로 저장', kind: 'primary',
          uid: 'M43-B10', uidLabel: '파일로 저장',
          onClick: function () {
            var url = null;
            try {
              var blob = new Blob([text], { type: 'application/json' });
              url = URL.createObjectURL(blob);
              var a = h('a', { href: url, download: name, style: { display: 'none' } });
              document.body.appendChild(a);
              a.click();
              a.remove();
              global.MB_UID.toast(name + ' 으로 저장했습니다');
            } catch (e) {
              /* 막히는 브라우저가 있습니다. "저장했습니다" 라고 거짓말하면
                 백업이 있다고 믿은 채로 기기를 정리합니다. */
              global.MB_UID.toast('파일로 저장이 안 됩니다 — 복사해서 옮겨 주세요');
            }
            /* 취소 버튼 없이 바로 받는 브라우저를 위해 조금 뒤에 놓습니다.
               즉시 revoke 하면 다운로드가 시작도 못 하고 끊깁니다. */
            if (url) setTimeout(function () { try { URL.revokeObjectURL(url); } catch (e) {} }, 30000);
            return true;   // 모달은 열어 둡니다 — 복사도 같이 하고 싶을 수 있습니다
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
  M.disclaimer = function (force) {
    /* 이미 수락했으면 다시 띄우지 않습니다.
       예전엔 온보딩 완료·건너뛰기가 수락 여부를 확인하지 않고 무조건 불러서,
       "이해했습니다"를 누른 뒤에도 완료를 다시 누르면 또 떴습니다.
       호출처마다 조건을 다는 대신 여기서 막습니다 — 빠뜨릴 수가 없는 자리입니다.
       force 는 설정에서 사용자가 일부러 다시 볼 때만 씁니다. */
    if (!force && S.get().disclaimerAccepted) return;
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
          h('li', { text: '로그인하지 않으면 모든 데이터가 이 기기에만 저장됩니다.' }),
          h('li', { text: '로그인하면 측정값이 내가 지정한 서버로 올라갑니다. 친구에게 무엇이 보일지는 친구마다 따로 켜야 하고, 기본으로 켜진 것은 행동에 대한 셋입니다 — 이번 주에 기록했는지, 계획한 날과 지킨 날의 개수, 그리고 오늘 식단(칼로리 · 탄단지). 몸 숫자는 기본으로 꺼져 있습니다.' })
        ]),
        /* 체성분은 민감정보입니다. 무엇이 어디로 가는지를 처음 화면에서
           읽을 수 있어야 합니다 — 설정 깊숙이에만 있으면 아무도 안 봅니다. */
        h('div', { style: { marginTop: '10px' } }, [
          h('a', { text: '개인정보처리방침 보기', href: './privacy.html',
                   target: '_blank', rel: 'noopener',
                   uid: 'M24-B10', uidLabel: '개인정보처리방침',
                   style: { fontSize: '13px', fontWeight: '700' } })
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

  /* M42 비밀번호 변경 — 바꾸면 다른 기기 세션이 전부 끊깁니다 */
  M.changePassword = function (onDone) {
    var cur, next, next2, msg, busy = false;
    UI.openModal({
      uid: 'M42', title: '비밀번호 변경',
      body: [
        h('div.field', [h('div.field__label', { text: '지금 비밀번호' }),
          cur = h('input.input', { uid: 'M42-F01', uidLabel: '지금 비밀번호', type: 'password' })]),
        h('div.field', [h('div.field__label', { text: '새 비밀번호' }),
          next = h('input.input', { uid: 'M42-F02', uidLabel: '새 비밀번호', type: 'password',
            placeholder: '8자 이상' })]),
        h('div.field', [h('div.field__label', { text: '새 비밀번호 확인' }),
          next2 = h('input.input', { uid: 'M42-F03', uidLabel: '새 비밀번호 확인', type: 'password' })]),
        msg = h('div.field__err', { style: { display: 'none' } }),
        h('div.muted', { style: { marginTop: '10px' },
          text: '바꾸면 다른 기기에서 전부 로그아웃됩니다. 토큰이 샜을 때의 복구 수단이기도 합니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '바꾸기', kind: 'primary', onClick: function (close) {
            if (busy) return true;
            var S = global.MB_SYNC;
            if (!S || !S.status().signedIn) {
              msg.textContent = '로그인 상태가 아닙니다'; msg.style.display = ''; return true;
            }
            if ((next.value || '').length < 8) {
              msg.textContent = '새 비밀번호는 8자 이상이어야 합니다'; msg.style.display = ''; return true;
            }
            if (next.value !== next2.value) {
              msg.textContent = '새 비밀번호가 서로 다릅니다'; msg.style.display = ''; return true;
            }
            busy = true; msg.textContent = '확인 중...'; msg.style.display = '';
            S.changePassword({ current: cur.value, next: next.value }).then(function () {
              global.MB_UID.toast('비밀번호를 바꿨습니다');
              if (onDone) onDone();
              close();
            }).catch(function (e) {
              msg.textContent = e.message; msg.style.display = ''; busy = false;
            });
            return true;
          } }
      ]
    });
  };

  /* M38 서버 주소 — 자가호스팅이라 기기마다 다를 수 있습니다 */
  M.serverAddress = function (onDone) {
    var S = global.MB_SYNC;
    var cur = S ? (S.status().baseUrl || '') : '';
    var input, msg;
    UI.openModal({
      uid: 'M38', title: '서버 주소',
      sub: '이 앱의 데이터를 보관하는 곳',
      body: [
        input = h('input.input', { uid: 'M38-F01', uidLabel: '서버 주소',
          value: cur, placeholder: 'http://192.168.0.10:8080',
          autocapitalize: 'none', autocorrect: 'off' }),
        msg = h('div.field__err', { style: { display: 'none' } }),
        h('div.muted', { style: { marginTop: '10px' },
          text: '집 컴퓨터에서 서버를 돌리고 있다면 그 컴퓨터의 주소입니다. ' +
                '비워두면 이 기기에만 저장되고 친구 기능은 쓸 수 없습니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '저장', kind: 'primary', onClick: function (close) {
            var v = (input.value || '').trim();
            if (v && !/^https?:\/\//.test(v)) {
              msg.textContent = 'http:// 또는 https:// 로 시작해야 합니다';
              msg.style.display = ''; return true;
            }
            if (!v) {
              S.configure(null);
              global.MB_UID.toast('이 기기에만 저장합니다');
              if (onDone) onDone();
              return;
            }

            /* 저장하기 전에 실제로 닿는지 두드려 봅니다.
             *
             * 예전엔 무조건 "서버를 바꿨습니다" 라고 했습니다. 그런데
             * 이 창은 대개 안 되는 상황에서 열립니다 — 주소를 잘못
             * 알았거나, 서버가 안 떠 있거나, https 페이지에서 http
             * 주소를 넣어(브라우저가 통째로 막습니다) 그렇습니다.
             * 성공했다고 말해 놓고 그 다음 화면이 다시 "서버가
             * 없습니다" 라고 하면, 사람은 뭘 잘못했는지 모른 채
             * 주소만 계속 고칩니다. */
            msg.style.display = ''; msg.textContent = '확인 중...';
            var mixed = false;
            try {
              mixed = location.protocol === 'https:' && /^http:\/\//.test(v);
            } catch (e) {}
            if (mixed) {
              msg.textContent = '지금 이 페이지는 https 인데 넣으신 주소는 http 입니다. ' +
                                '브라우저가 그 사이의 연결을 통째로 막아서, 저장해도 안 닿습니다. ' +
                                '서버 주소를 폰 브라우저에 직접 열어서 쓰세요.';
              return true;
            }
            S.configure(v);
            S.probe().then(function (okNow) {
              if (okNow) {
                global.MB_UID.toast('서버를 바꿨습니다');
                if (onDone) onDone();
                close();
                return;
              }
              msg.textContent = '저장했지만 지금은 그 주소에 닿지 않습니다. ' +
                                '서버가 꺼져 있거나 주소가 다릅니다 — 서버를 띄운 터미널에 ' +
                                '찍힌 주소를 그대로 쓰세요.';
              if (onDone) onDone();
            });
            return true;
          } }
      ]
    });
  };

  /* ======================================================================
   * M29 로그인 / 가입 — 우리 서버에서 직접
   *
   * 카카오·애플을 쓰지 않는 이유: 외부 OAuth 는 사업자 등록과 앱 심사가
   * 필요하고, "서버는 내 컴퓨터로 사용해"라는 이 앱의 전제와 맞지 않습니다.
   * 아이디는 이메일이 아닙니다 — 이메일을 받으면 보관해야 할 개인정보가
   * 하나 늘어나는데, 이 서버는 비밀번호 재발송을 하지 않으므로 할 일이 없습니다.
   * ==================================================================== */
  M.signIn = function (onDone) {
    var mode = 'in';          // 'in' = 로그인, 'up' = 가입, 'lost' = 비밀번호 잊음
    var body = h('div');
    var handle, pw, pw2, pair, name, rcode, msg, consentBtn, busy = false;
    /* 체크 상태는 draw() 를 지나서도 살아야 합니다 — 탭을 옮겼다
       돌아오면 초기화되는 게 맞고, 같은 탭 안에서 다시 그릴 때는
       유지돼야 합니다. draw() 가 탭을 바꿀 때만 불리므로 여기서
       기억하고 탭이 바뀔 때 끕니다. */
    var consent = false;

    function draw() {
      body.textContent = '';
      msg = h('div.field__err', { style: { display: 'none' } });

      body.appendChild(h('div.chips', { style: { marginBottom: '12px' } }, [
        chip('로그인', 'in', 'M29-B10'), chip('처음이에요', 'up', 'M29-B11'),
        chip('비밀번호 잊음', 'lost', 'M29-B12')
      ]));

      body.appendChild(field('아이디', handle = h('input.input', {
        uid: 'M29-F01', uidLabel: '아이디', value: handle ? handle.value : '',
        autocapitalize: 'none', autocorrect: 'off',
        placeholder: '영문·숫자 3~32자' })));

      if (mode === 'lost') {
        body.appendChild(field('복구 코드', rcode = h('input.input', {
          uid: 'M29-F06', uidLabel: '복구 코드',
          autocapitalize: 'characters', autocorrect: 'off', spellcheck: 'false',
          style: { fontFamily: 'ui-monospace, monospace', letterSpacing: '.06em' },
          placeholder: 'XXXX-XXXX-XXXX-XXXX' })));
      }

      body.appendChild(field(mode === 'lost' ? '새 비밀번호' : '비밀번호', pw = h('input.input', {
        uid: 'M29-F02', uidLabel: mode === 'lost' ? '새 비밀번호' : '비밀번호', type: 'password',
        placeholder: '8자 이상' })));

      if (mode === 'up' || mode === 'lost') {
        body.appendChild(field(mode === 'lost' ? '새 비밀번호 확인' : '비밀번호 확인',
          pw2 = h('input.input', {
            uid: 'M29-F03', uidLabel: '비밀번호 확인', type: 'password' })));
      }
      if (mode === 'up') {
        body.appendChild(field('표시 이름 (선택)', name = h('input.input', {
          uid: 'M29-F04', uidLabel: '표시 이름', maxlength: '20',
          placeholder: '친구에게 보이는 이름' })));
        /* 가입 코드를 안 쓰는 서버면 그 칸을 아예 안 그립니다.
           빈칸으로 남겨 두면 "뭘 넣어야 하지" 에서 사람이 멈춥니다.
           아직 안 물어봤으면(null) 보여 줍니다 — 있는 칸을 빼먹는 쪽이
           없는 칸을 보여 주는 쪽보다 나쁩니다. */
        var openSignup = (global.MB_SYNC && global.MB_SYNC.status().openSignup) === true;
        if (!openSignup) {
          body.appendChild(field('가입 코드', pair = h('input.input', {
            uid: 'M29-F05', uidLabel: '가입 코드',
            placeholder: '서버 주인에게 받은 코드' })));
          body.appendChild(h('div.muted', { style: { marginTop: '6px' },
            text: '이 서버는 공개 가입 서비스가 아닙니다. 주인이 알려준 코드가 있어야 계정을 만들 수 있습니다.' }));
        } else {
          body.appendChild(h('div.muted', { style: { marginTop: '6px' },
            text: '이 서버는 누구나 계정을 만들 수 있습니다. 친구에게 보여 줄 항목은 계정을 만든 뒤 하나씩 켭니다.' }));
        }

        /* 건강정보 업로드 동의 — 계정 만들기와 따로 받습니다.
         *
         * 체성분은 민감정보입니다. 계정을 만드는 것과 "내 몸 숫자를
         * 서버에 올리는 것" 은 다른 일인데, 로그인하면 친구가 하나도
         * 없어도 기록 사본(동기화)과 주간 요약이 올라가므로 가입이 곧
         * 업로드 동의가 됩니다.
         *
         * 판 2026-09-23: 예전 문구는 "주간 요약만" 이라고 했습니다 — 기록
         * 전체를 계정에 저장하게 된 뒤로 거짓이 됐습니다. 문구는 처리방침
         * 「기기와 내 계정에 저장되는 것」과 같게, 판은 sync.js · server/db.js
         * 와 같게 둡니다.
         * 그 동의를 다른 것과 섞어 받으면 안 읽히고, 안 읽힌 동의는
         * 동의가 아닙니다.
         *
         * 네 가지를 한 상자에 적습니다 — 무엇을 · 왜 · 얼마나 오래 ·
         * 거부하면 어떻게 되는지. 특히 마지막이 중요합니다: 거부해도
         * 앱의 계산과 계획은 그대로 됩니다. 못 쓰는 것은 친구 기능뿐입니다. */
        body.appendChild(h('div.note.note--warn', { style: { marginTop: '12px' } }, [
          h('b', { text: '내 기록을 계정(서버)에 저장하는 것에 동의가 필요합니다' }),
          h('ul', { style: { paddingLeft: '18px', margin: '8px 0 0', fontSize: '13px' } }, [
            h('li', { text: '무엇을 — 측정 기록(체중 · 골격근량 · 체지방량 · 체지방률), 프로필(키 · 나이 · ' +
                            '성별 · 운동 경력), 목표 · 계획, 식단 · 운동 기록, 앱 설정. 이 기기와 같은 ' +
                            '내용이 내 계정에도 저장됩니다(동기화). 결과지 사진은 올라가지 않습니다.' }),
            h('li', { text: '왜 — 기기를 바꿔도 기록이 따라오게, 그리고 친구에게 보여 줄 주간 요약을 ' +
                            '만들려고. 친구에게는 친구마다 켠 항목만 보입니다 — 처음에는 기록 여부 · ' +
                            '이번 주 운동 · 오늘 식단만 켜져 있고, 몸 숫자는 꺼져 있습니다.' }),
            h('li', { text: '얼마나 — 기록 사본은 계정을 지울 때까지, 주간 요약은 최근 52주까지. ' +
                            '계정을 지우면 서버에 있는 내 기록이 모두 지워집니다.' }),
            h('li', { text: '거부하면 — 계정을 못 만듭니다. 이 웹 앱은 로그인 없이도 이 기기 안에서 ' +
                            '측정 · 목표 · 계획 · 식단이 되고, 계정 저장과 친구 기능만 못 씁니다.' })
          ]),
          h('div', { style: { marginTop: '10px' } }, [
            consentBtn = h('button.chip', {
              text: '☐ 동의합니다', uid: 'M29-B14', uidLabel: '건강정보 동의',
              onClick: function () {
                consent = !consent;
                consentBtn.className = 'chip' + (consent ? ' is-on' : '');
                consentBtn.textContent = (consent ? '☑' : '☐') + ' 동의합니다';
              }
            })
          ])
        ]));
      }

      body.appendChild(msg);
      body.appendChild(h('div', { style: { marginTop: '10px' } }, [
        h('a', { text: '무엇이 서버로 가는지 보기 (개인정보처리방침)',
                 href: './privacy.html', target: '_blank', rel: 'noopener',
                 uid: 'M29-B13', uidLabel: '개인정보처리방침',
                 style: { fontSize: '13px', fontWeight: '700' } })
      ]));
      if (mode === 'lost') {
        body.appendChild(h('div.muted', { style: { marginTop: '10px' },
          text: '가입할 때 적어 둔 코드입니다. 되찾으면 다른 기기는 모두 로그아웃되고, ' +
                '코드는 새것으로 바뀝니다. 코드까지 잃었다면 서버 주인에게 말해야 합니다.' }));
      } else {
        body.appendChild(h('div.muted', { style: { marginTop: '10px' },
          text: mode === 'up'
            ? '가입하면 복구 코드를 한 번 보여줍니다. 비밀번호를 잊었을 때 돌아올 유일한 길이니 꼭 적어 두세요 — 이 서버는 메일을 보내지 않습니다.'
            : '비밀번호를 잊었다면 위의 “비밀번호 잊음” 으로 가세요. 가입할 때 받은 복구 코드가 필요합니다.' }));
      }
    }

    function field(label, input) {
      return h('div.field', { style: { marginBottom: '10px' } },
        [h('div.field__label', { text: label }), input]);
    }
    function chip(label, key, uid) {
      return h('button.chip' + (key === mode ? '.is-on' : ''), {
        text: label, uid: uid, uidLabel: label,
        onClick: function () { mode = key; consent = false; draw(); } });
    }
    function fail(t) { msg.textContent = t; msg.style.display = ''; busy = false; }

    draw();
    UI.openModal({
      uid: 'M29', title: '계정',
      sub: '이 앱의 서버에서 직접 관리합니다',
      body: body,
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '계속', kind: 'primary', onClick: function (close) {
            if (busy) return true;
            var S = global.MB_SYNC;
            if (!S || !S.status().configured) { fail('서버 주소가 설정되지 않았습니다'); return true; }
            var h1 = (handle.value || '').trim().toLowerCase();
            var p1 = pw.value || '';
            if (!h1) { fail('아이디를 넣어주세요'); return true; }
            if (mode === 'lost' && !(rcode.value || '').trim()) {
              fail('복구 코드를 넣어주세요'); return true;
            }
            if (p1.length < 8) {
              fail((mode === 'lost' ? '새 ' : '') + '비밀번호는 8자 이상이어야 합니다'); return true;
            }
            if (mode !== 'in' && p1 !== (pw2.value || '')) { fail('비밀번호가 서로 다릅니다'); return true; }
            if (mode === 'up' && !consent) {
              fail('몸에 대한 숫자를 올리는 것에 동의해야 계정을 만들 수 있습니다');
              return true;
            }

            busy = true; msg.textContent = '확인 중...'; msg.style.display = '';
            var work = mode === 'up'
              ? S.signUp({ handle: h1, password: p1,
                           displayName: (name.value || '').trim() || h1,
                           pairSecret: pair ? (pair.value || '').trim() : '',
                           healthConsent: consent })
              : (mode === 'lost'
                  ? S.recover({ handle: h1, code: rcode.value, password: p1 })
                  : S.signIn({ handle: h1, password: p1 }));

            work.then(function (r) {
              global.MB_STORE.publishWeekly();
              close();
              /* 가입과 되찾기는 코드를 새로 줍니다. 로그인 토스트로 덮어
                 버리면 그 한 번을 놓칩니다 — 코드 화면을 먼저 띄우고,
                 그걸 닫을 때 화면을 새로 그립니다. */
              if (r.recoveryCode) {
                M.recoveryCode(r.recoveryCode, {
                  fresh: mode !== 'up',
                  onDone: function () {
                    global.MB_UID.toast(r.user.displayName + '으로 로그인했습니다');
                    if (onDone) onDone();
                  }
                });
                return;
              }
              global.MB_UID.toast(r.user.displayName + '으로 로그인했습니다');
              if (onDone) onDone();
            }).catch(function (e) { fail(e.message); });
            return true;
          } }
      ]
    });
  };

  /* M30 친구 추가 */
  M.addFriend = function (onDone) {
    var input, msg;
    UI.openModal({
      uid: 'M30', title: '친구 추가',
      sub: '상대에게 받은 8자리 코드를 넣어주세요',
      body: [
        input = h('input.input', { placeholder: 'ABCD2345', maxlength: '8',
          style: { fontFamily: 'ui-monospace, monospace', fontSize: '18px',
                   letterSpacing: '.12em', textAlign: 'center' } }),
        msg = h('div.field__err', { style: { display: 'none' } }),
        h('div.muted', { style: { marginTop: '10px' },
          text: '전화번호나 이메일로는 찾을 수 없습니다. 코드를 직접 알려준 사람만 추가됩니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '요청 보내기', kind: 'primary', onClick: function (close) {
            var code = (input.value || '').trim().toUpperCase();
            if (code.length !== 8) {
              msg.textContent = '8자리 코드를 넣어주세요'; msg.style.display = ''; return true;
            }
            var S = global.MB_SYNC;
            /* 서버에 로그인돼 있으면 서버에 묻습니다. 초대 코드는 상대 것이라
               내 기기에는 없습니다 — 로컬에서 찾으면 언제나 "없는 코드"가 됩니다. */
            if (S && S.status().signedIn) {
              msg.textContent = '확인 중...'; msg.style.display = '';
              S.sendRequest(code).then(function () {
                global.MB_UID.toast('요청을 보냈습니다');
                if (onDone) onDone();
                close();
              }).catch(function (e) {
                msg.textContent = e.message; msg.style.display = '';
              });
              return true;   // 답이 올 때까지 모달을 열어 둡니다
            }
            var r = global.MB_BACKEND.sendRequest(code);
            if (!r.ok) { msg.textContent = r.reason; msg.style.display = ''; return true; }
            global.MB_UID.toast(r.status === 'accepted' ? '친구가 되었습니다' : '요청을 보냈습니다');
            if (onDone) onDone();
          } }
      ]
    });
  };

  /* M31 공유 전부 끄기 */
  M.stopSharing = function (friend, onConfirm) {
    UI.openModal({
      uid: 'M31', title: '공유를 모두 끌까요?',
      body: h('div', { text: friend.displayName + '님 화면에서 사라집니다. 친구 관계는 그대로입니다.' }),
      actions: [{ label: '취소', kind: 'ghost' },
                { label: '모두 끄기', kind: 'danger', onClick: onConfirm }]
    });
  };

  /* M26 스캔 값 확인 — 물리적으로 이상한 입력 */
  M.confirmScan = function (bad, onConfirm) {
    UI.openModal({
      uid: 'M26', title: '값을 한 번만 확인해 주세요',
      body: [
        h('div', { text: '아래 값이 보통 범위를 벗어났습니다. 결과지와 다르면 고쳐 주세요.' }),
        h('div', { style: { marginTop: '10px' } }, bad.reasons.map(function (r) {
          return h('div.note.note--warn', { style: { marginBottom: '6px' }, text: r });
        })),
        h('div.muted', { style: { marginTop: '8px' },
          text: '정말 이 값이 맞다면 그대로 저장해도 됩니다. 다만 이 값으로 만든 계획은 믿기 어렵습니다.' })
      ],
      actions: [
        { label: '고치러 가기', kind: 'ghost' },
        { label: '이대로 저장', kind: 'danger', onClick: onConfirm }
      ]
    });
  };

  /* M32 계정 삭제 */
  /* M52 — 모든 기기에서 로그아웃
   *
   * 폰을 잃어버렸거나 남의 컴퓨터에서 로그인한 채 나온 경우에 쓰는
   * 유일한 수단입니다. 서버는 이 기능을 그렇게 적어 뒀는데(db.js
   * signOutEverywhere) 화면에 누를 곳이 없었습니다.
   *
   * 이 기기도 같이 끊깁니다 — 서버가 세션을 전부 지우므로 지금 들고
   * 있는 토큰도 죽습니다. 그걸 안 치우면 화면은 로그인한 것처럼 보이는데
   * 모든 요청이 401 로 떨어집니다. 그래서 여기서 먼저 말해 둡니다.
   */
  M.signOutEverywhere = function (onDone) {
    var msg, busy = false;
    UI.openModal({
      uid: 'M52', title: '모든 기기에서 로그아웃할까요?',
      body: [
        h('div.note.note--warn', { text: '이 기기를 포함해 로그인된 모든 기기가 끊깁니다. ' +
          '다시 쓰려면 비밀번호로 다시 로그인하면 됩니다.' }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '폰을 잃어버렸거나 남의 컴퓨터에서 로그인한 채 나왔을 때 쓰세요. ' +
                '계정과 기록은 그대로 남습니다.' }),
        msg = h('div.field__err', { style: { display: 'none' } })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '전부 로그아웃', kind: 'danger', onClick: function (close) {
            if (busy) return true;
            var SY = global.MB_SYNC;
            if (!SY || !SY.status().signedIn) { close(); return; }
            busy = true; msg.style.display = 'none';
            SY.signOutEverywhere().then(function () {
              /* 서버 세션이 전부 지워졌으니 이 기기 토큰도 이미 죽었습니다.
                 signOut() 은 서버에 한 번 더 말을 걸지만 실패해도 로컬은
                 비웁니다 — 우리가 원하는 게 그겁니다. */
              return SY.signOut().catch(function () {});
            }).then(function () {
              global.MB_UID.toast('모든 기기에서 로그아웃했습니다');
              close();
              if (onDone) onDone();
            }).catch(function (e) {
              busy = false;
              msg.textContent = '로그아웃하지 못했습니다 — ' + (e && e.message || '연결 실패') +
                '. 다른 기기는 그대로 로그인돼 있습니다.';
              msg.style.display = '';
            });
            return true;
          } }
      ]
    });
  };

  M.deleteAccount = function (onDone) {
    var input, msg, busy = false;
    UI.openModal({
      uid: 'M32', title: '계정을 삭제할까요?',
      body: [
        h('div.note.note--bad', { text: '서버에서 계정 · 친구 관계 · 공유 설정 · 주간 기록 · ' +
          '프로필 사진이 모두 지워집니다. 되돌릴 수 없습니다.' }),
        h('p', { text: '확인을 위해 "삭제" 라고 입력해 주세요.' }),
        input = h('input.input', { placeholder: '삭제' }),
        msg = h('div.field__err', { style: { display: 'none' } }),
        h('div.muted', { style: { marginTop: '8px' },
          text: '이 기기에 저장된 측정 기록은 지워지지 않습니다. ' +
                '받아 둔 친구 목록 · 프로필 사진 · 친구 소식은 같이 지웁니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '삭제', kind: 'danger', onClick: function (close) {
            if ((input.value || '').trim() !== '삭제') {
              global.MB_UID.toast('"삭제" 라고 정확히 입력해 주세요');
              return true;
            }
            if (busy) return true;
            busy = true;
            msg.style.display = 'none';

            /* 서버에 먼저 말합니다.
             *
             * 예전엔 이 버튼이 로컬 거울만 비우고 "계정을 삭제했습니다"
             * 라고 했습니다. MB_SYNC.deleteAccount() 는 만들어져 있는데
             * 부르는 곳이 한 군데도 없었습니다 — 서버에는 계정도, 친구
             * 관계도, 주간 기록도, 프로필 사진도 그대로 남아 있었고,
             * 친구 화면에서는 아무 일도 안 일어났습니다. 지웠다고 믿은
             * 사람만 사라진 셈입니다.
             *
             * 그래서 실패하면 로컬도 안 건드립니다. 서버에 남아 있는데
             * 이 기기에서만 지우면, 지운 줄 아는 사람이 계속 친구
             * 화면에 떠 있게 됩니다 — 제일 나쁜 결과입니다. */
            var SY = global.MB_SYNC;
            var onServer = SY && SY.status().signedIn;
            var step = onServer ? SY.deleteAccount() : Promise.resolve({ ok: true });

            step.then(function () {
              global.MB_BACKEND.deleteAccount();
              if (global.MB_NEWS) { try { global.MB_NEWS.reset(); } catch (e) {} }
              global.MB_UID.toast('계정을 삭제했습니다');
              close();
              if (onDone) onDone();
            }).catch(function (e) {
              busy = false;
              msg.textContent = '서버에서 지우지 못했습니다 — ' +
                (e && e.message || '연결 실패') + '. 계정은 그대로 있습니다. ' +
                '인터넷이 되는 곳에서 다시 시도해 주세요.';
              msg.style.display = '';
            });
            return true;   // 결과가 올 때까지 열어 둡니다
          } }
      ]
    });
  };

  /* M37 친구 끊기 */
  /* ======================================================================
   * M27 — 이 친구에게 보낼 것
   *
   * 예전에는 P17 이라는 화면이었습니다. 화면이면 노출 바는 위에, 토글은
   * 2.3화면 아래라 자기 행동이 만든 상태 변화를 볼 수 없었습니다.
   * 모달이면 루프가 한 자리에서 닫힙니다.
   * ==================================================================== */
  M.shareWith = function (friend, onDone) {
    var BE = global.MB_BACKEND;
    var me = BE.currentUser();
    if (!me) return;
    var body = h('div');

    function draw() {
      body.textContent = '';
      var cur = BE.getShare(me.id, friend.id);
      var snap = global.MB_STORE.weeklySnapshot();
      var trendOn = cur.weightTrend || cur.smmTrend || cur.bfmTrend;

      BE.SHARE_FIELDS.forEach(function (fl, i) {
        var on = !!cur[fl.key];
        // absolute 는 변화량이 하나라도 켜져 있어야 의미가 있습니다.
        // 백엔드가 이미 그렇게 강제하는데, 지금까지는 조용히 되돌리면서 ok:true 를
        // 줘서 눌러도 아무 일이 없는 버튼이었습니다. 규칙을 약하게 만드는 게 아니라
        // 보이게 만듭니다.
        var locked = fl.key === 'absolute' && !trendOn;
        var uid = 'M27-F' + ('0' + (i + 1)).slice(-2);
        var row = h('div.radio-card' + (on ? '.is-on' : ''), {
          uid: uid, uidLabel: fl.label,
          style: locked ? { opacity: '.5', cursor: 'not-allowed' } : { cursor: 'pointer' },
          'aria-disabled': locked ? 'true' : null,
          onClick: function () {
            if (locked) {
              global.MB_UID.toast('체중·골격근·체지방 중 하나를 먼저 켜야 합니다');
              return;
            }
            var before = BE.getShare(me.id, friend.id);
            BE.setShare(friend.id, keyed(fl.key, !on));
            var after = BE.getShare(me.id, friend.id);
            // absolute 연쇄 해제를 말해 줍니다. 마지막 변화량을 끄면 실제 수치도
            // 같이 꺼지는데, 그걸 안 말하면 이 화면이 진실을 말한다는 계약이 깨집니다.
            if (before.absolute && !after.absolute && fl.key !== 'absolute') {
              global.MB_UID.toast('실제 수치까지도 함께 꺼졌습니다');
            }
            draw();
          }
        }, [
          h('div', { style: { display: 'flex', justifyContent: 'space-between', gap: '8px' } }, [
            h('div.radio-card__t', { text: (on ? '✓ ' : '· ') + fl.label }),
            h('div.card__sub', { text: locked ? '먼저 변화량을 켜세요' : valueOf(fl.key, cur, snap) })
          ]),
          h('div.radio-card__d', { text: DESC[fl.key] || '' })
        ]);
        body.appendChild(row);
      });

      body.appendChild(h('div.note', { style: { marginTop: '10px' },
        text: '끄면 지금까지 보여준 기록까지 상대 화면에서 사라집니다. 켜면 과거 기록도 함께 나타납니다. ' +
              '인터넷이 없으면 연결된 다음에 반영됩니다.' }));
    }

    function keyed(k, v) { var o = {}; o[k] = v; return o; }

    var DESC = {
      weightTrend: '마지막 인바디와 그 앞 인바디 사이의 변화',
      smmTrend: '마지막 인바디와 그 앞 인바디 사이의 변화',
      bfmTrend: '마지막 인바디와 그 앞 인바디 사이의 변화',
      planProgress: '목표까지 얼마나 왔는지 (%)',
      streak: '이번 주에 기록을 했는지 여부 (주간 체크인이든 운동 체크든)',
      /* 무엇이 안 나가는지까지 적습니다. "일정을 공유한다"만 읽으면
         무슨 요일에 무슨 운동을 했는지까지 나가는 줄로 읽힙니다. */
      schedule: '숫자 네 개 — 하기로 한 날 · 지킨 날 · 지나갔는데 체크가 없는 날 · ' +
                '아직 남은 날. 무슨 요일에 무슨 운동인지는 안 나갑니다.',
      absolute: '변화량 대신 실제 숫자로. 켠 항목에만 붙습니다.'
    };

    function valueOf(key, cur, snap) {
      if (key === 'streak') return snap.checkedIn ? '이번 주 기록함' : '이번 주 아직';
      if (key === 'schedule') {
        return snap.plannedDays == null ? '이번 주 정한 날 없음'
          : '계획 ' + snap.plannedDays + '일 · 지킴 ' + snap.keptDays + '일';
      }
      if (key === 'absolute') return cur.absolute ? '켜짐' : '꺼짐';
      var map = { weightTrend: 'dWeightKg', smmTrend: 'dSmmKg', bfmTrend: 'dBfmKg' };
      if (key === 'planProgress') return snap.progressPct == null ? '아직 값 없음' : snap.progressPct + '%';
      var v = snap[map[key]];
      return v == null ? '아직 값 없음' : UI.sign(v) + 'kg';
    }

    draw();
    UI.openModal({
      uid: 'M27', title: friend.displayName + '님에게 보낼 것',
      sub: friend.displayName + '님에게만 적용됩니다',
      body: body,
      actions: [
        { label: '전부 끄기', kind: 'danger', uidLabel: '전부 끄기', close: false, onClick: function () {
            M.stopSharing(friend, function () {
              var off = {};
              global.MB_BACKEND.SHARE_FIELDS.forEach(function (x) { off[x.key] = false; });
              global.MB_BACKEND.setShare(friend.id, off);
              global.MB_UID.toast(global.MB_SYNC
                ? global.MB_SYNC.deliveryNote(friend.displayName)
                : friend.displayName + '님 화면에서 사라졌습니다');
              draw();
            });
            return true;   // M27 은 열어 둡니다 — 확인 모달이 그 위에 뜹니다
          } },
        { label: '완료', kind: 'primary', uidLabel: '완료' }
      ],
      onClose: function () { if (onDone) onDone(); }
    });
  };

  /* ======================================================================
   * M28 — 항목 하나가 지금 누구에게 나가나
   * P15 노출 바의 칩에서 열립니다. 자기 노출 상태를 탭 루트에서 한 탭 거리에.
   * ==================================================================== */
  M.whoSees = function (fieldKey, onDone) {
    var BE = global.MB_BACKEND;
    var me = BE.currentUser();
    if (!me) return;
    var fl = BE.SHARE_FIELDS.filter(function (x) { return x.key === fieldKey; })[0];
    if (!fl) return;
    var body = h('div');

    function draw() {
      body.textContent = '';
      var list = BE.listFriends().accepted.filter(function (r) {
        return r.iShare.settings[fieldKey];
      });
      if (!list.length) {
        body.appendChild(h('div.empty', [h('div.empty__t', { text: '지금 이 항목을 보는 사람이 없습니다' })]));
        return;
      }
      list.forEach(function (r, i) {
        body.appendChild(h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px',
          padding: '8px 0', borderBottom: '1px solid var(--border)' } }, [
          h('div', { style: { flex: '1', fontWeight: '700' }, text: r.displayName }),
          h('button.btn.btn--sm', { text: '끄기',
            uid: 'M28-B10#' + (i + 1), uidLabel: '끄기 ' + (i + 1),
            onClick: function () {
              var o = {}; o[fieldKey] = false;
              BE.setShare(r.id, o);
              global.MB_UID.toast(global.MB_SYNC
                ? global.MB_SYNC.deliveryNote(r.displayName)
                : r.displayName + '님 화면에서 사라졌습니다');
              draw();
            } })
        ]));
      });
      body.appendChild(h('div.muted', { style: { marginTop: '8px' },
        text: '사람별로 정하려면 친구를 열어 주세요.' }));
    }

    draw();
    UI.openModal({
      uid: 'M28', title: fl.label + ' — 지금 보는 사람',
      body: body,
      actions: [
        { label: '이 항목 전부 끄기', kind: 'danger', uidLabel: '이 항목 전부 끄기', close: false,
          onClick: function () {
            var targets = BE.listFriends().accepted.filter(function (r) {
              return r.iShare.settings[fieldKey];
            });
            if (!targets.length) return true;
            UI.openModal({
              uid: 'M39', title: fl.label + '을 모두 끌까요?',
              body: h('div', { text: targets.map(function (r) { return r.displayName; }).join('·') +
                '님 화면에서 사라집니다. 지금까지 보여준 기록도 함께 사라집니다.' }),
              actions: [{ label: '취소', kind: 'ghost' },
                        { label: '모두 끄기', kind: 'danger', onClick: function () {
                            targets.forEach(function (r) {
                              var o = {}; o[fieldKey] = false; BE.setShare(r.id, o);
                            });
                            global.MB_UID.toast(fl.label + '을 전부 껐습니다');
                            draw();
                          } }]
            });
            return true;   // M28 은 열어 둡니다
          } },
        { label: '닫기', uidLabel: '닫기' }
      ],
      onClose: function () { if (onDone) onDone(); }
    });
  };

  M.removeFriend = function (friend, onConfirm) {
    UI.openModal({
      uid: 'M37', title: friend.displayName + '님과 친구를 끊을까요?',
      body: h('div', { text: '서로 공유하던 내용이 모두 사라집니다. 다시 친구가 되려면 코드부터 다시 시작합니다.' }),
      actions: [{ label: '취소', kind: 'ghost' },
                { label: '끊기', kind: 'danger', onClick: onConfirm }]
    });
  };

  /* M40 양 고르기 — 사진보다 이게 정확합니다 */
  M.portion = function (food, onPick) {
    var F = global.MB_FOOD;
    var mult = 1;
    var info, custom;
    function refresh() {
      var sc = F.scaled(food, mult);
      info.textContent = '무게 ' + sc.g + 'g · ' + sc.kcal + 'kcal · 단백질 ' + sc.p + 'g · 탄수 ' +
                         sc.c + 'g · 지방 ' + sc.f + 'g';
    }
    var chips = h('div.chips', F.PORTIONS.map(function (p2) {
      var b = h('button.chip' + (p2.mult === 1 ? '.is-on' : ''), { text: p2.label,
        onClick: function () {
          mult = p2.mult; custom.value = '';
          chips.querySelectorAll('.chip').forEach(function (x) { x.classList.remove('is-on'); });
          b.classList.add('is-on');
          refresh();
        } });
      return b;
    }));
    var conf = F.CONF_LABEL[food.conf] || F.CONF_LABEL.mid;
    var dlg = UI.openModal({
      uid: 'M40', title: food.name,
      // "기준 1개 (50g)" 은 50g 이 단백질처럼 읽혔다 — 영양 정보 바로 위에 붙어 있어서다
      sub: '1인분 = ' + food.unit + ', 무게 ' + food.g + 'g',
      body: [
        h('div.field__label', { text: '얼마나 드셨나요' }),
        chips,
        h('div.field', { style: { marginTop: '10px' } }, [
          h('div.field__label', { text: '직접 입력 (배수)' }),
          custom = h('input.input.input--num', { type: 'number', step: '0.1', min: '0.1',
            placeholder: '예: 1.3',
            onInput: function () {
              var v = parseFloat(custom.value);
              if (v > 0) {
                mult = v;
                chips.querySelectorAll('.chip').forEach(function (x) { x.classList.remove('is-on'); });
                refresh();
              }
            } })
        ]),
        info = h('div.note', { style: { marginTop: '10px' } }),
        h('div.muted', { style: { marginTop: '8px' },
          text: conf.text + ' — ' + conf.note }),
        h('button.btn.btn--ghost.btn--sm', {
          text: (S.isFavorite(food.name) ? '★ 즐겨찾기 해제' : '☆ 즐겨찾기'),
          style: { marginTop: '8px' },
          onClick: function (ev) {
            var on = S.toggleFavorite(food.name);
            ev.target.textContent = on ? '★ 즐겨찾기 해제' : '☆ 즐겨찾기';
          } })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '추가', kind: 'primary', onClick: function () { onPick(F.scaled(food, mult)); } }
      ]
    });
    refresh();
    return dlg;
  };

  /* M41 직접 입력 — 목록에 없는 음식 */
  M.customFood = function (onAdd) {
    var name, kcal, p, c, f;
    UI.openModal({
      uid: 'M41', title: '직접 입력',
      sub: '포장지 라벨을 보고 적는 게 가장 정확합니다',
      body: [
        h('div.field', [h('div.field__label', { text: '이름' }),
          name = h('input.input', { placeholder: '예: 회사 구내식당 점심' })]),
        h('div', { style: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '8px' } }, [
          h('div.field', [h('div.field__label', { text: '칼로리 (kcal)' }),
            kcal = h('input.input.input--num', { type: 'number', min: '0' })]),
          h('div.field', [h('div.field__label', { text: '단백질 (g)' }),
            p = h('input.input.input--num', { type: 'number', min: '0' })]),
          h('div.field', [h('div.field__label', { text: '탄수화물 (g)' }),
            c = h('input.input.input--num', { type: 'number', min: '0' })]),
          h('div.field', [h('div.field__label', { text: '지방 (g)' }),
            f = h('input.input.input--num', { type: 'number', min: '0' })])
        ]),
        h('div.muted', { text: '칼로리만 알아도 괜찮습니다. 비워두면 0으로 들어갑니다.' })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '추가', kind: 'primary', onClick: function () {
            var n = (name.value || '').trim();
            if (!n) { global.MB_UID.toast('이름을 적어주세요'); return true; }
            onAdd({ name: n, unit: '직접', mult: 1, g: 0,
                    kcal: Math.round(+kcal.value || 0), p: +p.value || 0,
                    c: +c.value || 0, f: +f.value || 0, conf: 'mid', custom: true });
          } }
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

  /* M45 사진 크게 보기 — 결과지 숫자는 작습니다. 폰 화면에서 37.9 와
     97.9 를 가르려면 확대가 필요합니다. 브라우저 기본 확대는 모달 안에서
     잘 안 먹어서, 눌러서 2.5배로 키우고 드래그로 훑게 했습니다. */
  M.photoZoom = function (dataUrl) {
    if (!dataUrl) return;
    var scale = 1;
    var box = h('div', {
      style: { overflow: 'auto', maxHeight: '68vh', borderRadius: '10px',
               background: 'var(--bg-2)', WebkitOverflowScrolling: 'touch' }
    });
    var img = h('img', {
      src: dataUrl, alt: '올린 결과지',
      style: { width: '100%', display: 'block', transformOrigin: '0 0', cursor: 'zoom-in' },
      onClick: function () {
        scale = scale === 1 ? 2.5 : 1;
        img.style.width = (scale * 100) + '%';
        img.style.cursor = scale === 1 ? 'zoom-in' : 'zoom-out';
      }
    });
    box.appendChild(img);
    UI.openModal({
      uid: 'M45', title: '결과지',
      sub: '눌러서 확대 · 끌어서 이동',
      body: [box],
      actions: [{ label: '닫기', kind: 'primary' }]
    });
  };

  /* M46 자동 판독 켜기 — 건강 데이터를 기기 밖으로 내보내는 동의입니다.
     무엇이 나가고, 어디로 가고, 무엇이 안 나가는지를 적습니다. "개인정보
     처리방침에 동의" 같은 말로 뭉개지 않습니다 — 그런 문장은 아무도 안
     읽고, 안 읽힌 동의는 동의가 아닙니다. */
  M.enableOcr = function (onConfirm) {
    var st = global.MB_SYNC ? global.MB_SYNC.status() : {};
    UI.openModal({
      uid: 'M46', title: '사진을 서버로 보냅니다',
      sub: st.baseUrl || '내 서버',
      body: [
        h('div', { text: '자동 판독을 켜면, 판독 버튼을 누를 때마다 결과지 사진이 이 서버로 올라갑니다.' }),
        h('ul', { style: { paddingLeft: '18px', margin: '10px 0' } }, [
          h('li', { text: '올라가는 것: 결과지 사진 한 장 (줄여서 1MB 이하)' }),
          /* 이 줄이 빠져 있었습니다. 서버가 직접 읽는 것처럼 읽혔는데,
             실제로는 외부 판독 서비스로 한 번 더 보냅니다. 사진이
             어디까지 가는지 다 말하지 않으면 동의가 아닙니다. */
          h('li', { text: '그 다음: 내 서버가 사진을 외부 판독 서비스(Anthropic)로 한 번 더 보냅니다. ' +
                          '숫자를 읽는 것은 그쪽입니다.' }),
          h('li', { text: '결과지에는 보통 이름 · 나이 · 성별 · 측정일시가 함께 인쇄돼 있습니다. ' +
                          '사진에 찍혀 있으면 그것도 같이 갑니다 — 가리고 찍으셔도 됩니다.' }),
          h('li', { text: '안 올라가는 것: 누르지 않은 사진. 자동으로 올라가는 사진은 없습니다.' })
        ]),
        /* 사진은 나라 밖으로 나갑니다. 개인정보보호법 제28조의8 이 국외
           이전에 요구하는 다섯 가지를 그대로 적습니다 — 항목 · 국가와
           시기와 방법 · 받는 사람과 연락처 · 목적과 보유기간 · 거부 방법.
           특히 "이 서버는 사진을 저장하지 않는다" 는 보유기간 항목에
           딱 맞는 가장 유리한 사실인데 빠져 있었습니다. */
        h('div.note.note--warn', { style: { marginTop: '4px' } }, [
          h('b', { text: '이 사진은 나라 밖으로 나갑니다' }),
          h('ul', { style: { paddingLeft: '18px', margin: '8px 0 0' } }, [
            h('li', { text: '이전되는 항목 — 결과지 사진 한 장 (찍혀 있으면 이름 · 나이 · 성별 · 측정일시 포함)' }),
            h('li', { text: '가는 곳 · 시기 · 방법 — 미국, 판독 버튼을 누를 때마다, HTTPS 로' }),
            h('li', { text: '받는 곳 — Anthropic PBC · privacy@anthropic.com' }),
            h('li', { text: '목적과 보유 — 결과지 숫자 판독에만. 내 서버는 사진을 디스크에 저장하지 않고 ' +
                            '메모리에서 중계만 하고 버립니다. 받는 쪽 보유 기간은 그쪽 약관을 따릅니다.' }),
            h('li', { text: '거부 — 안 켜면 한 장도 안 나갑니다. 켠 뒤에도 설정에서 끄면 그때부터 안 나갑니다. ' +
                            '거부해도 앱은 그대로 씁니다 — 숫자를 직접 입력하면 됩니다.' })
          ])
        ]),
        h('div.note', {
          text: '돌려받은 숫자는 그대로 저장되지 않습니다. 결과지 안에서 검산이 맞는지 따진 뒤, ' +
                '검수 화면에서 직접 보고 확정합니다. 지금처럼 직접 입력하는 길도 그대로 남습니다.' }),
        h('div', { style: { marginTop: '8px' } }, [
          h('a', { text: '개인정보처리방침 6번 — 결과지 사진과 자동 판독',
                   href: './privacy.html', target: '_blank', rel: 'noopener',
                   uid: 'M46-B10', uidLabel: '개인정보처리방침',
                   style: { fontSize: '13px', fontWeight: '700' } })
        ])
      ],
      actions: [
        { label: '안 켤래요', kind: 'ghost' },
        { label: '알겠습니다, 켤게요', kind: 'primary',
          onClick: function () { if (onConfirm) onConfirm(); } }
      ]
    });
  };

  /* M47 "모두 지우기" 공통 확인.
     되돌릴 수 없는 삭제는 버튼 한 번으로 일어나면 안 됩니다. 특히 손가락이
     미끄러지기 쉬운 폰에서요. 전체 초기화(M18)는 "초기화" 를 타이핑하게
     하는데, 메모·사진은 그 정도까지는 아니라 한 번 물어보는 것으로 합니다.
     지울 것이 몇 개인지 반드시 같이 보여 줍니다 — 숫자가 없으면 사용자는
     자기가 무엇을 잃는지 모른 채 누릅니다. */
  M.confirmClear = function (o) {
    UI.openModal({
      uid: 'M47', title: o.title,
      body: [
        h('div.note.note--bad', { text: o.warn }),
        o.keep ? h('div.muted', { style: { marginTop: '8px' }, text: o.keep }) : null
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: o.confirmLabel || '지우기', kind: 'danger',
          onClick: function () { o.onConfirm(); } }
      ]
    });
  };

  /* M53 저장된 기록을 못 읽었습니다.
   *
   * 측정 기록은 서버로 안 올라가는 **유일본**입니다. 못 읽었을 때
   * 조용히 빈 상태로 시작하면, 앱이 온보딩을 띄우고 사용자가 한 걸음
   * 넘어가는 순간 첫 저장이 깨진 원본을 덮어씁니다 — 손으로 복구할
   * 재료까지 그때 사라집니다.
   *
   * 그래서 store 가 원본을 옆으로 치워 두고, 여기서 그 사실을 말합니다.
   * 사람이 할 수 있는 일이 실제로 있습니다: 브라우저 개발자 도구로
   * 그 칸을 열어 숫자를 옮겨 적는 것. 어렵지만 없는 것보다 낫습니다.
   */
  M.loadBroken = function (p) {
    UI.openModal({
      uid: 'M53', title: '저장된 기록을 읽지 못했습니다',
      sub: p && p.kept ? '원본은 지우지 않고 옆에 보관해 뒀습니다' : null,
      body: [
        h('div.note.note--bad', {
          text: '이 기기에 저장돼 있던 기록을 읽지 못했습니다 — ' +
                ((p && p.why) || '이유를 알 수 없습니다') + '.' }),
        p && p.kept
          ? h('div', { style: { marginTop: '10px' } }, [
              h('div.card__sub', { text: '원본을 여기 보관해 뒀습니다' }),
              h('div', { style: { fontFamily: 'ui-monospace, monospace', fontSize: '12px',
                                  wordBreak: 'break-all', marginTop: '4px' },
                         text: p.kept }),
              h('div.muted', { style: { marginTop: '6px' },
                text: '브라우저 개발자 도구 → 저장소(localStorage)에서 이 이름을 열면 ' +
                      '원래 내용이 그대로 있습니다. 숫자를 옮겨 적을 수 있습니다.' })
            ])
          : h('div.note.note--warn', { style: { marginTop: '10px' },
              text: '자리가 없어서 원본을 보관하지도 못했습니다. ' +
                    '이 기기의 저장 공간을 비운 뒤 앱을 다시 열어 보세요 — ' +
                    '그 전에는 아무것도 저장하지 마세요.' }),
        h('div.muted', { style: { marginTop: '10px' },
          text: '지금부터 쓰기 시작하면 빈 상태로 시작합니다. 다른 기기에 ' +
                '내보내기(JSON) 파일이 있으면 설정 → 가져오기로 되살릴 수 있습니다.' })
      ],
      actions: [
        { label: '가져오기 열기', onClick: function () { global.MB_APP.go('P12'); } },
        { label: '알겠습니다', kind: 'primary' }
      ]
    });
  };

  /* M48 저장 실패 — 기기에 자리가 없습니다.
     여기서 제일 중요한 것은 사용자가 방금 입력한 숫자를 잃지 않는
     것입니다. 저장은 실패했지만 화면의 값은 아직 살아 있으니, 그
     값을 눈에 보이게 적어 줍니다. 적어 두고 자리를 만든 뒤 다시
     넣을 수 있게. */
  M.saveFailed = function (v) {
    var rows = [['체중', v.weightKg, 'kg'], ['골격근량', v.smmKg, 'kg'], ['체지방량', v.bfmKg, 'kg']]
      .filter(function (r) { return r[1] != null; })
      .map(function (r) { return r[0] + ' ' + r[1] + r[2]; }).join(' · ');
    UI.openModal({
      uid: 'M48', title: '저장하지 못했습니다',
      sub: '이 기기에 자리가 없습니다',
      body: [
        h('div.note.note--bad', {
          text: '측정이 저장되지 않았습니다. 사진을 먼저 지워 자리를 만들어 봤지만 그래도 모자랍니다.' }),
        rows ? h('div', { style: { marginTop: '10px' } }, [
          h('div.card__sub', { text: '방금 넣은 값 — 어딘가에 적어 두세요' }),
          h('div.num', { style: { fontSize: '16px', fontWeight: '700', marginTop: '4px' }, text: rows }),
          v.measuredAt ? h('div.muted', { style: { marginTop: '2px' },
            text: '측정일 ' + String(v.measuredAt).slice(0, 10) }) : null
        ]) : null,
        h('div.muted', { style: { marginTop: '10px' },
          text: '브라우저 설정에서 이 사이트의 저장 공간을 늘리거나, ' +
                '설정 → 결과지 사진에서 사진을 지우면 자리가 납니다.' })
      ],
      actions: [
        { label: '설정 열기', onClick: function () { global.MB_APP.go('P12'); } },
        { label: '알겠습니다', kind: 'primary' }
      ]
    });
  };

  /* ======================================================================
   * M49 복구 코드 — 한 번만 보여줍니다
   *
   * 이 서버는 메일을 보내지 않습니다. 그래서 비밀번호를 잊었을 때 돌아올
   * 길은 이 코드 하나뿐이고, 서버에는 해시만 남으므로 우리도 다시 꺼내
   * 줄 수 없습니다. 화면이 그 사실을 흐리게 말하면 사용자는 "나중에 어디서
   * 볼 수 있겠지" 하고 넘깁니다 — 그리고 그 나중은 없습니다.
   *
   * 그래서 여기만 규칙을 달리 합니다
   *   · ✕ 를 안 답니다. 실수로 닫아서 잃는 길을 없앱니다.
   *   · 바깥을 눌러도, Esc 를 눌러도 안 닫힙니다.
   *   · "적어 뒀습니다" 를 누르기 전에는 나가는 버튼이 안 눌립니다.
   *
   * 한 번 더 귀찮게 하는 값어치가 있는 자리입니다. 이걸 놓치면 계정을
   * 통째로 다시 만들어야 하고, 그러면 친구 관계와 주간 기록이 같이
   * 사라집니다.
   * ==================================================================== */
  M.recoveryCode = function (code, opts) {
    opts = opts || {};
    var wrote = false, done, hint;

    var codeEl = h('div', {
      text: code,
      style: { fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
               fontSize: '20px', fontWeight: '800', letterSpacing: '.08em',
               textAlign: 'center', padding: '14px 8px', marginTop: '4px',
               borderRadius: '10px', userSelect: 'all',
               background: 'color-mix(in srgb, currentColor 7%, transparent)' }
    });

    /* 클립보드가 막힌 브라우저(http 로 연 경우 등)가 있습니다.
       "복사됐습니다" 라고 거짓말하면 사용자는 붙여넣기만 믿고 코드를
       잃습니다 — 이 코드는 한 번만 보여주는 것이라 되찾을 데가 없습니다. */
    var copyBtn = h('button.btn.btn--sm', {
      text: '복사', uid: 'M49-B10', uidLabel: '복사',
      onClick: function () { UI.copyText(code, { el: codeEl }); }
    });

    var wroteBtn = h('button.chip', {
      text: '적어 뒀습니다', uid: 'M49-B11', uidLabel: '적어 뒀습니다',
      onClick: function () {
        wrote = !wrote;
        wroteBtn.className = 'chip' + (wrote ? ' is-on' : '');
        if (done) done.disabled = !wrote;
        if (hint) hint.style.display = wrote ? 'none' : '';
      }
    });

    /* 제목은 고정입니다. 번호 목록(docs/UID-REGISTRY.md)은 소스에서
       읽어 만드는데, 제목이 변수면 그 번호가 이름 없이 남습니다. */
    var m = UI.openModal({
      uid: 'M49', title: '복구 코드',
      sub: (opts.fresh ? '새 코드입니다 · ' : '') + '지금 한 번만 보여집니다',
      dismissable: false,
      closeButton: false,
      body: [
        h('div.note.note--warn', {
          text: '비밀번호를 잊었을 때 돌아올 수 있는 유일한 길입니다. ' +
                '서버에는 이 코드가 남지 않으니 우리도 다시 알려줄 수 없습니다.' }),
        codeEl,
        h('div.btn-row', { style: { marginTop: '8px' } }, [copyBtn, wroteBtn]),
        h('div.muted', { style: { marginTop: '12px' },
          text: '종이에 적어 지갑에 넣거나, 비밀번호 관리 앱에 저장해 두세요. ' +
                '스크린샷은 폰을 잃으면 같이 사라집니다.' }),
        hint = h('div.muted', { style: { marginTop: '6px' },
          text: '적어 뒀다고 눌러야 닫을 수 있습니다.' })
      ],
      actions: [
        { label: '다 적었습니다', kind: 'primary', uid: 'M49-B01', uidLabel: '다 적었습니다',
          onClick: function () {
            if (!wrote) return true;        // 모달을 닫지 않습니다
            if (opts.onDone) opts.onDone();
          } }
      ]
    });

    /* 버튼은 openModal 이 만듭니다. 그래서 돌려받은 el 안에서 찾습니다 —
       document 전체를 뒤지면 같은 번호의 옛 모달이 남아 있을 때 엉뚱한
       버튼을 잠급니다. */
    done = m.el.querySelector('[data-uid="M49-B01"]');
    if (done) done.disabled = true;
  };

  /* M50 복구 코드 새로 받기 — 코드를 잃어버렸을 때.
     비밀번호를 다시 묻습니다: 잠깐 열린 폰을 집어든 사람이 코드를
     뽑아 가면, 그 사람은 나중에 언제든 계정을 가져갈 수 있습니다. */
  M.newRecoveryCode = function (onDone) {
    var pw, msg, busy = false;
    UI.openModal({
      uid: 'M50', title: '복구 코드 새로 받기',
      sub: '옛 코드는 그 자리에서 못 쓰게 됩니다',
      body: [
        h('div.muted', { text: '적어 둔 코드를 잃어버렸다면 여기서 새로 받으세요. ' +
                               '본인인지 확인하려고 비밀번호를 한 번 더 묻습니다.' }),
        h('div.field', { style: { marginTop: '10px' } }, [
          h('div.field__label', { text: '비밀번호' }),
          pw = h('input.input', { uid: 'M50-F01', uidLabel: '비밀번호', type: 'password' })
        ]),
        msg = h('div.field__err', { style: { display: 'none' } })
      ],
      actions: [
        { label: '취소', kind: 'ghost' },
        { label: '새 코드 받기', kind: 'primary', onClick: function (close) {
            if (busy) return true;
            var S = global.MB_SYNC;
            if (!S || !S.status().signedIn) {
              msg.textContent = '로그인이 필요합니다'; msg.style.display = ''; return true;
            }
            if (!(pw.value || '')) {
              msg.textContent = '비밀번호를 넣어주세요'; msg.style.display = ''; return true;
            }
            busy = true; msg.textContent = '확인 중...'; msg.style.display = '';
            S.newRecoveryCode({ password: pw.value }).then(function (r) {
              close();
              M.recoveryCode(r.recoveryCode, { fresh: true, onDone: onDone });
            }).catch(function (e) {
              busy = false;
              msg.textContent = e.message; msg.style.display = '';
            });
            return true;
          } }
      ]
    });
  };

  global.MB_MODALS = M;
})(window);
