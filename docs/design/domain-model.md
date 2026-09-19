# Mybody — 도메인 모델 & 데이터 스키마 (v1, 프로토타입 단계)

> 범위: 단일 사용자(owner 전용), 정적 vanilla HTML/CSS/JS 프로토타입. 저장소는 `localStorage`.
> 모든 식별자는 `snake_case`, 엔티티명은 `PascalCase`, enum 값은 `SCREAMING_SNAKE`.
> 날짜는 `YYYY-MM-DD`(로컬), 시각 포함 시 ISO-8601 `YYYY-MM-DDTHH:mm:ss+09:00`.

---

## 0. 공통 규약

### 0.1 단위 규약

| 개념 | 단위 | 저장 정밀도 | 비고 |
|---|---|---|---|
| 체중 / 근육 / 지방 질량 | kg | 소수 1자리 | InBody 출력 정밀도와 동일 |
| 체수분 | L | 소수 1자리 | |
| 단백질 / 무기질 / 골무기질량 | kg | 소수 2자리 | |
| 비율(PBF, ECW/TBW, 준수율) | % 또는 0~1 | 필드명에 `_pct` = %, `_ratio` = 0~1 | 혼용 금지 |
| 신장 | cm (입력) / m (계산용 `height_m`) | cm 소수 1자리 | |
| 에너지 | kcal | 정수 | |
| 매크로 | g | 정수 | |
| 중량(바벨 등) | kg | 0.5 단위 | |
| 시간 | 분(`_min`) 또는 초(`_sec`) | 정수 | 필드명에 명시 |
| 내장지방레벨 VFL | level (정수 1~20) | 정수 | 단위 없음 |
| InBody 점수 | point (20~100) | 정수 | |

### 0.2 ID 규약

| 엔티티 | ID 포맷 | 예시 |
|---|---|---|
| InBodyScan | `scan_<YYYYMMDD>_<seq2>` | `scan_20260914_01` |
| Goal | `goal_<YYYYMMDD>_<seq2>` | `goal_20260919_01` |
| Plan | `plan_<goal_id 뒷부분>_<intensity>_<rev>` | `plan_20260919_01_MODERATE_r1` |
| ProgressLog | `log_<YYYYMMDD>` (하루 1건) | `log_20260921` |
| WeeklyCheckpoint | `ckpt_<goal_id>_w<week_index>` | `ckpt_20260919_01_w03` |
| UI 요소(프로토타입 배지) | `P-xx` 페이지 / `M-xx` 모달 / `B-xxx` 버튼 / `I-xxx` 입력 / `C-xx` 카드 | `B-112` |

### 0.3 Enum 정의

```
Sex                 = MALE | FEMALE
ActivityLevel       = SEDENTARY | LIGHT | MODERATE | ACTIVE | VERY_ACTIVE
                      (좌식 / 가벼움 / 보통 / 활동적 / 매우활동적)
TrainingExperience  = BEGINNER | INTERMEDIATE | ADVANCED        (초급 / 중급 / 상급)
EquipmentAccess     = FULL_GYM | HOME_DUMBBELL | BODYWEIGHT_ONLY (헬스장 / 홈덤벨 / 맨몸)
IntensityLevelId    = HARD | MODERATE | EASY                     (상 / 중 / 하)
GoalType            = CUT | LEAN_BULK | RECOMP | MAINTAIN        (감량 / 린벌크 / 체성분개선 / 유지)
ScanSource          = PHOTO_OCR | MANUAL | SEEDED                (사진판독 / 직접입력 / 샘플)
PlanStatus          = DRAFT | ACTIVE | PAUSED | COMPLETED | ARCHIVED
PhaseKind           = ADAPT | MAIN | DELOAD | PEAK | MAINTAIN    (적응기/본기/디로드/마무리/유지)
SessionKind         = FULL_BODY | UPPER | LOWER | PUSH | PULL | LEGS | CARDIO | REST
ExerciseRole        = PRIMARY_COMPOUND | SECONDARY_COMPOUND | ISOLATION | CORE | CONDITIONING
MealSlotId          = BREAKFAST | LUNCH | DINNER | SNACK_1 | SNACK_2 | PRE_WORKOUT | POST_WORKOUT
FeasibilityBand     = SAFE | CHALLENGING | STRAINED | UNREALISTIC (안정 / 도전적 / 무리 / 비현실적)
CheckpointVerdict   = ON_TRACK | AHEAD | BEHIND | STALLED | REVERSED
AdjustmentAction    = KCAL_DELTA | PROTEIN_DELTA | CARDIO_DELTA | VOLUME_DELTA |
                      SESSION_COUNT_DELTA | INSERT_DELOAD | INTENSITY_DOWNGRADE |
                      INTENSITY_UPGRADE | EXTEND_TARGET_DATE | NOTIFY_ONLY
```

---

## 1. 엔티티 정의

### 1.1 `UserProfile` — 사용자 프로필 (단일 레코드)

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 | 기본값 | 비고 |
|---|---|---|---|---|---|---|
| `id` | 식별자 | string | – | ✔ | `"owner"` | 단일 사용자이므로 고정 |
| `display_name` | 이름 | string | – | ✖ | `"나"` | |
| `sex` | 성별 | Sex | – | ✔ | – | BMR/최대 증근속도 계산에 사용 |
| `birth_date` | 생년월일 | date | – | ✔ | – | |
| `height_cm` | 신장 | number | cm | ✔ | – | BMI 계산 기준 |
| `activity_level` | 활동량 | ActivityLevel | – | ✔ | `MODERATE` | 운동 제외한 일상 활동 |
| `training_experience` | 운동 경력 | TrainingExperience | – | ✔ | `BEGINNER` | 최대 증근속도 상한 결정 |
| `training_years` | 운동 연차 | number | 년 | ✖ | 0 | |
| `equipment_access` | 운동 환경 | EquipmentAccess | – | ✔ | `FULL_GYM` | 종목 필터링 |
| `available_days_per_week` | 주당 가능일수 | int | 일 | ✔ | 4 | 1~7 |
| `session_minutes_cap` | 1회 최대 운동시간 | int | 분 | ✔ | 60 | |
| `preferred_training_days` | 선호 요일 | string[] | – | ✖ | `[]` | `MON`..`SUN` |
| `injuries` | 부상/통증 부위 | string[] | – | ✖ | `[]` | 종목 제외 필터 |
| `dietary_restrictions` | 식이 제한 | string[] | – | ✖ | `[]` | 예: `"유당불내증"`, `"채식"` |
| `disliked_foods` | 기피 식품 | string[] | – | ✖ | `[]` | |
| `cooking_capability` | 조리 가능도 | `LOW\|MID\|HIGH` | – | ✖ | `MID` | 식단 템플릿 난이도 |
| `budget_level` | 식비 수준 | `LOW\|MID\|HIGH` | – | ✖ | `MID` | |
| `created_at` / `updated_at` | 생성/수정 시각 | datetime | – | ✔ | – | |

**파생:** `age_years`, `height_m`, `bmr_fallback_kcal` (1.4절 참조)

---

### 1.2 `InBodyScan` — 인바디 측정 1건

사진 1장 = 스캔 1건. 모든 표준 출력 항목을 보관한다.

#### 1.2.1 메타

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 | 비고 |
|---|---|---|---|---|---|
| `id` | 스캔 ID | string | – | ✔ | `scan_20260914_01` |
| `measured_at` | 측정일시 | datetime | – | ✔ | 인바디 용지의 측정 시각 |
| `device_model` | 측정 장비 | string | – | ✖ | `"InBody 770"` |
| `source` | 입력 방식 | ScanSource | – | ✔ | |
| `image_ref` | 사진 참조키 | string \| null | – | ✖ | `mybody:v1:scan_image:<id>` |
| `height_cm_at_scan` | 측정 시 신장 | number | cm | ✖ | 없으면 프로필 값 사용 |
| `note` | 메모 | string | – | ✖ | |
| `is_baseline` | 기준 스캔 여부 | boolean | – | ✔ | 목표 산출의 시작점 |
| `created_at` | 생성 시각 | datetime | – | ✔ | |

#### 1.2.2 체성분 분석 (Body Composition Analysis)

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `tbw_l` | 체수분 (TBW) | number | L | ✖ |
| `icw_l` | 세포내수분 (ICW) | number | L | ✖ |
| `ecw_l` | 세포외수분 (ECW) | number | L | ✖ |
| `protein_kg` | 단백질 | number | kg | ✖ |
| `minerals_kg` | 무기질 | number | kg | ✖ |
| `bmc_kg` | 골무기질량 (BMC) | number | kg | ✖ |
| `bfm_kg` | 체지방량 (BFM) | number | kg | **✔** |
| `weight_kg` | 체중 | number | kg | **✔** |

#### 1.2.3 골격근·지방 분석 (Muscle-Fat Analysis)

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `smm_kg` | 골격근량 (SMM) | number | kg | **✔** |
| `ffm_kg` | 제지방량 (FFM) | number | kg | ✖ (없으면 파생) |
| `weight_pct_of_standard` | 체중 표준대비 | number | % | ✖ |
| `smm_pct_of_standard` | 골격근량 표준대비 | number | % | ✖ |
| `bfm_pct_of_standard` | 체지방량 표준대비 | number | % | ✖ |

> ⚠️ 사용자가 말한 **“근력량”은 인바디 용지에 없는 항목**이다. 실제 항목은 **골격근량(SMM)** 이므로 앱 전체에서 `smm_kg` 로 통일하고, UI 라벨은 `"골격근량(근육량)"` 으로 노출한다.

#### 1.2.4 비만 분석 (Obesity Analysis)

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `bmi` | 체질량지수 (BMI) | number | kg/m² | ✖ (파생 가능) |
| `pbf_pct` | 체지방률 (PBF) | number | % | ✖ (파생 가능) |
| `obesity_degree_pct` | 비만도 | number | % | ✖ |

#### 1.2.5 부위별 근육 분석 (Segmental Lean Analysis) — `segmental_lean`

5개 부위 각각 `{ mass_kg, pct_of_standard }`

| 키 | 한글 라벨 |
|---|---|
| `right_arm` | 오른팔 |
| `left_arm` | 왼팔 |
| `trunk` | 몸통 |
| `right_leg` | 오른다리 |
| `left_leg` | 왼다리 |

#### 1.2.6 부위별 체지방 분석 (Segmental Fat Analysis) — `segmental_fat`

동일 5개 키, 각각 `{ mass_kg, pct_of_standard }`

#### 1.2.7 연구 항목 / 추가 지표

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `bmr_kcal` | 기초대사량 (BMR) | int | kcal | ✖ (없으면 파생) |
| `whr` | 복부지방률 (WHR) | number | ratio | ✖ |
| `vfl_level` | 내장지방레벨 (VFL) | int | level | ✖ |
| `ecw_tbw_ratio` | 세포외수분비 | number | ratio | ✖ |
| `inbody_score` | 인바디 점수 | int | point | ✖ |
| `smi_kg_m2` | 골격근지수 (SMI) | number | kg/m² | ✖ |

#### 1.2.8 체중조절 항목 (Weight Control)

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `ideal_weight_kg` | 적정체중 | number | kg | ✖ |
| `weight_control_kg` | 체중조절 | number | kg (±) | ✖ |
| `fat_control_kg` | 지방조절 | number | kg (±) | ✖ |
| `muscle_control_kg` | 근육조절 | number | kg (±) | ✖ |

#### 1.2.9 OCR 스텁 — `ocr` (source = `PHOTO_OCR` 일 때만)

```
ocr: {
  engine: "stub-v0",              // 프로토타입에선 항상 스텁
  processed_at: datetime,
  overall_confidence: 0~1,
  needs_review: boolean,          // 하나라도 confidence < 0.85 이면 true → 모달 M-02 띄움
  fields: OcrFieldResult[]
}

OcrFieldResult {
  target_field: string,           // "weight_kg" 등 InBodyScan 경로
  raw_text: string,               // "78.0 kg"
  parsed_value: number|null,
  confidence: 0~1,
  bbox: [x, y, w, h] | null,      // 0~1 정규화 좌표 (사진 위 하이라이트용)
  edited_by_user: boolean
}
```

프로토타입 규칙: `PHOTO_OCR` 선택 시 실제 판독을 하지 않고 **샘플 값 + 임의 confidence** 를 주입한 뒤, 사용자가 확인·수정하는 모달(`M-02`)을 반드시 거치게 한다.

---

### 1.3 `Goal` — 목표

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 | 비고 |
|---|---|---|---|---|---|
| `id` | 목표 ID | string | – | ✔ | |
| `baseline_scan_id` | 기준 스캔 | string | – | ✔ | 현재값의 출처 |
| `start_date` | 시작일 | date | – | ✔ | |
| `target_date` | 목표일 | date | – | ✔ | |
| `target_weight_kg` | 목표 체중 | number | kg | ✔ | |
| `target_smm_kg` | 목표 골격근량 | number | kg | ✔ | |
| `target_bfm_kg` | 목표 체지방량 | number | kg | ✔ | |
| `target_pbf_pct` | 목표 체지방률 | number | % | ✖ | 입력 시 `target_bfm_kg` 역산 가능 |
| `priority` | 우선순위 | `FAT_FIRST\|MUSCLE_FIRST\|BALANCED` | – | ✔ | 충돌 시 무엇을 양보할지 |
| `selected_intensity` | 선택 강도 | IntensityLevelId | – | ✖ | 미선택 시 `recommended_intensity` |
| `hard_constraints` | 제약 조건 | object | – | ✖ | `{ min_kcal: 1600, max_days_per_week: 5 }` |
| `motivation_note` | 메모 | string | – | ✖ | |
| `status` | 상태 | `ACTIVE\|ACHIEVED\|ABANDONED\|SUPERSEDED` | – | ✔ | |
| `created_at`/`updated_at` | 생성/수정 | datetime | – | ✔ | |

입력 방식은 **절대값(목표 체중 72kg)** 과 **변화량(−6kg)** 둘 다 허용하되, 저장은 **항상 절대값**으로 정규화하고 변화량은 파생 필드로 둔다. (사용자 원문은 “변화 입력” → UI에선 델타 입력 토글 `I-204` 제공)

---

### 1.4 `IntensityLevel` — 실현 강도 프리셋 (상/중/하)

읽기 전용 시드 데이터. 계획 생성 엔진의 파라미터 묶음.

| 필드 | 한글 라벨 | 타입 | 단위 | HARD(상) | MODERATE(중) | EASY(하) |
|---|---|---|---|---|---|---|
| `id` | 식별자 | IntensityLevelId | – | `HARD` | `MODERATE` | `EASY` |
| `label_ko` | 라벨 | string | – | 상 | 중 | 하 |
| `tagline_ko` | 한 줄 설명 | string | – | 최단기간·고강도 | 균형 잡힌 기본 | 지속 가능·저부담 |
| `max_fat_loss_pct_bw_week` | 최대 감량속도 | number | %체중/주 | 1.00 | 0.75 | 0.45 |
| `deficit_pct_of_tdee` | 칼로리 적자 | number | % | 25 | 18 | 12 |
| `surplus_pct_of_tdee` | 칼로리 잉여(증량 시) | number | % | 15 | 10 | 5 |
| `protein_g_per_kg` | 단백질 | number | g/kg 체중 | 2.4 | 2.0 | 1.6 |
| `fat_g_per_kg_min` | 최소 지방 | number | g/kg 체중 | 0.6 | 0.8 | 0.9 |
| `sessions_per_week` | 주당 근력 세션 | int | 회 | 5 | 4 | 3 |
| `cardio_sessions_per_week` | 주당 유산소 | int | 회 | 3 | 2 | 1 |
| `cardio_minutes_per_session` | 유산소 시간 | int | 분 | 30 | 25 | 20 |
| `daily_step_target` | 걸음 목표 | int | 보 | 10000 | 8000 | 6000 |
| `session_minutes` | 세션 길이 | int | 분 | 75 | 60 | 45 |
| `weekly_sets_per_muscle` | 부위별 주간 세트 | `[min,max]` | 세트 | `[16,22]` | `[12,16]` | `[8,12]` |
| `rpe_range` | 목표 RPE | `[min,max]` | – | `[8,9.5]` | `[7,8.5]` | `[6,8]` |
| `split_template_id` | 분할 템플릿 | string | – | `PPL_UL_5D` | `UPPER_LOWER_4D` | `FULL_BODY_3D` |
| `free_meals_per_week` | 자유식 | int | 회 | 0 | 1 | 2 |
| `diet_strictness` | 식단 엄격도 | `STRICT\|FLEX\|LOOSE` | – | `STRICT` | `FLEX` | `LOOSE` |
| `deload_every_weeks` | 디로드 주기 | int | 주 | 5 | 6 | 8 |
| `checkin_frequency_days` | 체크인 주기 | int | 일 | 7 | 7 | 14 |
| `expected_adherence_pct` | 가정 준수율 | int | % | 90 | 80 | 70 |

---

### 1.5 `Plan` — 플랜 루트 (운동 + 식단 + 타임라인)

| 필드 | 한글 라벨 | 타입 | 필수 | 비고 |
|---|---|---|---|---|
| `id` | 플랜 ID | string | ✔ | |
| `goal_id` | 목표 참조 | string | ✔ | |
| `baseline_scan_id` | 기준 스캔 | string | ✔ | |
| `intensity` | 강도 | IntensityLevelId | ✔ | 강도별로 별도 Plan 3개 생성 → 비교 화면 `P-04` |
| `revision` | 개정 번호 | int | ✔ | AdjustmentRule 적용 시 +1 |
| `generated_at` | 생성 시각 | datetime | ✔ | |
| `generator_version` | 엔진 버전 | string | ✔ | `"planner-0.1.0"` |
| `status` | 상태 | PlanStatus | ✔ | 동시에 `ACTIVE` 는 1개만 |
| `feasibility` | 실현 가능성 | object | ✔ | 2.3절 파생 묶음 |
| `timeline` | 타임라인 | `Phase[]` | ✔ | |
| `workout_plan` | 운동 플랜 | WorkoutPlan | ✔ | |
| `diet_plan` | 식단 플랜 | DietPlan | ✔ | |
| `assumptions` | 가정 | string[] | ✔ | UI 하단 고지 (`C-31`) |
| `warnings` | 경고 | Warning[] | ✔ | `{ code, severity, message_ko }` |
| `adjustment_rule_ids` | 적용 규칙 | string[] | ✔ | |
| `superseded_by` | 대체 플랜 | string \| null | ✖ | |

#### `Phase` — 타임라인 구간

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `index` | 순번 | int | – |
| `kind` | 구간 종류 | PhaseKind | – |
| `label_ko` | 라벨 | string | – |
| `start_week` / `end_week` | 시작/종료 주차 | int | 주 (1-base, 포함) |
| `start_date` / `end_date` | 시작/종료일 | date | – |
| `kcal_modifier_pct` | 칼로리 조정 | number | % (디로드 0, 적응기 +5) |
| `volume_modifier_pct` | 볼륨 조정 | number | % (디로드 −40) |
| `expected_weight_kg` | 예상 체중(종료 시) | number | kg |
| `expected_smm_kg` | 예상 골격근량 | number | kg |
| `expected_bfm_kg` | 예상 체지방량 | number | kg |
| `focus_ko` | 중점 | string | – |

---

### 1.6 `WorkoutPlan`

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `split_template_id` | 분할 템플릿 | string | – |
| `split_label_ko` | 분할 이름 | string | – |
| `sessions_per_week` | 주당 세션 | int | 회 |
| `weekly_schedule` | 요일 배치 | `{MON..SUN: SessionKind}` | – |
| `progression_model` | 점진 과부하 방식 | `DOUBLE_PROGRESSION\|LINEAR\|RPE_AUTOREG` | – |
| `weekly_sets_by_muscle` | 부위별 주간 세트 | `{ chest, back, quads, hams, glutes, delts, biceps, triceps, core, calves: int }` | 세트 |
| `sessions` | 세션 목록 | `WorkoutSession[]` | – |
| `cardio_prescription` | 유산소 처방 | CardioPrescription | – |
| `weak_point_focus` | 약점 보강 | string[] | – (부위별 근육분석 비대칭에서 자동 도출) |
| `estimated_weekly_minutes` | 주간 총 시간 | int | 분 |

#### `WorkoutSession`

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `id` | 세션 ID | string | – (`s_upper_a`) |
| `day_of_week` | 요일 | string | `MON`.. |
| `kind` | 종류 | SessionKind | – |
| `label_ko` | 이름 | string | – (`"상체 A"`) |
| `order_in_week` | 주 내 순서 | int | – |
| `warmup_ko` | 워밍업 | string | – |
| `exercises` | 종목 | `ExercisePrescription[]` | – |
| `finisher_ko` | 마무리 | string \| null | – |
| `estimated_minutes` | 예상 소요 | int | 분 |
| `target_rpe_avg` | 평균 목표 RPE | number | – |

#### `ExercisePrescription`

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `slot` | 순번 | int | – | ✔ |
| `exercise_id` | 종목 ID | string | – | ✔ |
| `name_ko` / `name_en` | 종목명 | string | – | ✔ |
| `role` | 역할 | ExerciseRole | – | ✔ |
| `primary_muscle` | 주동근 | string | – | ✔ |
| `secondary_muscles` | 협응근 | string[] | – | ✖ |
| `equipment` | 기구 | string | – | ✔ |
| `sets` | 세트 수 | int | 세트 | ✔ |
| `rep_min` / `rep_max` | 반복 범위 | int | 회 | ✔ |
| `rpe_target` | 목표 RPE | number | 1~10 | ✔ |
| `rest_sec` | 휴식 | int | 초 | ✔ |
| `tempo` | 템포 | string | – | ✖ (`"3-1-1-0"`) |
| `load_kg` | 권장 중량 | number \| null | kg | ✖ (1RM 미입력 시 null) |
| `load_pct_1rm` | 1RM 대비 | number \| null | % | ✖ |
| `progression_rule_ko` | 증량 규칙 | string | – | ✔ |
| `substitutions` | 대체 종목 | `{exercise_id, name_ko, reason_ko}[]` | – | ✖ |
| `note_ko` | 메모 | string | – | ✖ |

#### `CardioPrescription`

`{ modality: "TREADMILL_INCLINE"|"CYCLE"|"ROWER"|"WALK", sessions_per_week: int, minutes_per_session: int, intensity_ko: "LISS"|"Zone2"|"HIIT", target_hr_pct: [min,max], placement_ko: "근력 후 / 비운동일", est_kcal_per_session: int }`

#### `ExerciseCatalogItem` — 종목 라이브러리 (코드에 하드코딩된 시드)

`{ id, name_ko, name_en, role, primary_muscle, secondary_muscles[], equipment, difficulty: 1..3, unilateral: bool, contraindicated_for: string[], default_rep_range: [min,max], default_rest_sec }`

---

### 1.7 `DietPlan`

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `bmr_kcal` | 기초대사량 | int | kcal |
| `bmr_source` | BMR 출처 | `INBODY\|KATCH_MCARDLE\|MIFFLIN` | – |
| `activity_factor` | 활동계수 | number | – |
| `exercise_kcal_per_week` | 운동 소모 | int | kcal/주 |
| `tdee_kcal` | 총 소비열량 | int | kcal/일 |
| `daily_delta_kcal` | 일일 적자/잉여 | int | kcal (음수=적자) |
| `target_kcal` | 목표 섭취 | int | kcal/일 |
| `training_day_kcal` | 운동일 섭취 | int | kcal |
| `rest_day_kcal` | 휴식일 섭취 | int | kcal |
| `protein_g` | 단백질 | int | g/일 |
| `fat_g` | 지방 | int | g/일 |
| `carb_g` | 탄수화물 | int | g/일 |
| `fiber_g_min` | 식이섬유 최소 | int | g/일 |
| `water_ml` | 수분 | int | mL/일 |
| `sodium_mg_max` | 나트륨 상한 | int | mg/일 |
| `protein_g_per_kg` | 단백질 밀도 | number | g/kg |
| `kcal_floor` | 섭취 하한 | int | kcal (안전장치) |
| `meal_count` | 끼니 수 | int | 끼 |
| `meal_template` | 끼니 템플릿 | `MealSlot[]` | – |
| `free_meals_per_week` | 자유식 | int | 회 |
| `refeed_ko` | 리피드/다이어트 브레이크 | string \| null | – |
| `supplements` | 보충제 | `{name_ko, dose_ko, timing_ko}[]` | – |
| `grocery_list_ko` | 장보기 목록 | string[] | – |

#### `MealSlot`

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `slot` | 끼니 | MealSlotId | – |
| `label_ko` | 라벨 | string | – |
| `time_hint` | 권장 시각 | string | `"08:00"` |
| `kcal` | 열량 | int | kcal |
| `protein_g` / `fat_g` / `carb_g` | 매크로 | int | g |
| `kcal_share_pct` | 배분 비율 | number | % |
| `items` | 구성 | `MealItem[]` | – |
| `swap_options_ko` | 교체안 | string[] | – |

#### `MealItem`

`{ food_id, name_ko, amount, unit_ko ("g"|"개"|"공기"|"큰술"), kcal, protein_g, fat_g, carb_g, is_swappable: bool }`

#### `FoodCatalogItem` — 식품 라이브러리 시드

`{ id, name_ko, category_ko, per_100g: {kcal, protein_g, fat_g, carb_g}, common_portion: {amount, unit_ko, grams}, tags: ["고단백","저지방","한식"] }`

---

### 1.8 `ProgressLog` — 일일 기록

| 필드 | 한글 라벨 | 타입 | 단위 | 필수 |
|---|---|---|---|---|
| `id` | 기록 ID | string | – | ✔ (`log_20260921`) |
| `date` | 날짜 | date | – | ✔ |
| `plan_id` | 플랜 참조 | string | – | ✔ |
| `weight_kg` | 체중 | number \| null | kg | ✖ (아침 공복 기준) |
| `kcal_actual` | 실제 섭취 | int \| null | kcal | ✖ |
| `protein_g_actual` | 실제 단백질 | int \| null | g | ✖ |
| `diet_adherence_pct` | 식단 준수율 | int \| null | % | ✖ (자동 계산 or 수동) |
| `workout_done` | 운동 수행 | `DONE\|PARTIAL\|SKIPPED\|REST` | – | ✔ |
| `session_id` | 수행 세션 | string \| null | – | ✖ |
| `set_logs` | 세트 기록 | `SetLog[]` | – | ✖ |
| `cardio_minutes` | 유산소 | int | 분 | ✖ |
| `steps` | 걸음 수 | int \| null | 보 | ✖ |
| `sleep_hours` | 수면 | number \| null | h | ✖ |
| `energy_1_5` | 컨디션 | int \| null | 1~5 | ✖ |
| `soreness_1_5` | 근육통 | int \| null | 1~5 | ✖ |
| `note_ko` | 메모 | string | – | ✖ |

`SetLog` = `{ exercise_id, set_index, reps, load_kg, rpe, is_failure: bool }`

---

### 1.9 `WeeklyCheckpoint` — 주간 체크포인트

| 필드 | 한글 라벨 | 타입 | 단위 |
|---|---|---|---|
| `id` | 체크포인트 ID | string | – |
| `goal_id` / `plan_id` | 참조 | string | – |
| `week_index` | 주차 | int | 주 (1-base) |
| `period_start` / `period_end` | 기간 | date | – |
| `scan_id` | 이 주의 인바디 | string \| null | – (있으면 실측 체성분 사용) |
| `weight_ma7_kg` | 7일 이동평균 체중 | number | kg |
| `weight_trend_kg_per_week` | 체중 추세 | number | kg/주 |
| `planned_weight_kg` | 계획 체중 | number | kg |
| `weight_gap_kg` | 계획 대비 차이 | number | kg |
| `bfm_kg` / `smm_kg` | 실측 체지방/골격근 | number \| null | kg |
| `diet_adherence_pct` | 식단 준수율 | int | % |
| `workout_adherence_pct` | 운동 완료율 | int | % |
| `avg_sleep_hours` | 평균 수면 | number | h |
| `avg_steps` | 평균 걸음 | int | 보 |
| `volume_load_kg` | 총 볼륨 부하 | number | kg |
| `strength_index_delta_pct` | 근력 지표 변화 | number | % |
| `progress_ratio` | 진행률 | number | 실제/계획 |
| `verdict` | 판정 | CheckpointVerdict | – |
| `triggered_rule_ids` | 발동 규칙 | string[] | – |
| `applied_adjustments` | 적용 조정 | `Adjustment[]` | – |
| `message_ko` | 요약 코멘트 | string | – |

`Adjustment` = `{ rule_id, action: AdjustmentAction, magnitude, unit, before, after, applied_at, accepted_by_user: bool }`

---

### 1.10 `AdjustmentRule` — 자동 조정 규칙 (시드 데이터)

| 필드 | 한글 라벨 | 타입 |
|---|---|---|
| `id` | 규칙 ID | string (`R-01`) |
| `label_ko` | 규칙명 | string |
| `priority` | 우선순위 | int (낮을수록 우선) |
| `applies_to_intensity` | 적용 강도 | IntensityLevelId[] |
| `condition` | 조건식 | `Condition` (아래 DSL) |
| `action` | 조치 | AdjustmentAction |
| `magnitude` | 크기 | number |
| `unit` | 단위 | `kcal`\|`pct`\|`sessions`\|`minutes`\|`weeks`\|`level` |
| `clamp` | 상·하한 | `{min, max}` |
| `cooldown_days` | 재발동 금지 기간 | int |
| `requires_user_confirm` | 사용자 확인 필요 | boolean |
| `message_ko` | 안내 문구 | string |

`Condition` DSL (JSON, 순수 평가 함수로 해석):
```json
{ "all": [
  { "metric": "progress_ratio",      "op": "<",  "value": 0.4, "window_weeks": 2 },
  { "metric": "diet_adherence_pct",  "op": ">=", "value": 85,  "window_weeks": 2 }
]}
```
지원 metric: `progress_ratio`, `weight_trend_kg_per_week`, `diet_adherence_pct`, `workout_adherence_pct`, `avg_sleep_hours`, `strength_index_delta_pct`, `pbf_pct_delta`, `weeks_elapsed`, `avg_energy_1_5`.

**시드 규칙 (초기 8개)**

| ID | 조건 | 조치 | 크기 | 확인필요 |
|---|---|---|---|---|
| `R-01` | 2주 연속 `progress_ratio < 0.4` AND `diet_adherence_pct ≥ 85` | `KCAL_DELTA` | −5% (최대 −150 kcal) | ✖ |
| `R-02` | 2주 연속 `progress_ratio > 1.6` AND `strength_index_delta_pct < −3` | `KCAL_DELTA` | +120 kcal | ✖ |
| `R-03` | 2주 연속 `diet_adherence_pct < 70` | `INTENSITY_DOWNGRADE` | 1단계 | ✔ (`M-05`) |
| `R-04` | 2주 연속 `workout_adherence_pct < 60` | `SESSION_COUNT_DELTA` | −1회/주 | ✔ |
| `R-05` | `weeks_elapsed % deload_every_weeks == 0` | `INSERT_DELOAD` | 1주 | ✖ |
| `R-06` | 3주 연속 `weight_trend ≈ 0` AND `diet_adherence_pct ≥ 85` | `CARDIO_DELTA` | +1회 × 20분 | ✖ |
| `R-07` | `avg_sleep_hours < 6` AND `avg_energy_1_5 ≤ 2` | `VOLUME_DELTA` | −20% (1주) | ✖ |
| `R-08` | 남은 주차 기준 `feasibility_band == UNREALISTIC` | `EXTEND_TARGET_DATE` | +4주 | ✔ (`M-06`) |

---

### 1.11 프로토타입 전용: `UiElement` + `FeedbackNote`

검증 단계의 핵심. 모든 페이지/모달/버튼에 고유번호 배지를 붙이고, 그 번호로 피드백을 남긴다.

`UiElement` (코드에 선언된 레지스트리, `data-uid` 속성과 1:1)

| 필드 | 타입 | 예시 |
|---|---|---|
| `uid` | string | `B-112` |
| `kind` | `PAGE\|MODAL\|BUTTON\|INPUT\|CARD\|TAB\|TOAST` | `BUTTON` |
| `page_uid` | string | `P-02` |
| `label_ko` | string | `"플랜 생성"` |
| `purpose_ko` | string | `"선택 강도로 3개 플랜 생성"` |
| `status` | `STUB\|MOCK\|WIRED` | `MOCK` |

`FeedbackNote` (owner가 프로토타입에서 직접 남김 → `localStorage`)

`{ id, uid, created_at, verdict: "OK"|"CHANGE"|"REMOVE"|"QUESTION", text_ko, resolved: bool }`

**번호 체계 (예약 대역)**

| 대역 | 화면 |
|---|---|
| `P-01` | 홈/대시보드 |
| `P-02` | 인바디 사진 업로드 & 판독 확인 |
| `P-03` | 목표 입력 |
| `P-04` | 강도 3안 비교 (상/중/하) |
| `P-05` | 플랜 상세 — 운동 |
| `P-06` | 플랜 상세 — 식단 |
| `P-07` | 주간 체크인 / 기록 |
| `P-08` | 진행 추이 |
| `P-09` | 설정 / 데이터 관리 |
| `M-01`~`M-09` | 모달 (사진선택, OCR확인, 종목교체, 식단교체, 강도하향, 일정연장, 초기화, 도움말, 피드백작성) |
| `B-0xx` | 공통/네비 버튼 |
| `B-1xx`~`B-9xx` | 각 페이지 번호 × 100 대역 (예: `P-02`의 버튼은 `B-2xx`) |
| `I-xxx` | 입력 필드 (동일 대역 규칙) |
| `C-xx` | 카드/위젯 |

---

## 2. 파생 / 계산 필드

> 모든 파생값은 **저장하지 않고 조회 시 계산**하는 것이 원칙. 예외: `Plan.feasibility`, `Phase.expected_*`, `WeeklyCheckpoint.*` 는 생성 시점의 스냅샷이므로 저장한다(나중에 규칙이 바뀌어도 과거 판단 근거가 보존되어야 하므로).

### 2.1 UserProfile 파생

| 필드 | 수식 |
|---|---|
| `age_years` | `floor((today − birth_date) / 365.25)` |
| `height_m` | `height_cm / 100` |
| `bmr_mifflin_kcal` | 남: `10·W + 6.25·H_cm − 5·age + 5` / 여: `… − 161` |

### 2.2 InBodyScan 파생

| 필드 | 수식 | 비고 |
|---|---|---|
| `ffm_kg` | `weight_kg − bfm_kg` | 용지 값이 있으면 그 값 우선, 없으면 계산 |
| `pbf_pct` | `bfm_kg / weight_kg × 100` | 소수 1자리 |
| `bmi` | `weight_kg / height_m²` | |
| `smm_ffm_ratio` | `smm_kg / ffm_kg` | 체성분 일관성 검증의 핵심 계수 `k` |
| `smi_kg_m2` | `(segmental_lean 사지 4부위 합) / height_m²` | 근감소증 지표 |
| `bmr_katch_kcal` | `370 + 21.6 × ffm_kg` | Katch-McArdle. `bmr_kcal` 없을 때 fallback |
| `bmr_effective_kcal` | `bmr_kcal ?? bmr_katch_kcal ?? bmr_mifflin_kcal` | 출처를 `bmr_source` 에 기록 |
| `ideal_weight_calc_kg` | `22 × height_m²` | 용지 `ideal_weight_kg` 없을 때 |
| `fat_control_calc_kg` | `(목표 PBF 기준 지방) − bfm_kg`, 목표 PBF 남 15% / 여 23% | |
| `muscle_control_calc_kg` | `ideal_weight − ffm_kg − 목표지방` 을 SMM 환산 | |
| `arm_asymmetry_pct` | `(RA − LA) / ((RA+LA)/2) × 100` | 절댓값 5% 초과 시 경고 → 약점 보강 |
| `leg_asymmetry_pct` | `(RL − LL) / ((RL+LL)/2) × 100` | 동일 |
| `trunk_lean_ratio` | `trunk.mass_kg / ffm_kg` | |
| `ecw_tbw_flag` | `ecw_tbw_ratio > 0.390` → `"부종 의심"` | |
| `days_since_prev` | `measured_at − prev.measured_at` (일) | |
| `delta_prev_weight_kg` / `delta_prev_smm_kg` / `delta_prev_bfm_kg` / `delta_prev_pbf_pct` | 현재 − 직전 스캔 | 추이 카드 `C-12` |

### 2.3 Goal 파생 — 여기서 “실현 강도”가 결정된다

```
// 기본 델타 (사용자가 델타로 입력했으면 역으로 절대값 산출)
delta_weight_kg      = target_weight_kg - baseline.weight_kg
delta_smm_kg         = target_smm_kg    - baseline.smm_kg
delta_bfm_kg         = target_bfm_kg    - baseline.bfm_kg
target_ffm_kg        = target_weight_kg - target_bfm_kg
target_pbf_pct       = target_bfm_kg / target_weight_kg * 100
delta_pbf_pct        = target_pbf_pct - baseline.pbf_pct
delta_ffm_kg         = target_ffm_kg - baseline.ffm_kg

// 체성분 정합성 검증 (사용자가 물리적으로 모순된 목표를 넣는 경우가 매우 흔함)
k                    = baseline.smm_kg / baseline.ffm_kg      // 통상 0.53~0.57
predicted_smm_kg     = k * target_ffm_kg
smm_residual_kg      = target_smm_kg - predicted_smm_kg
  // residual > +0.5 → 근육/제지방 비율 자체를 올려야 함 = 리컴프 목표
  // residual < -0.5 → 목표 골격근량이 목표 체중에 비해 과소 → 경고 W-GOAL-02

// 기간
duration_days        = target_date - start_date
duration_weeks       = duration_days / 7

// 요구 속도
weekly_weight_rate_kg = delta_weight_kg / duration_weeks
weekly_bfm_rate_kg    = delta_bfm_kg    / duration_weeks
weekly_smm_rate_kg    = delta_smm_kg    / duration_weeks
fat_loss_pct_bw_week  = abs(weekly_bfm_rate_kg) / baseline.weight_kg * 100
muscle_gain_pct_bw_month = weekly_smm_rate_kg * 4.345 / baseline.weight_kg * 100

// 목표 유형 분류
goal_type =
  delta_bfm_kg < -0.5 && delta_smm_kg >  0.5 ? RECOMP
: delta_bfm_kg < -0.5                        ? CUT
: delta_smm_kg >  0.5                        ? LEAN_BULK
:                                              MAINTAIN
```

**상한 테이블 (증근)** `max_muscle_gain_kg_month`

| 경력 | 남 | 여 |
|---|---|---|
| BEGINNER | 1.00 | 0.50 |
| INTERMEDIATE | 0.50 | 0.25 |
| ADVANCED | 0.25 | 0.13 |

```
recomp_factor = (goal_type == RECOMP) ? 0.60 : 1.00   // 칼로리 적자 중 증근 효율 저하
max_muscle_rate = max_muscle_gain_kg_month[exp][sex] * recomp_factor

// 강도별 부하율(strain) — 1.0 = 해당 강도의 상한에 정확히 걸침
fat_strain(L)    = fat_loss_pct_bw_week / IntensityLevel[L].max_fat_loss_pct_bw_week
muscle_strain    = (weekly_smm_rate_kg * 4.345) / max_muscle_rate
strain(L)        = max(fat_strain(L), muscle_strain)

feasibility_score(L) = clamp(round(100 * (1.6 - strain(L)) / 0.9), 0, 100)
feasibility_band     = score >= 80 ? SAFE
                     : score >= 60 ? CHALLENGING
                     : score >= 40 ? STRAINED
                     :               UNREALISTIC

// 최소 소요 기간 (각 강도에서)
weeks_fat(L)    = abs(delta_bfm_kg) / (IntensityLevel[L].max_fat_loss_pct_bw_week/100 * baseline.weight_kg)
weeks_muscle    = max(0, delta_smm_kg) / (max_muscle_rate / 4.345)
min_feasible_weeks(L) = ceil(max(weeks_fat(L), weeks_muscle))

recommended_intensity = 가장 낮은 강도 중 feasibility_band != UNREALISTIC 인 것,
                        없으면 HARD + 경고 W-GOAL-01 (기간 연장 제안 모달 M-06)
```

### 2.4 DietPlan 파생

```
activity_factor = { SEDENTARY:1.20, LIGHT:1.375, MODERATE:1.45, ACTIVE:1.55, VERY_ACTIVE:1.70 }[activity_level]
  // 주의: 운동 세션 소모는 아래에서 별도 가산하므로 계수는 "비운동 활동" 기준으로 보수적으로 잡음

exercise_kcal_per_week = Σ(근력 세션 × session_minutes × 6 kcal/min)
                       + Σ(유산소 세션 × minutes × 8 kcal/min)
tdee_kcal = round(bmr_effective_kcal * activity_factor + exercise_kcal_per_week / 7)

// 적자/잉여: 목표 지방 감소 속도에서 역산 (7700 kcal ≈ 지방 1kg)
required_daily_deficit = abs(weekly_bfm_rate_kg) * 7700 / 7          // 감량 시
preset_daily_deficit   = tdee_kcal * IntensityLevel[L].deficit_pct_of_tdee / 100
daily_delta_kcal       = -min(required_daily_deficit, preset_daily_deficit)   // 더 완만한 쪽 채택
  // 증량이면 부호 반전 + surplus_pct_of_tdee 사용

kcal_floor   = max(bmr_effective_kcal * 1.10, 22 * ffm_kg, sex==MALE ? 1500 : 1200)
target_kcal  = round_to_10(clamp(tdee_kcal + daily_delta_kcal, kcal_floor, tdee_kcal * 1.25))

// 매크로 — 단백질·지방 고정 후 탄수 잔여
ref_weight_kg = min(baseline.weight_kg, target_weight_kg)   // 비만 시 과다 단백질 방지
protein_g = round(IntensityLevel[L].protein_g_per_kg * ref_weight_kg)
fat_g     = round(max(IntensityLevel[L].fat_g_per_kg_min * ref_weight_kg,
                      target_kcal * 0.20 / 9))
carb_g    = round((target_kcal - protein_g*4 - fat_g*9) / 4)
if (carb_g < 100) { fat_g -= ceil((100 - carb_g) * 4 / 9); carb_g = 100 }   // 탄수 하한 재조정

fiber_g_min = round(target_kcal / 1000 * 14)
water_ml    = round(weight_kg * 35 + cardio_minutes * 10)

// 운동일/휴식일 사이클링 (중·상 강도만)
training_day_kcal = target_kcal + round(target_kcal * 0.08)
rest_day_kcal     = target_kcal - round(target_kcal * 0.08 * training_days / rest_days)

// 끼니 배분 (meal_count=4 기준)
kcal_share = { BREAKFAST: 25%, LUNCH: 30%, DINNER: 30%, SNACK_1: 15% }
```

### 2.5 WorkoutPlan 파생

```
weekly_sets_by_muscle[m] = Σ over sessions Σ over exercises
                             (primary_muscle==m ? sets : 0) + (secondary 포함 시 sets*0.5)
estimated_session_minutes = Σ(sets * (rep_avg * 3.5 sec + rest_sec)) / 60 + 워밍업 8분
weekly_volume_load_kg     = Σ(sets * rep_avg * load_kg)
strength_index            = Σ over 빅3(스쿼트/벤치/데드) of e1RM,
                            e1RM = load_kg * (1 + reps/30)        // Epley
weak_point_focus          = abs(arm_asymmetry_pct) > 5 → "팔 단측 보강",
                            abs(leg_asymmetry_pct) > 5 → "다리 단측 보강",
                            segmental_lean.trunk.pct_of_standard < 95 → "코어/등 보강"
```

### 2.6 ProgressLog / WeeklyCheckpoint 파생

```
weight_ma7_kg            = mean(최근 7일 중 weight_kg 비null 값)   // 최소 3건 필요
weight_trend_kg_per_week = 최근 14일 (date, weight) 최소제곱 기울기 × 7
planned_weight_kg(w)     = baseline.weight_kg + weekly_weight_rate_kg * w
                           (Phase의 kcal_modifier 반영 시 구간별 누적)
weight_gap_kg            = weight_ma7_kg - planned_weight_kg(w)
progress_ratio           = (baseline.weight_kg - weight_ma7_kg) /
                           (baseline.weight_kg - planned_weight_kg(w))     // 0으로 나눔 방지
diet_adherence_pct       = mean over days of clamp(100 - abs(kcal_actual - target_kcal)/target_kcal*100, 0, 100)
workout_adherence_pct    = (DONE*1 + PARTIAL*0.5) / planned_sessions * 100
verdict                  = progress_ratio >= 1.25 ? AHEAD
                         : progress_ratio >= 0.75 ? ON_TRACK
                         : progress_ratio >= 0.25 ? BEHIND
                         : progress_ratio > -0.25 ? STALLED
                         :                          REVERSED
strength_index_delta_pct = (이번주 strength_index / 기준주 strength_index - 1) * 100
```

### 2.7 경고 코드

| 코드 | 조건 | 심각도 | 문구 |
|---|---|---|---|
| `W-GOAL-01` | 모든 강도에서 `UNREALISTIC` | error | 목표일까지 기간이 부족합니다. 최소 N주 필요 |
| `W-GOAL-02` | `smm_residual_kg < -0.5` | warn | 목표 체중 대비 골격근량이 낮습니다 |
| `W-GOAL-03` | `target_pbf_pct < 8`(남) / `< 16`(여) | error | 권장 최저 체지방률 미만 |
| `W-DIET-01` | `target_kcal == kcal_floor` | warn | 섭취 하한에 도달, 목표 속도 달성 불가 |
| `W-DIET-02` | `protein_g/target_kcal*4 > 0.45` | warn | 단백질 비중 과다 |
| `W-SCAN-01` | `ecw_tbw_ratio > 0.390` | info | 부종 의심 — 측정 조건 확인 |
| `W-SCAN-02` | `abs(ffm_kg + bfm_kg - weight_kg) > 0.3` | warn | 판독값 불일치, 재확인 필요 |
| `W-PLAN-01` | `available_days_per_week < sessions_per_week` | warn | 가능 일수보다 세션이 많음 |

---

## 3. JSON 예시 (한국인 남성 샘플)

### 3.1 UserProfile

```json
{
  "id": "owner",
  "display_name": "나",
  "sex": "MALE",
  "birth_date": "1993-04-11",
  "height_cm": 175.0,
  "activity_level": "MODERATE",
  "training_experience": "BEGINNER",
  "training_years": 0.5,
  "equipment_access": "FULL_GYM",
  "available_days_per_week": 4,
  "session_minutes_cap": 70,
  "preferred_training_days": ["MON", "TUE", "THU", "FRI"],
  "injuries": ["좌측 어깨 충돌증후군"],
  "dietary_restrictions": [],
  "disliked_foods": ["오이"],
  "cooking_capability": "MID",
  "budget_level": "MID",
  "created_at": "2026-09-19T21:05:00+09:00",
  "updated_at": "2026-09-19T21:05:00+09:00"
}
```

### 3.2 InBodyScan (체중 78.0 / 골격근량 33.0 / 체지방량 18.0)

```json
{
  "id": "scan_20260914_01",
  "measured_at": "2026-09-14T09:12:00+09:00",
  "device_model": "InBody 770",
  "source": "PHOTO_OCR",
  "image_ref": "mybody:v1:scan_image:scan_20260914_01",
  "height_cm_at_scan": 175.0,
  "is_baseline": true,
  "note": "공복, 아침 측정",

  "body_composition": {
    "tbw_l": 43.9,
    "icw_l": 27.3,
    "ecw_l": 16.6,
    "protein_kg": 11.72,
    "minerals_kg": 4.18,
    "bmc_kg": 3.45,
    "bfm_kg": 18.0,
    "weight_kg": 78.0
  },

  "muscle_fat": {
    "weight_kg": 78.0,
    "smm_kg": 33.0,
    "ffm_kg": 60.0,
    "weight_pct_of_standard": 113.2,
    "smm_pct_of_standard": 104.8,
    "bfm_pct_of_standard": 152.5
  },

  "obesity": {
    "bmi": 25.5,
    "pbf_pct": 23.1,
    "obesity_degree_pct": 113.0
  },

  "segmental_lean": {
    "right_arm": { "mass_kg": 3.42, "pct_of_standard": 98.2 },
    "left_arm":  { "mass_kg": 3.19, "pct_of_standard": 91.6 },
    "trunk":     { "mass_kg": 26.80, "pct_of_standard": 101.5 },
    "right_leg": { "mass_kg": 9.82, "pct_of_standard": 99.4 },
    "left_leg":  { "mass_kg": 9.74, "pct_of_standard": 98.6 }
  },

  "segmental_fat": {
    "right_arm": { "mass_kg": 0.82, "pct_of_standard": 141.4 },
    "left_arm":  { "mass_kg": 0.85, "pct_of_standard": 146.6 },
    "trunk":     { "mass_kg": 9.90, "pct_of_standard": 163.0 },
    "right_leg": { "mass_kg": 2.35, "pct_of_standard": 128.4 },
    "left_leg":  { "mass_kg": 2.32, "pct_of_standard": 126.8 }
  },

  "research": {
    "bmr_kcal": 1663,
    "whr": 0.89,
    "vfl_level": 11,
    "ecw_tbw_ratio": 0.378,
    "inbody_score": 74,
    "smi_kg_m2": 8.55
  },

  "weight_control": {
    "ideal_weight_kg": 67.4,
    "weight_control_kg": -10.6,
    "fat_control_kg": -11.9,
    "muscle_control_kg": 1.3
  },

  "ocr": {
    "engine": "stub-v0",
    "processed_at": "2026-09-19T21:10:12+09:00",
    "overall_confidence": 0.91,
    "needs_review": true,
    "fields": [
      { "target_field": "body_composition.weight_kg", "raw_text": "78.0", "parsed_value": 78.0, "confidence": 0.99, "bbox": [0.62,0.21,0.08,0.03], "edited_by_user": false },
      { "target_field": "muscle_fat.smm_kg",          "raw_text": "33.0", "parsed_value": 33.0, "confidence": 0.97, "bbox": [0.62,0.26,0.08,0.03], "edited_by_user": false },
      { "target_field": "body_composition.bfm_kg",    "raw_text": "18.O", "parsed_value": 18.0, "confidence": 0.72, "bbox": [0.62,0.31,0.08,0.03], "edited_by_user": true },
      { "target_field": "research.vfl_level",         "raw_text": "11",   "parsed_value": 11,   "confidence": 0.83, "bbox": [0.70,0.58,0.05,0.03], "edited_by_user": false }
    ]
  },

  "created_at": "2026-09-19T21:10:12+09:00",

  "_derived_preview": {
    "ffm_kg": 60.0,
    "pbf_pct": 23.1,
    "bmi": 25.47,
    "smm_ffm_ratio": 0.550,
    "bmr_katch_kcal": 1666,
    "arm_asymmetry_pct": 6.96,
    "leg_asymmetry_pct": 0.82,
    "ecw_tbw_flag": null
  }
}
```

> `_derived_preview` 는 **저장하지 않는다.** 위 블록은 계산 결과를 보여주기 위한 예시일 뿐이며, 실제 저장 객체에서는 제외한다.

### 3.3 Goal (20주 리컴프)

```json
{
  "id": "goal_20260919_01",
  "baseline_scan_id": "scan_20260914_01",
  "start_date": "2026-09-20",
  "target_date": "2027-02-07",
  "target_weight_kg": 72.0,
  "target_smm_kg": 35.0,
  "target_bfm_kg": 12.0,
  "target_pbf_pct": null,
  "priority": "BALANCED",
  "selected_intensity": "MODERATE",
  "hard_constraints": { "min_kcal": 1700, "max_days_per_week": 5 },
  "motivation_note": "내년 봄 전까지 체지방률 17% 아래",
  "status": "ACTIVE",
  "created_at": "2026-09-19T21:14:00+09:00",
  "updated_at": "2026-09-19T21:14:00+09:00",

  "_derived_preview": {
    "delta_weight_kg": -6.0,
    "delta_smm_kg": 2.0,
    "delta_bfm_kg": -6.0,
    "delta_ffm_kg": 0.0,
    "target_ffm_kg": 60.0,
    "target_pbf_pct": 16.7,
    "delta_pbf_pct": -6.4,
    "k": 0.550,
    "predicted_smm_kg": 33.0,
    "smm_residual_kg": 2.0,
    "goal_type": "RECOMP",
    "duration_days": 140,
    "duration_weeks": 20.0,
    "weekly_weight_rate_kg": -0.30,
    "weekly_bfm_rate_kg": -0.30,
    "weekly_smm_rate_kg": 0.10,
    "fat_loss_pct_bw_week": 0.385,
    "muscle_gain_pct_bw_month": 0.557,
    "max_muscle_rate_kg_month": 0.60,
    "muscle_strain": 0.724,
    "feasibility_by_intensity": {
      "EASY":     { "fat_strain": 0.855, "strain": 0.855, "score": 83, "band": "SAFE",        "min_feasible_weeks": 18 },
      "MODERATE": { "fat_strain": 0.513, "strain": 0.724, "score": 97, "band": "SAFE",        "min_feasible_weeks": 15 },
      "HARD":     { "fat_strain": 0.385, "strain": 0.724, "score": 97, "band": "SAFE",        "min_feasible_weeks": 15 }
    },
    "recommended_intensity": "EASY",
    "warnings": []
  }
}
```

### 3.4 Plan (강도 = 중)

```json
{
  "id": "plan_20260919_01_MODERATE_r1",
  "goal_id": "goal_20260919_01",
  "baseline_scan_id": "scan_20260914_01",
  "intensity": "MODERATE",
  "revision": 1,
  "generated_at": "2026-09-19T21:15:02+09:00",
  "generator_version": "planner-0.1.0",
  "status": "ACTIVE",

  "feasibility": { "score": 97, "band": "SAFE", "strain": 0.724,
                   "limiting_factor": "MUSCLE_GAIN_RATE", "min_feasible_weeks": 15 },

  "timeline": [
    { "index": 1, "kind": "ADAPT",  "label_ko": "적응기",   "start_week": 1,  "end_week": 2,
      "start_date": "2026-09-20", "end_date": "2026-10-03",
      "kcal_modifier_pct": 5, "volume_modifier_pct": -20,
      "expected_weight_kg": 77.4, "expected_smm_kg": 33.2, "expected_bfm_kg": 17.4,
      "focus_ko": "폼 익히기 · 식사 패턴 고정" },
    { "index": 2, "kind": "MAIN",   "label_ko": "본 감량기 1", "start_week": 3,  "end_week": 8,
      "start_date": "2026-10-04", "end_date": "2026-11-14",
      "kcal_modifier_pct": 0, "volume_modifier_pct": 0,
      "expected_weight_kg": 75.6, "expected_smm_kg": 33.8, "expected_bfm_kg": 15.6,
      "focus_ko": "점진 과부하 + 적자 유지" },
    { "index": 3, "kind": "DELOAD", "label_ko": "디로드",   "start_week": 9,  "end_week": 9,
      "start_date": "2026-11-15", "end_date": "2026-11-21",
      "kcal_modifier_pct": 10, "volume_modifier_pct": -40,
      "expected_weight_kg": 75.6, "expected_smm_kg": 33.9, "expected_bfm_kg": 15.5,
      "focus_ko": "회복 · 유지 칼로리" },
    { "index": 4, "kind": "MAIN",   "label_ko": "본 감량기 2", "start_week": 10, "end_week": 18,
      "start_date": "2026-11-22", "end_date": "2027-01-23",
      "kcal_modifier_pct": 0, "volume_modifier_pct": 0,
      "expected_weight_kg": 72.6, "expected_smm_kg": 34.8, "expected_bfm_kg": 12.6,
      "focus_ko": "정체 구간 대응" },
    { "index": 5, "kind": "PEAK",   "label_ko": "마무리",   "start_week": 19, "end_week": 20,
      "start_date": "2027-01-24", "end_date": "2027-02-07",
      "kcal_modifier_pct": -5, "volume_modifier_pct": -10,
      "expected_weight_kg": 72.0, "expected_smm_kg": 35.0, "expected_bfm_kg": 12.0,
      "focus_ko": "목표 도달 · 유지 전환 준비" }
  ],

  "workout_plan": {
    "split_template_id": "UPPER_LOWER_4D",
    "split_label_ko": "상하체 4분할",
    "sessions_per_week": 4,
    "weekly_schedule": {
      "MON": "UPPER", "TUE": "LOWER", "WED": "CARDIO",
      "THU": "UPPER", "FRI": "LOWER", "SAT": "CARDIO", "SUN": "REST"
    },
    "progression_model": "DOUBLE_PROGRESSION",
    "weekly_sets_by_muscle": {
      "chest": 12, "back": 14, "quads": 12, "hams": 10, "glutes": 10,
      "delts": 12, "biceps": 8, "triceps": 8, "core": 8, "calves": 6
    },
    "weak_point_focus": ["좌측 팔 단측 보강 (비대칭 6.96%)"],
    "estimated_weekly_minutes": 290,

    "sessions": [
      {
        "id": "s_upper_a",
        "day_of_week": "MON",
        "kind": "UPPER",
        "label_ko": "상체 A",
        "order_in_week": 1,
        "warmup_ko": "로잉머신 5분 + 밴드 풀어파트 2x15 + 숄더 디슬로케이트 1x10",
        "estimated_minutes": 62,
        "target_rpe_avg": 7.8,
        "exercises": [
          { "slot": 1, "exercise_id": "ex_incline_db_press", "name_ko": "인클라인 덤벨 프레스", "name_en": "Incline DB Press",
            "role": "PRIMARY_COMPOUND", "primary_muscle": "chest", "secondary_muscles": ["delts","triceps"],
            "equipment": "덤벨", "sets": 4, "rep_min": 8, "rep_max": 10, "rpe_target": 8, "rest_sec": 120,
            "tempo": "3-0-1-0", "load_kg": 22.5, "load_pct_1rm": null,
            "progression_rule_ko": "4세트 모두 10회 달성 시 다음 주 좌우 +2.5kg",
            "substitutions": [{ "exercise_id": "ex_machine_chest_press", "name_ko": "머신 체스트 프레스", "reason_ko": "어깨 통증 시" }],
            "note_ko": "좌측 어깨 충돌증후군 고려 — 바벨 대신 덤벨 중립 그립" },
          { "slot": 2, "exercise_id": "ex_chest_supported_row", "name_ko": "체스트 서포티드 로우", "name_en": "Chest Supported Row",
            "role": "PRIMARY_COMPOUND", "primary_muscle": "back", "secondary_muscles": ["biceps"],
            "equipment": "머신", "sets": 4, "rep_min": 10, "rep_max": 12, "rpe_target": 8, "rest_sec": 105,
            "tempo": "2-1-1-0", "load_kg": 45.0, "load_pct_1rm": null,
            "progression_rule_ko": "전 세트 12회 시 +5kg", "substitutions": [] },
          { "slot": 3, "exercise_id": "ex_lat_pulldown", "name_ko": "랫 풀다운", "name_en": "Lat Pulldown",
            "role": "SECONDARY_COMPOUND", "primary_muscle": "back", "secondary_muscles": ["biceps"],
            "equipment": "케이블", "sets": 3, "rep_min": 10, "rep_max": 12, "rpe_target": 8, "rest_sec": 90,
            "tempo": "2-0-2-0", "load_kg": 50.0, "load_pct_1rm": null,
            "progression_rule_ko": "전 세트 12회 시 +5kg", "substitutions": [] },
          { "slot": 4, "exercise_id": "ex_db_lateral_raise_unilateral", "name_ko": "원암 사이드 레터럴 레이즈", "name_en": "Single-arm Lateral Raise",
            "role": "ISOLATION", "primary_muscle": "delts", "secondary_muscles": [],
            "equipment": "덤벨", "sets": 3, "rep_min": 12, "rep_max": 15, "rpe_target": 8.5, "rest_sec": 60,
            "tempo": "2-0-1-1", "load_kg": 7.5, "load_pct_1rm": null,
            "progression_rule_ko": "좌측을 먼저 수행하고 우측은 좌측 횟수에 맞춤 (비대칭 보정)",
            "substitutions": [], "note_ko": "약점 보강 슬롯" },
          { "slot": 5, "exercise_id": "ex_cable_triceps_pushdown", "name_ko": "케이블 푸시다운", "name_en": "Cable Pushdown",
            "role": "ISOLATION", "primary_muscle": "triceps", "secondary_muscles": [],
            "equipment": "케이블", "sets": 3, "rep_min": 12, "rep_max": 15, "rpe_target": 8.5, "rest_sec": 60,
            "tempo": "2-0-1-0", "load_kg": 25.0, "load_pct_1rm": null,
            "progression_rule_ko": "전 세트 15회 시 +2.5kg", "substitutions": [] },
          { "slot": 6, "exercise_id": "ex_incline_db_curl", "name_ko": "인클라인 덤벨 컬", "name_en": "Incline DB Curl",
            "role": "ISOLATION", "primary_muscle": "biceps", "secondary_muscles": [],
            "equipment": "덤벨", "sets": 3, "rep_min": 10, "rep_max": 12, "rpe_target": 8.5, "rest_sec": 60,
            "tempo": "3-0-1-0", "load_kg": 12.5, "load_pct_1rm": null,
            "progression_rule_ko": "전 세트 12회 시 +1.25kg(양손)", "substitutions": [] }
        ],
        "finisher_ko": "플랭크 3x40초"
      }
    ],

    "cardio_prescription": {
      "modality": "TREADMILL_INCLINE",
      "sessions_per_week": 2,
      "minutes_per_session": 25,
      "intensity_ko": "Zone2",
      "target_hr_pct": [60, 70],
      "placement_ko": "비운동일(수·토) 또는 근력 후",
      "est_kcal_per_session": 210
    }
  },

  "diet_plan": {
    "bmr_kcal": 1663,
    "bmr_source": "INBODY",
    "activity_factor": 1.45,
    "exercise_kcal_per_week": 1860,
    "tdee_kcal": 2677,
    "daily_delta_kcal": -330,
    "target_kcal": 2350,
    "training_day_kcal": 2540,
    "rest_day_kcal": 2100,
    "protein_g": 144,
    "fat_g": 62,
    "carb_g": 292,
    "protein_g_per_kg": 2.0,
    "fiber_g_min": 33,
    "water_ml": 3100,
    "sodium_mg_max": 2300,
    "kcal_floor": 1829,
    "meal_count": 4,
    "free_meals_per_week": 1,
    "refeed_ko": "9주차 디로드 주간은 유지 칼로리(2670kcal)로 상향",

    "meal_template": [
      { "slot": "BREAKFAST", "label_ko": "아침", "time_hint": "07:30",
        "kcal": 588, "protein_g": 36, "fat_g": 16, "carb_g": 73, "kcal_share_pct": 25,
        "items": [
          { "food_id": "f_oatmeal", "name_ko": "귀리(건조)", "amount": 70, "unit_ko": "g", "kcal": 266, "protein_g": 9, "fat_g": 5, "carb_g": 45, "is_swappable": true },
          { "food_id": "f_greek_yogurt", "name_ko": "그릭요거트(무가당)", "amount": 150, "unit_ko": "g", "kcal": 146, "protein_g": 15, "fat_g": 7, "carb_g": 7, "is_swappable": true },
          { "food_id": "f_banana", "name_ko": "바나나", "amount": 1, "unit_ko": "개", "kcal": 105, "protein_g": 1, "fat_g": 0, "carb_g": 27, "is_swappable": true },
          { "food_id": "f_whey", "name_ko": "웨이 프로틴", "amount": 1, "unit_ko": "스쿱", "kcal": 120, "protein_g": 24, "fat_g": 2, "carb_g": 3, "is_swappable": false }
        ],
        "swap_options_ko": ["귀리 → 현미밥 150g", "그릭요거트 → 계란 3개"] },

      { "slot": "LUNCH", "label_ko": "점심", "time_hint": "12:30",
        "kcal": 705, "protein_g": 45, "fat_g": 18, "carb_g": 88, "kcal_share_pct": 30,
        "items": [
          { "food_id": "f_brown_rice", "name_ko": "현미밥", "amount": 210, "unit_ko": "g", "kcal": 300, "protein_g": 6, "fat_g": 2, "carb_g": 64, "is_swappable": true },
          { "food_id": "f_chicken_breast", "name_ko": "닭가슴살", "amount": 180, "unit_ko": "g", "kcal": 198, "protein_g": 40, "fat_g": 4, "carb_g": 0, "is_swappable": true },
          { "food_id": "f_kimchi", "name_ko": "배추김치", "amount": 80, "unit_ko": "g", "kcal": 24, "protein_g": 1, "fat_g": 0, "carb_g": 4, "is_swappable": false },
          { "food_id": "f_mixed_veg", "name_ko": "구운 채소", "amount": 200, "unit_ko": "g", "kcal": 90, "protein_g": 4, "fat_g": 1, "carb_g": 16, "is_swappable": true },
          { "food_id": "f_olive_oil", "name_ko": "올리브유", "amount": 10, "unit_ko": "g", "kcal": 90, "protein_g": 0, "fat_g": 10, "carb_g": 0, "is_swappable": true }
        ],
        "swap_options_ko": ["닭가슴살 → 연어 150g (지방 +8g, 탄수 −20g 조정)", "구내식당: 백반 + 밥 2/3공기 + 단백 반찬 2배"] },

      { "slot": "DINNER", "label_ko": "저녁", "time_hint": "19:00",
        "kcal": 705, "protein_g": 45, "fat_g": 22, "carb_g": 79, "kcal_share_pct": 30,
        "items": [
          { "food_id": "f_sweet_potato", "name_ko": "고구마", "amount": 250, "unit_ko": "g", "kcal": 215, "protein_g": 4, "fat_g": 0, "carb_g": 50, "is_swappable": true },
          { "food_id": "f_beef_lean", "name_ko": "소고기 우둔살", "amount": 150, "unit_ko": "g", "kcal": 250, "protein_g": 33, "fat_g": 12, "carb_g": 0, "is_swappable": true },
          { "food_id": "f_egg", "name_ko": "계란", "amount": 2, "unit_ko": "개", "kcal": 144, "protein_g": 12, "fat_g": 10, "carb_g": 1, "is_swappable": true },
          { "food_id": "f_salad", "name_ko": "샐러드 채소", "amount": 150, "unit_ko": "g", "kcal": 30, "protein_g": 2, "fat_g": 0, "carb_g": 5, "is_swappable": false }
        ],
        "swap_options_ko": ["소고기 → 돼지 안심 160g", "외식: 국밥 + 공깃밥 1/2 + 수육 추가"] },

      { "slot": "POST_WORKOUT", "label_ko": "운동 후", "time_hint": "21:00",
        "kcal": 352, "protein_g": 18, "fat_g": 6, "carb_g": 52, "kcal_share_pct": 15,
        "items": [
          { "food_id": "f_whey", "name_ko": "웨이 프로틴", "amount": 1, "unit_ko": "스쿱", "kcal": 120, "protein_g": 24, "fat_g": 2, "carb_g": 3, "is_swappable": false },
          { "food_id": "f_rice_cake", "name_ko": "떡(가래떡)", "amount": 100, "unit_ko": "g", "kcal": 210, "protein_g": 4, "fat_g": 0, "carb_g": 47, "is_swappable": true }
        ],
        "swap_options_ko": ["비운동일에는 이 끼니 생략 → rest_day_kcal 적용"] }
    ],

    "supplements": [
      { "name_ko": "크레아틴 모노하이드레이트", "dose_ko": "5g", "timing_ko": "매일 아무 때나" },
      { "name_ko": "비타민 D", "dose_ko": "2000IU", "timing_ko": "식후" },
      { "name_ko": "오메가3", "dose_ko": "1~2g", "timing_ko": "식후" }
    ],

    "grocery_list_ko": ["귀리 1kg", "그릭요거트 1kg", "닭가슴살 2kg", "소고기 우둔살 1kg",
                        "계란 30구", "현미 2kg", "고구마 2kg", "샐러드 채소 1kg", "올리브유", "웨이 프로틴"]
  },

  "assumptions": [
    "기초대사량은 인바디 측정값(1663kcal)을 사용했습니다.",
    "활동계수 1.45는 사무직 + 주 6일 활동 기준 추정치입니다.",
    "지방 1kg = 7700kcal 로 환산했습니다.",
    "초급자 리컴프 가정으로 월 0.6kg 증근 상한을 적용했습니다.",
    "이 플랜은 의료적 조언이 아니며, 기저질환이 있으면 전문가와 상의하세요."
  ],
  "warnings": [
    { "code": "W-SCAN-01", "severity": "info", "message_ko": "좌우 팔 근육 비대칭 6.9% — 단측 운동을 배치했습니다." }
  ],
  "adjustment_rule_ids": ["R-01","R-02","R-03","R-04","R-05","R-06","R-07","R-08"],
  "superseded_by": null
}
```

### 3.5 ProgressLog

```json
{
  "id": "log_20260921",
  "date": "2026-09-21",
  "plan_id": "plan_20260919_01_MODERATE_r1",
  "weight_kg": 77.8,
  "kcal_actual": 2410,
  "protein_g_actual": 138,
  "diet_adherence_pct": 97,
  "workout_done": "DONE",
  "session_id": "s_upper_a",
  "set_logs": [
    { "exercise_id": "ex_incline_db_press", "set_index": 1, "reps": 10, "load_kg": 22.5, "rpe": 7.5, "is_failure": false },
    { "exercise_id": "ex_incline_db_press", "set_index": 2, "reps": 10, "load_kg": 22.5, "rpe": 8.0, "is_failure": false },
    { "exercise_id": "ex_incline_db_press", "set_index": 3, "reps": 9,  "load_kg": 22.5, "rpe": 8.5, "is_failure": false },
    { "exercise_id": "ex_incline_db_press", "set_index": 4, "reps": 8,  "load_kg": 22.5, "rpe": 9.0, "is_failure": true }
  ],
  "cardio_minutes": 0,
  "steps": 9120,
  "sleep_hours": 6.5,
  "energy_1_5": 4,
  "soreness_1_5": 2,
  "note_ko": "어깨 통증 없음"
}
```

### 3.6 WeeklyCheckpoint

```json
{
  "id": "ckpt_goal_20260919_01_w03",
  "goal_id": "goal_20260919_01",
  "plan_id": "plan_20260919_01_MODERATE_r1",
  "week_index": 3,
  "period_start": "2026-10-04",
  "period_end": "2026-10-10",
  "scan_id": null,
  "weight_ma7_kg": 77.5,
  "weight_trend_kg_per_week": -0.12,
  "planned_weight_kg": 77.1,
  "weight_gap_kg": 0.4,
  "bfm_kg": null,
  "smm_kg": null,
  "diet_adherence_pct": 91,
  "workout_adherence_pct": 100,
  "avg_sleep_hours": 6.3,
  "avg_steps": 8740,
  "volume_load_kg": 41250,
  "strength_index_delta_pct": 2.8,
  "progress_ratio": 0.56,
  "verdict": "BEHIND",
  "triggered_rule_ids": [],
  "applied_adjustments": [],
  "message_ko": "근력은 오르는데 체중 변화가 계획보다 느립니다. 다음 주도 같으면 칼로리를 조정합니다."
}
```

### 3.7 AdjustmentRule (시드 1건)

```json
{
  "id": "R-01",
  "label_ko": "정체 시 칼로리 하향",
  "priority": 10,
  "applies_to_intensity": ["EASY", "MODERATE", "HARD"],
  "condition": { "all": [
    { "metric": "progress_ratio",     "op": "<",  "value": 0.4, "window_weeks": 2 },
    { "metric": "diet_adherence_pct", "op": ">=", "value": 85,  "window_weeks": 2 }
  ]},
  "action": "KCAL_DELTA",
  "magnitude": -5,
  "unit": "pct",
  "clamp": { "min": -150, "max": 0 },
  "cooldown_days": 14,
  "requires_user_confirm": false,
  "message_ko": "2주간 준수는 잘 했는데 변화가 느려 일일 섭취를 {delta}kcal 낮췄습니다."
}
```

---

## 4. localStorage 레이아웃 (프로토타입)

### 4.1 키 규약

모든 키는 `mybody:v<SCHEMA_VERSION>:<domain>[:<id>]` 형식. 버전을 키에 넣어 구버전 데이터와 충돌 없이 공존/마이그레이션한다.

| 키 | 값 타입 | 크기 감각 | 비고 |
|---|---|---|---|
| `mybody:schema_version` | `"1"` | 1B | **버전 접두사 없음** (부트스트랩 키) |
| `mybody:v1:profile` | `UserProfile` | ~1KB | 단일 객체 |
| `mybody:v1:settings` | `AppSettings` | ~0.5KB | 테마, 단위, ID배지 표시 on/off, 디버그 |
| `mybody:v1:scan_index` | `{id, measured_at, weight_kg, smm_kg, bfm_kg, pbf_pct, is_baseline}[]` | ~2KB | 목록 렌더링용 요약 — 상세를 안 읽고 그림 |
| `mybody:v1:scan:<scan_id>` | `InBodyScan` | ~4KB | 1건 1키 |
| `mybody:v1:scan_image:<scan_id>` | `{mime, width, height, data_url}` | **0.3~3MB** | ⚠️ 용량 주범, 4.3 참조 |
| `mybody:v1:goal_index` | `{id, target_date, status}[]` | ~0.3KB | |
| `mybody:v1:goal:<goal_id>` | `Goal` | ~1KB | |
| `mybody:v1:active_goal_id` | `string` | – | |
| `mybody:v1:plan_index` | `{id, goal_id, intensity, revision, status, generated_at}[]` | ~1KB | 강도 3안이 모두 등재됨 |
| `mybody:v1:plan:<plan_id>` | `Plan` | ~25KB | 가장 큰 일반 레코드 |
| `mybody:v1:active_plan_id` | `string` | – | |
| `mybody:v1:logs:<YYYY-MM>` | `{ [date]: ProgressLog }` | ~30KB/월 | **월 단위 버킷** — 일별 키는 금지(키 폭발) |
| `mybody:v1:log_months` | `string[]` (`["2026-09","2026-10"]`) | ~0.1KB | 버킷 인덱스 |
| `mybody:v1:checkpoints:<goal_id>` | `WeeklyCheckpoint[]` | ~10KB | 목표당 최대 ~52건 |
| `mybody:v1:feedback` | `FeedbackNote[]` | ~5KB | 프로토타입 검증 피드백 |
| `mybody:v1:ui_state` | `{last_page_uid, open_accordions[], badge_visible: bool}` | ~0.3KB | 새로고침 복원 |
| `mybody:v1:__meta` | `{created_at, last_opened_at, seeded: bool, app_build: "proto-0.1.0"}` | ~0.2KB | |

**저장하지 않는 것:** `ExerciseCatalogItem[]`, `FoodCatalogItem[]`, `IntensityLevel[]`, `AdjustmentRule[]` — 이들은 **JS 파일에 시드 상수로 하드코딩**한다. 앱 업데이트 시 자동으로 갱신되어야 하는 참조 데이터이므로 localStorage에 넣으면 오히려 낡은 값이 고착된다.

### 4.2 접근 계층 (필수 패턴)

```js
const DB = {
  V: 1,
  key: (domain, id) => `mybody:v${DB.V}:${domain}` + (id ? `:${id}` : ''),
  get(domain, id, fallback = null) {
    try { const raw = localStorage.getItem(DB.key(domain, id));
          return raw == null ? fallback : JSON.parse(raw); }
    catch (e) { console.warn('[DB.get]', domain, id, e); return fallback; }
  },
  set(domain, id, value) {
    try { localStorage.setItem(DB.key(domain, id), JSON.stringify(value)); return true; }
    catch (e) {
      if (e.name === 'QuotaExceededError') { showModal('M-07', { reason: 'QUOTA' }); }
      return false;
    }
  },
  remove(domain, id) { localStorage.removeItem(DB.key(domain, id)); },
  wipe() { Object.keys(localStorage).filter(k => k.startsWith('mybody:')).forEach(k => localStorage.removeItem(k)); }
};
```

모든 읽기는 반드시 try/catch + fallback. `file://` + 시크릿 창에서 `localStorage` 접근 자체가 throw 할 수 있으므로, 실패 시 **메모리 내 Map 으로 자동 강등(degraded mode)** 하고 상단에 `"저장 불가 — 새로고침하면 데이터가 사라집니다"` 배너(`C-99`)를 띄운다.

### 4.3 이미지 용량 정책

- 업로드 즉시 `<canvas>` 로 **장변 1280px, JPEG q=0.72** 리사이즈 후 dataURL 저장.
- 예상 크기 300~600KB. localStorage 총량이 보통 5~10MB이므로 **사진은 최대 3장까지만** 보관하고, 초과 시 오래된 것부터 `scan_image:*` 만 삭제(스캔 수치는 유지) — 삭제 전 확인 모달 `M-07`.
- `scan_index` 에 `has_image: bool` 을 두어 썸네일 없는 항목을 구분.
- 백엔드/IndexedDB 전환 시 이 정책은 통째로 폐기된다 (5절).

### 4.4 버전 관리 & 마이그레이션

```js
const MIGRATIONS = {
  // from -> to. 순차 적용. 각 함수는 순수하게 "키를 읽어 새 키를 쓴다".
  1: null,                       // 최초 버전
  // 2: (log) => { ... }         // 예: v1 scan.muscle_fat.smm_kg → v2 scan.smm_kg 평탄화
};

function bootstrapDb() {
  const stored = parseInt(localStorage.getItem('mybody:schema_version') || '0', 10);
  if (stored === 0) { seedIfEmpty(); localStorage.setItem('mybody:schema_version', String(DB.V)); return; }
  if (stored > DB.V)  { showModal('M-07', { reason: 'FUTURE_VERSION' }); return; }  // 다운그레이드 방지
  for (let v = stored; v < DB.V; v++) {
    backupBeforeMigrate(v);       // mybody:backup:v{v}:<timestamp> 에 전체 덤프 1부
    MIGRATIONS[v + 1]?.(migrationLogger);
    localStorage.setItem('mybody:schema_version', String(v + 1));
  }
}
```

규칙:
1. **필드는 삭제하지 않고 deprecate** 한다. 제거는 메이저 버전에서만.
2. 새 필드는 **항상 기본값을 갖는 optional** 로 추가 → 마이그레이션 불필요한 변경이 대부분이 되게 한다.
3. 모든 레코드에 `schema_version` 을 **넣지 않는다** (중복). 대신 전역 `mybody:schema_version` 1개로 관리.
4. 마이그레이션 직전 전체 덤프를 `mybody:backup:...` 에 1부 남기고, 성공 후 다음 실행에서 정리.
5. `P-09` 설정 화면에 **전체 JSON 내보내기(`B-903`) / 가져오기(`B-904`) / 초기화(`B-905`)** 를 반드시 제공. 프로토타입 단계에서 스키마가 바뀌면 그냥 내보내기 → 초기화 → 가져오기로 복구한다.
6. 내보내기 포맷:
```json
{ "app": "mybody", "schema_version": 1, "exported_at": "2026-09-19T22:00:00+09:00",
  "data": { "profile": {...}, "scans": [...], "goals": [...], "plans": [...],
            "logs": {...}, "checkpoints": {...}, "feedback": [...] } }
```
(이미지는 `include_images` 옵션이 켜진 경우에만 포함 — 파일이 수 MB가 됨)

---

## 5. 나중에 실제 백엔드가 붙으면 달라지는 것

### 5.1 그대로 남는 것

| 항목 | 이유 |
|---|---|
| 모든 엔티티 필드명·타입·단위 | 스키마를 그대로 테이블/컬럼으로 승격. `InBodyScan` → `inbody_scans`, 중첩 블록은 JSONB 또는 평탄화 |
| enum 값 | DB enum 또는 CHECK 제약으로 승격 |
| 파생 수식 (2절 전체) | 순수 함수이므로 클라이언트/서버 어디서 돌려도 동일. `calc.js` 를 그대로 서버로 이식 |
| `IntensityLevel`, `AdjustmentRule`, 카탈로그 시드 | 시드 테이블 + 마이그레이션 스크립트로 전환 |
| UI ID 체계 (`P-`/`M-`/`B-`) | 그대로 유지 — 이후에도 피드백·버그 트래킹 주소로 계속 쓴다 |
| Plan의 스냅샷 원칙 (생성 시점 값 저장) | 오히려 서버에서 더 중요해짐 (감사 추적) |

### 5.2 옮겨가는 것

| 지금 (프로토타입) | 나중 (백엔드) |
|---|---|
| `localStorage` 키 네임스페이스 | PostgreSQL 테이블 + `user_id` 외래키. **모든 엔티티에 `user_id` 컬럼 추가** — 지금 단일 사용자라서 없는 유일한 필드 |
| `scan_index`, `plan_index`, `log_months` (수동 인덱스) | **전부 삭제.** DB 인덱스 + `SELECT` 로 대체 |
| `scan_image:<id>` dataURL | 오브젝트 스토리지(S3/R2) + `image_url`, `image_key`, `image_bytes`, `image_sha256` 필드. 4.3의 3장 제한·강제 리사이즈 정책 폐기 |
| `ocr.engine: "stub-v0"` | 실제 OCR 파이프라인(Vision API / 전용 모델). `OcrFieldResult` 구조는 **그대로 유지** — 스텁을 이 구조에 맞춰 만든 이유가 이것 |
| 플랜 생성 로직 (브라우저 JS) | 서버 사이드 `POST /goals/{id}/plans?intensity=MODERATE`. 계산 함수는 동일, 실행 위치만 이동 |
| `AdjustmentRule` 을 앱 열었을 때 평가 | 주간 크론 잡 + 푸시 알림 |
| 내보내기/가져오기 JSON | 계정 기반 동기화. 내보내기는 GDPR형 데이터 export 기능으로 잔존 |
| `mybody:schema_version` + JS 마이그레이션 | DB 마이그레이션 도구 + API 버저닝(`/v1/`). 클라이언트 캐시에만 로컬 버전 유지 |
| `FeedbackNote` (localStorage) | 검증 끝나면 **삭제**. 또는 이슈 트래커 연동 |
| 단일 `active_plan_id` | `plans.status = 'ACTIVE'` + `UNIQUE (user_id) WHERE status='ACTIVE'` 부분 유니크 인덱스 |

### 5.3 백엔드 전환 시 새로 필요해지는 것

- `user_id`, `created_by`, `deleted_at` (소프트 삭제), `updated_at` 트리거
- 낙관적 동시성 제어: 각 레코드에 `version: int` 또는 `etag`
- 멱등성: 플랜 생성 요청에 `idempotency_key`
- 동기화 충돌 해결: `ProgressLog` 는 `(user_id, date)` 유니크 + **last-write-wins**, `Plan` 은 **서버 승리(클라이언트는 읽기 전용)**
- 오프라인 큐: 기록은 오프라인에서 쌓고 온라인 복귀 시 배치 업로드 → `ProgressLog` 에 `synced_at`, `client_id` 추가
- 개인정보: 인바디 사진은 민감 정보. 저장 시 암호화 + 만료 정책(예: 원본 사진 90일 후 삭제, 수치만 영구 보관) 필요

### 5.4 지금 미리 지켜둬야 전환이 싸지는 규칙

1. **DOM에서 직접 `localStorage` 를 부르지 않는다.** 반드시 `DB` / `Repo` 계층 경유 → 나중에 `Repo` 만 `fetch` 로 갈아끼우면 끝.
2. **계산 로직을 렌더 코드와 분리** (`calc.js` / `planner.js` / `render.js`). 계산 파일은 DOM·localStorage를 전혀 모르게 유지.
3. **모든 ID를 서버에서 다시 발급할 수 있게** 참조는 ID로만 하고, 객체를 중첩 복사해 넣지 않는다 (예외: `Plan` 의 스냅샷은 의도된 복사).
4. **시간은 항상 ISO-8601 + 오프셋**으로 저장. `new Date().toString()` 금지.
5. **부동소수 반올림은 표시 단계에서만.** 저장값은 원본 정밀도 유지.