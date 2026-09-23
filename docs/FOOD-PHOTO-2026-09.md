# 사진 음식 인식 · 탄단지 분석 — 도입 조사 (2026-09-23)

> 아직 구현하지 않았습니다. 이 문서는 결정용입니다. 먼저 쓴 분석은 `docs/FOOD-PLAN.md` (그 결론 "이름은 모델, 양은 사람" 은 유지·강화).
> 보고서(화면): https://claude.ai/artifact/BFrci3LZ88iUZTzXNwu1mP — 3절. 서버 유지비 계산기는 2절.

## 권고

이렇게 간다: 기존 서버 프록시(server/ocr.js와 같은 패턴)에 /api/food-photo 를 하나 더 만들고, 모델은 지금 인바디 판독 기본값과 같은 Claude Sonnet 5 로 시작한다. 모델에게는 음식 이름 후보와 portion_word(반/1인분/1.5/2/모름)만 받고 kcal·탄단지 칸은 아예 두지 않는다. 숫자는 전부 내장 한식표(432개)에서 꺼내고, 이름과 양은 검수 화면에서 사람이 확정한다. 비용은 결정 요인이 아니다. 사진 1장에 약 20~23원이고, 하루 2장이면 사용자당 월 약 1,200~1,350원, 10명 전체로 월 약 1.3만원이다. Haiku 4.5 는 반값(장당 약 10원)이지만 쓰지 않는다. 식사 사진에서 Sonnet 급보다 확연히 나빴다는 2026 연구가 있고(에너지 R² 0.23 vs 0.60, 단 포장식품 데이터), 아낄 수 있는 돈이 10명 기준 월 6천원 남짓이다. 주말 30끼 측정에서 이름 정확도 차이가 5%p 이내로 나오면 그때 다시 본다. Opus 5/5.5 는 과잉이라 안 쓴다. Opus 5.5 는 현재 코드의 강제 tool_choice(server/ocr.js:428)에 400 오류를 낸다는 문제도 있다. 오픈소스 자체 호스팅은 지금 안 한다. 이유는 셋이다. (1) 한식 인식 오픈소스는 2026-09에도 없다. GitHub 'kfood' 최고가 14★이고 2016년에 멈췄다. (2) 범용 오픈 VLM 중 가장 나은 Qwen3.5-4B 도 저울 계량 벤치에서 Claude Sonnet 5 보다 낮았다(F1 0.61 vs 0.695). 가볍다고 거론되던 MiniCPM-V 4.6·Gemma 4 E4B 는 하위권이었다. (3) 오라클 무료 VM이 2026-06-15부터 2코어/12GB로 줄어 사진당 분 단위 대기가 예상된다[추정]. 절감액이 연 십여만원이라 운영 부담을 못 넘는다. 온디바이스도 안 한다. 쓸 만한 무료 경로(iOS 27 Foundation Models, Android ML Kit Prompt API)는 최신 기종에서만 되고 한식 정확도 실측이 0건이다. 모든 연구가 같은 결론이다: 모델은 음식 이름은 대체로 맞히고 양은 틀린다. 실측 200끼 벤치에서는 '음식별 통상 1인분'만 쓰는 기준선(MAE 35.4g)이 Sonnet 5 의 무게 추정(39.7g)보다 정확했다. 그래서 FOOD-PLAN 의 '이름은 모델, 양은 사람' 구조는 그대로 유지하고 오히려 강화한다. 달라지는 점은 하나다. 비슷한 요리를 가르는 세분류(김치찌개/부대찌개/김치찜)에서는 이름도 틀리므로 이름도 사람이 확정한다. 사진 기능은 코드를 쓰기 전에 주말 30끼 저울 측정이라는 게이트를 먼저 통과해야 켠다.

## 사진 1장 비용 (1,400원/$)

| 모델 | $/MTok 입·출 | 토큰 입·출 | 1장 | 메모 |
|---|---|---|---|---|
| Claude Sonnet 5 — 기본 가정 (채택) | 2/10 | 2536/900 | 19.7원 | 이미지 1,036 + 시스템 1,200 + 맥락 300. 공식 단가 1차 확인: $2/$10 도입가가 정식 단가로 확정됐고 9/1 인상은 취소됨. 출력 600토큰이면 $0.01107(15.5원) |
| Claude Sonnet 5 — 보수 가정 | 2/10 | 3524/900 | 22.5원 | 이미지 1,100 + 텍스트 1,500×1.3(4.7 이후 신형 토크나이저 +30%, 공식) + 강제 tool-use 시스템 오버헤드 474. thinking 토큰은 제외했고, 켜지면 더 오름[미검증] |
| Claude Haiku 4.5 — 기본 가정 | 1/5 | 2536/900 | 9.9원 | 구형 토크나이저, 표준 해상도 등급. 출력 600이면 $0.00554(7.8원). 캐싱 최소 4,096토큰이라 이 프롬프트로는 캐시 불가 |
| Claude Haiku 4.5 — 보수 가정 | 1/5 | 3188/900 | 10.8원 | 이미지 1,100 + 텍스트 1,500 + 강제 tool-use 오버헤드 588 |
| Claude Opus 5.5 — 기본 가정 | 4/20 | 2536/900 | 39.4원 | 공식 $4/$20(과제 전제의 'Opus 5.x $5/$25'와 다름). 보수 가정 $0.03134(43.9원). 강제 tool_choice 불가, thinking 끌 수 없음 → 과잉, 채택 안 함 |
| Claude Opus 5 — 기본 가정 | 5/25 | 2536/900 | 49.3원 | 보수 가정 $0.03978(55.7원). 이름+portion_word 과제에 과잉 |
| (비교) gpt-5.6 Terra | 2/12 | 2536/900 | 22.2원 | [미검증] openai.com 차단, 검색 요약. gpt-5-mini 의 후계인데 Sonnet 5 보다 비쌈. gpt-5-mini/nano 는 2026-12-11 API 종료 예정 |
| (비교) gpt-5.6 Luna | 0.2/1.2 | 2536/900 | 2.2원 | [미검증] 이미지 토큰 산식 미확정. 한식 품질 미측정 |
| (비교) Gemini 3.1 Flash-Lite | 0.25/1.5 | 2536/900 | 2.8원 | [미검증] ai.google.dev 차단. Gemini 3 은 이미지가 media_resolution 고정값(HIGH 1,120). 무료 등급 데이터는 제품 개선에 쓰일 수 있어 식사 사진에는 부적합 |

## 사용자 1명당 월

| 모델 | 하루 장수 | 월 |
|---|---|---|
| Claude Sonnet 5 (기본 가정, 채택) | 1 | 591원 |
| Claude Sonnet 5 (기본 가정, 채택) | 2 | 1,182원 |
| Claude Sonnet 5 (기본 가정, 채택) | 3 | 1,773원 |
| Claude Sonnet 5 (보수 가정) | 1 | 674원 |
| Claude Sonnet 5 (보수 가정) | 2 | 1,348원 |
| Claude Sonnet 5 (보수 가정) | 3 | 2,022원 |
| Claude Haiku 4.5 (기본 가정) | 1 | 296원 |
| Claude Haiku 4.5 (기본 가정) | 2 | 591원 |
| Claude Haiku 4.5 (기본 가정) | 3 | 887원 |
| Claude Opus 5.5 (기본 가정) | 1 | 1,182원 |
| Claude Opus 5.5 (기본 가정) | 2 | 2,364원 |
| Claude Opus 5.5 (기본 가정) | 3 | 3,546원 |
| Claude Opus 5 (기본 가정) | 1 | 1,478원 |
| Claude Opus 5 (기본 가정) | 2 | 2,955원 |
| Claude Opus 5 (기본 가정) | 3 | 4,433원 |

## 파이프라인

파이프라인(구현 전 설계, 기존 인바디 판독 코드를 재사용)

1) 폰에서 준비: 장변 1024px로 리사이즈한다(1024×768). Canvas 에 다시 그려 EXIF(GPS·기기·시각)를 통째로 지운다. 촬영 시각만 따로 읽어 기록에 넣는다. 원본은 어디에도 저장하지 않고 기기에 썸네일만 남긴다. 리사이즈는 비용 문제이기도 하다. Sonnet 5·Opus 5/5.5 는 고해상도 등급(장변 2576px, 최대 4,784토큰)이라 휴대폰 원본을 그대로 보내면 이미지 토큰이 약 4.6배가 된다(공식 문서 1차 확인).

2) 서버 프록시 /api/food-photo: server/ocr.js 의 키 처리·오류 설명 로직을 재사용한다. 요청 본문과 이미지는 에러 로그를 포함해 절대 로깅하지 않는다. 한도는 인바디 판독과 카운터를 분리한다. 기존 판독 한도(server/server.js:159 OCR_PER_DAY=10, :250 OCR_PER_DAY_TOTAL=250, SQLite ocr_usage 테이블)와 같은 구조로 food_usage 를 두고, 사용자당 하루 6장, 서버 전체 하루 40장으로 한다. 기존 교훈대로 실제로 판독에 성공했을 때만 센다. Anthropic 콘솔에는 음식 전용 워크스페이스를 만들고 월 지출 한도 $20(약 2.8만원)를 건다. 서버 한도 40장/일 × 30일 × 장당 $0.016 ≈ $19 이므로 최악의 경우도 이 안에서 멈춘다.

3) 모델 호출: Claude Sonnet 5, tool-use 강제(tool_choice type 'tool'), temperature 0. 스키마는 photo_quality(good/poor/unusable), dishes[{name_ko, alt_names(최대 2개 후보), confidence(high/medium/low), portion_word(반/1인분/1.5/2/모름), count(셀 수 있는 것만, 없으면 null), container(밥공기/국그릇/종지/접시/도시락/불명), basis(container_size/typical_serving/guess)}], unidentifiable[] 이다. kcal·그램·탄단지 필드는 스키마에 없다. 모델이 무게를 말하면 버린다. 시스템 프롬프트(약 1,200토큰)에는 한국 식기 기준표(밥공기 ≈210g 등), '모르면 모른다고 해도 정답'이라는 규칙, 밥·국·반찬을 분리하라는 규칙을 넣는다. 맥락(약 300토큰)은 끼니 시각과 이 사람이 최근 자주 먹은 음식 10개다. thinking 은 명시적으로 끄거나 최소로 둔다. 파라미터를 생략하면 adaptive thinking 이 켜져 출력 토큰이 늘 수 있다는 보고가 있다[미검증, 실호출로 확인]. 모델을 Opus 5.5 로 바꿀 일이 생기면 강제 tool_choice 가 400을 내므로 auto + strict 스키마로 바꿔야 한다.

4) 내장 음식표 매칭(서버 또는 앱): name_ko 와 alt_names 를 fooddb.js 의 이름과 별칭(432개)에 퍼지 검색한다. 방식은 공백·괄호를 정규화한 뒤 자모 단위 편집거리를 쓰고, 별칭은 완전일치를 우선한다. 매칭에 실패하면 억지로 가장 가까운 것을 고르지 않고 '표에 없음 → 검색/직접 입력'으로 넘긴다. 선택 실험으로 432개 이름 목록(약 3,000자, 약 2,000~3,000토큰[추정])을 프롬프트에 넣어 후보 안에서만 고르게 하는 방식도 30끼 측정에서 비교한다. 제3자 사례에서 후보 강제가 정확도를 올렸다(표본 8장이라 약한 근거). 이렇게 하면 시스템 프롬프트가 1,024토큰을 넘어 Sonnet 5 캐싱 대상이 된다. 캐시는 워크스페이스 단위로 공유되고 1시간 TTL 이 있어서, 10명이 점심·저녁에 몰리면 적중할 수 있다.

5) 검수 화면(P20 3단계): 항목마다 이름 1순위 + 후보 2개 + '이건 아니에요·직접 찾기'를 둔다. 양은 반/1인분/1.5/2 프리셋이고 기본은 항상 1인분이다. 모델의 portion_word 는 프리셋 위의 작은 힌트로만 보여준다. confidence low 와 basis guess 는 미선택 상태로 띄우고, 사용자가 건드리기 전엔 저장 버튼이 켜지지 않는다. 국물 요리는 [다 먹음][반][건더기만]을 추가로 묻는다. photo_quality 가 unusable 이면 바로 수동 검색으로 넘어간다. '그냥 검색해서 고르기' 버튼은 1단계부터 항상 보인다.

6) 저장: 기록마다 source:'photo' 를 붙인다(표 검색은 'table', 직접 입력은 'manual'). 모델 원출력(이름·portion_word·confidence)과 사용자가 최종 확정한 값을 같이 남긴다. 이 차이가 나중에 '이름 수정률·양 수정률' 지표가 된다. 주간 달성률에서는 출처별 비율을 보여준다.

토큰 가정: 이미지 1,036토큰. 공식 산식이 이제 ⌈w/28⌉×⌈h/28⌉ 라서 1024×768 = 37×28 = 1,036 이다. 과제 전제의 w×h/750 근사(1,049)는 현행 문서에서 빠졌다. 여기에 시스템 1,200, 맥락 300, 출력 600~900토큰을 더한다.

## 정확도 — 화면에서 약속할 수 있는 것

화면에서 약속할 수 있는 것은 이 한 가지다: '사진은 음식 이름을 제안합니다. 이름과 양은 확인한 뒤 저장됩니다.' 칼로리 정확도에 대한 약속은 사진 기능을 켜도 검색 기록(0단계)과 같다. 양은 사람이 프리셋으로 고르기 때문에 사진이 정확도를 더하지 않는다. 사진이 개선하는 것은 입력 속도다. '정확도 90%', '약 520kcal(±130)', 기존 P20 문구의 '평균 오차 24%'는 쓰지 않는다. 24%는 원문을 아무도 못 연 수치라 지운다.

근거 수치
(1) 이름은 대체로 맞힌다. 저울 계량 200끼 벤치에서 Claude Sonnet 5 항목 F1 0.695(3회 평균), GPT-5.5 0.66, GPT-4o 0.748~0.768이다(유럽 식당 음식, 1차 확인). 다만 DiningBench(29모델, 같은 메뉴 안 헷갈리는 요리 포함)는 '세밀한 구분에서 크게 고전'했다. 그래서 김치찌개/부대찌개 같은 구분은 사람이 확정한다.
(2) 양은 모델이 표보다 못하다. 같은 벤치에서 '음식별 통상 1인분 중앙값' 기준선이 MAE 35.4g 으로 Sonnet 5 의 39.7g 보다 낫고, 놓친 항목까지 치면(cpMAE) Sonnet 5 는 69.9g 이다. OmniFood-Bench 도 '이름은 사람 수준, 질량은 파국적 실패'(생채소 MAPE 185%)였다[2차].
(3) 오차는 체계적 과소추정이다. NIH 대사주방 102끼에서 상용 앱 4종이 끼당 252~345kcal(약 33%) 과소, 지방 약 30g 누락이었다(학회 초록). 이 중 양까지 자동 추정한다고 알려진 Cal AI 가 최하위(−345)였다(자동 추정 광고 여부는 [미검증]). 분량이 클수록 과소가 커진다(GPT-4o·Claude 3.5 무게 MAPE 36~37%, 기울기 −0.23~−0.50).
(4) 무게를 알면 오차가 크게 준다. Gemini 2.5 Flash 탄수 MAPE 가 56.6%에서 실측 무게를 주면 20.2%로 떨어진다. 단 우리 프리셋은 저울 무게가 아니라서 개선 폭은 이보다 작다[미검증].
(5) 여러 장 찍기와 프롬프트 튜닝은 효과가 없었다(Sci Rep 2026, 다각도 RMSLE 0.627 vs 단일 0.623, p=0.182). 그러니 투자하지 않는다. '일본 영양사' 페르소나는 추정을 일괄로 낮추는 효과라서, 분량이 크고 원래 과소추정되는 한식에는 역효과일 수 있다. 1순위 실험이 아니다.
(6) 한식은 더 나쁘다. 한국 음식 VLM 벤치마크는 0건이다. 사람(82명)도 김치 분량은 최적 각도에서 52.4%만 맞혔고, 국은 과대추정했다. 직접 학습한 한식 모델은 실사진에서 36% 이하였다.
결론: 한식에 대한 수치는 우리가 직접 재는 30끼 측정이 유일한 근거가 된다. 그 결과도 n=30이라 신뢰구간이 넓으니 화면에 인쇄할 퍼센트로 쓰지 않고, '켤지 말지'를 가르는 데만 쓴다. 화면에는 항목별 편차 등급(conf high/mid/low → '편차 작음/식당마다 다름/편차 큼')만 보여준다.

## 오픈소스

| 이름 | 종류·라이선스 | 한식 | 어디서 | 근거 | 판정 |
|---|---|---|---|---|---|
| [Qwen3.5 Small 4B/9B (Qwen3-VL 후계, 2026-03-02)](https://github.com/Metabolic-Intelligence-Lab/vlm-food-benchmark/blob/main/analysis/outputs/metrics_v2_all.csv) | 범용 VLM · Apache-2.0 [2차, HF 차단] | 한식 평가 0건 | 4B Q4: M1 16GB ○ · 오라클 2코어/12GB 메모리 ○, 속도 분 단위[추정] | 저울 계량 200끼 벤치: 4B F1 0.61·MAE 42.6g, 9B F1 0.649·MAE 40.9g (Sonnet 5 는 0.695/39.7g) | 오픈소스 중 최선. 지금은 안 씀. 프라이버시 요구가 생기면 1순위 후보 |
| [Qwen3-VL 2B~235B](https://github.com/QwenLM/Qwen3-VL) | 범용 VLM · Apache-2.0 (README 1차) | [미검증] | 2B/4B Q4: M1 ○ | OmniFood-Bench 에 8B 포함. 이름은 사람 수준, 양은 파국적 실패[2차] | Qwen3.5 로 대체됨 |
| [MiniCPM-V 4.6 (1.3B) / 4.5 (8B)](https://github.com/OpenBMB/MiniCPM-V) | 소형 VLM · Apache-2.0 (README 1차) | [미검증] | 4.6: CPU gguf 2GB — 오라클 무료 VM에 들어감 | 4.6: F1 0.44~0.48, MAE 60~71g (하위권). 4.5 8B: F1 0.645, MAE 47.2g | 가볍지만 음식 성능이 낮아 탈락 |
| [Gemma 4 (E2B/E4B/12B/26B/31B)](https://github.com/google-deepmind/gemma) | 범용 VLM · Apache-2.0 (2026-04, 2차) | [미검증] | E4B: M1·오라클 메모리 ○ | E4B 벤치 최하위(F1 0.36~0.40, MAE 62~65g), 12B F1 약 0.52 | 탈락 |
| [HyperCLOVAX-SEED-Vision-Instruct-3B (Naver)](https://huggingface.co/naver-hyperclovax/HyperCLOVAX-SEED-Vision-Instruct-3B) | 한국어 특화 VLM · 커스텀 — MAU 1천만 이하 무료, NAVER 경쟁 서비스는 별도 | 한국어 강점, 한식 수치 [미검증] | 3B: M1 ○ | 음식 평가 0건 | 자체 호스팅을 검토할 때만 30끼 측정 후보 |
| [VARCO-VISION-2.0 (NCSOFT 1.7B/14B)](https://huggingface.co/NCSOFT/VARCO-VISION-2.0-14B) | 한국어 특화 VLM · CC BY-NC 4.0 (비상업) | [미검증] | 1.7B: M1 ○ | 없음 | 비상업 라이선스라 안 씀 |
| [InternVL3.5 / Moondream 2 / SmolVLM2](https://github.com/m87-labs/moondream) | 범용·초소형 VLM · Apache/MIT (Moondream 3.x 는 BSL) | [미검증], SmolLM 계열 백본은 한국어 미지원 | 어디서나 | 소형 음식 근거 없음 | 탈락 |
| [Food-R1 (Qwen3-VL-8B + GRPO)](https://github.com/hustvl/Food-R1) | 음식 특화 VLM · Apache-2.0 | 한식 전용 데이터 없음 (Food-101 bibimbap·MM-Food-100K 일부뿐) | 8B, 공식 GGUF 없음 | 공개 후 하루 만에 push 정지(2026-06-04) | 탈락 |
| [FoodLMM · FoodSAM · FoodSeg103](https://github.com/YuehaoYin/FoodLMM) | 음식 MLLM/세그멘테이션 · Apache-2.0 | 없음 | GPU | 2024년에 정지 | 방치, 탈락 |
| [Food-101 분류기 (nateraw/food 등)](https://huggingface.co/nateraw/food) | 101종 분류기 · 다양 | bibimbap 1종 | 브라우저·모바일 | softmax 라 '모르는 음식'을 표현 못 함 | 금지 (FOOD-PLAN §9 유지) |
| [TREX PR #4 — AI Hub #74 로 직접 학습한 YOLOv8n 342종](https://github.com/LeeDongHyun00/TREX/pull/4) | 온디바이스 한식 검출 (3.77MB) · 라이선스 없음 → 재사용 불가 | 342종 | 모바일 약 130ms | 스튜디오 top-1 73%(밥 8종 399장). 실사진 검출 9/25=36%이고, 표에 없는 음식까지 넣으면 9/52≈17% | '직접 학습해도 실사진에선 무너진다'는 실측 근거. 안 함 |
| [GitHub 한식 인식 저장소 전체 (kfood-server 등)](https://github.com/tonyslowdown/kfood-server) | 학부 과제·방치 · 대부분 없음 | ✅ | ✕ | 'kfood' 186건 중 최고 14★(2016-03 정지), '한식 인식' 0건 | 쓸 것 없음 |
| [vlm-food-benchmark (저울 계량 200끼·870항목)](https://github.com/Metabolic-Intelligence-Lab/vlm-food-benchmark) | 벤치마크 (코드 MIT, 데이터 CC BY 4.0) · MIT / CC BY 4.0 | ❌ 유럽 대학 식당 | — | 음식별 1인분 중앙값 기준선 MAE 35.4g 이 모든 모델보다 나음 | '이름은 모델, 양은 표' 구조의 핵심 근거 |

## 상용 API

| 이름 | 가격 | 1장 | 한식 | 근거 | 판정 |
|---|---|---|---|---|---|
| [Claude Sonnet 5](https://platform.claude.com/docs/en/about-claude/pricing) | $2/$10 per MTok (정식 확정, 1차) | 19.7~22.5원 | 미측정 — 30끼 측정 대상 | 저울 벤치 F1 0.695, MAE 39.7g (측정 모델 중 최상위권) | 채택 |
| [Claude Haiku 4.5](https://doi.org/10.3390/nu18122017) | $1/$5 (1차) | 9.9~10.8원 | 미측정 | Claude 3종 비교에서 Sonnet/Opus 보다 확연히 나쁨(에너지 R² 0.23 vs 0.60, 포장식품 데이터) | 30끼 측정에서 이름 정확도 차이가 5%p 이내일 때만 전환 검토 |
| [Claude Opus 5.5 / Opus 5](https://platform.claude.com/docs/en/about-claude/pricing) | $4/$20 · $5/$25 (1차) | 39~56원 | 미측정 | Sonnet↔Opus 차 1~3%p(4.6 세대) | 안 씀 (과잉. Opus 5.5 는 강제 tool_choice 400) |
| [OpenAI gpt-5.6 Terra / Luna / Sol](https://developers.openai.com/api/docs/pricing) | $2/$12 · $0.20/$1.20 · $4/$20(프로모션) [미검증] | 22.2 / 2.2 / 약 36원 | 미측정 | GPT-5.5 저울 벤치 F1 0.66, MAE 42.0g | 안 씀 (Sonnet 5 대비 이점 없음, 키·프록시 이중화 부담). gpt-5-mini 는 2026-12-11 종료 예정 |
| [Google Gemini 3.1 Flash-Lite / 3.5 Flash](https://ai.google.dev/gemini-api/docs/pricing) | $0.25/$1.5 · $1.5/$9 [미검증] | 2.8 / 16.6원 | 미측정 | Gemini 3.0 Flash 가 Nutrition5k 10모델 중 최고 CCC 0.767·MAE 80.7kcal (저가형끼리 비교) | 안 씀. 2.5 계열은 퇴역 예정(날짜 미확정), 무료 등급은 데이터가 학습에 쓰임 |
| [두잉랩 FoodLens API](https://www.startupn.kr/news/articleView.html?idxno=24615) | 비공개, 최초 3개월 무료·월 5만 호출 기본 (2022 기사 기준) [미검증] | 비공개 | ✅ 한식 명시 (약 6,000종, 회사 주장) [미검증] | '정확도 90~95%'는 회사 주장뿐, 검증 연구 0건 | 안 씀. 무료 기간이 지금도 있으면 30끼 측정 비교군으로만 선택 사용 |
| [FatSecret Image Recognition](https://platform.fatsecret.com/docs/v1/image.recognition) | 애드온, 사용량 과금, 비공개 | 비공개 | △ 국가 DB 58~62개, KR 이미지 인식 [미검증] | NIH 방식 벤치(10모델)에 포함, 양까지 모델이 추정하는 구조 | 안 씀 (양을 모델이 말하는 구조) |
| [Passio Nutrition-AI (Flutter SDK 있음)](https://www.passio.ai/cost-breakdown) | 토큰제 $2.50/M, 장당 요금 [미검증] | [미검증] | 근거 없음, 미국 DB 중심 | 온디바이스라 프라이버시는 좋음 | 안 씀 |
| [LogMeal / Clarifai / Calorie Mama](https://docs.logmeal.com/docs/guides-essential-concepts-plans-limits) | 비공개 / 월 1,000회 무료 / 비공개 | — | 1,300종 근거 없음 / 한식 라벨 사실상 없음 / 한국어 라벨만 | Clarifai 는 영양 정보 없이 라벨만. Calorie Mama 예제는 2017년 정지 | 안 씀 |
| [Foodvisor Vision API / Bite AI](https://raw.githubusercontent.com/api-evangelist/foodvisor/refs/heads/main/apis.yml) | — | — | — | Foodvisor 는 vision.foodvisor.io NXDOMAIN (2026-09-23 확인). Bite AI 는 앱 삭제, API 운영 여부 불명 | 종료, 제외 |

## 온디바이스

판정: 지금은 안 한다. 서버 프록시(클라우드)가 유일한 경로다. 이유는 네 가지다. (1) 쓸 만한 무료 플랫폼 모델은 기기가 좁다. iOS 는 Foundation Models 이미지 입력이 iOS 27(2026-09-14 출시)부터이고 iPhone 15 Pro·16 이상에서 Apple Intelligence 를 켜야 한다(WWDC26 세션 241 1차). Android 는 ML Kit GenAI Prompt API 가 Beta(1.0.0-beta4)이고 Pixel 9 이상, Galaxy S25/S26 급만 된다. Galaxy S24·A시리즈 포함 여부는 [미검증]이다. 친구 10명의 기종을 조사하지 않았으니 커버리지는 0~100% 어디든 될 수 있다. (2) 내장 분류기에는 한식이 0개다. Apple Vision 1,303클래스에 kimchi·bibimbap·bulgogi 가 없다(Revision1 기준). ML Kit 기본 400 라벨도 마찬가지다. (3) 앱에 넣는 소형 VLM(flutter_gemma 1.9.0 으로 Gemma 4 E2B 2.4GB, SmolVLM2 0.36GB 등)은 한식 정확도·지연 실측이 0건이다. 음식 벤치에서 Gemma 4 E4B 는 최하위였다. 900토큰 출력이면 S26 Ultra GPU 에서도 약 17초가 걸린다. (4) 아낄 수 있는 돈이 작다. 10명이 하루 2장이면 Sonnet 5 기준 월 약 1.2~1.35만원, 연 약 16만원이다. 재검토 조건: ML Kit Prompt API 정식화와 보급형 기종 포함, 또는 iOS 27 FM 이 30끼 측정에서 이름 정확도가 클라우드와 같거나 높을 때. 그때도 '되는 기기에서만 이름 미리 채우기, 양은 항상 사람'의 보조 경로로만 쓴다.

## 한국 음식 데이터

판정: 내장 432개 표를 1순위로 유지한다. 외부 데이터로 대체하지 않는다. 자체 검산 결과 알코올을 빼면 아트워터(4p+4c+9f) 15% 초과는 배추김치 −18%, 브로콜리 데침 −21% 두 건뿐이다. 새로 발견한 문제가 하나 있다. 소주 1병 400 / 반병 170 / 1잔 56kcal 가 서로 맞지 않는다(1병으로 환산하면 400/340/403). 이것을 먼저 고친다.
(1) 식약처 음식 표준데이터(data.go.kr 15100070)는 CSV 를 한 번 받아 두 가지에만 쓴다. ① 우리 값과 교차검산해 ±20%를 넘으면 표시하고, ② 표에 없는 한식을 보강한다. 보강은 출처 배지를 달고 아트워터를 통과한 행만, '분석함량' 행을 우선한다. 규모는 19,495행인데 74%가 프랜차이즈이고, 한식 요리 대표식품은 약 1,094개다. FOOD-PLAN 의 '1,300 vs 12,200' 논쟁은 이 수치로 정리된다(제3자 실측, 원문 미열람). '1인(회)분량 참고량' 열은 비어 있고 식품중량은 급식 기준이 섞여 있다. 그래서 1인분 프리셋은 대체할 수 없다(갈비탕 198kcal, 라면 930kcal 같은 괴리가 있다). API(15127578)는 무료이고 개발계정 일 10,000건이다. FOOD-PLAN 의 '개발 1,000/운영 100,000'은 틀렸다. 부분일치 검색에 100건 상한이 있어 실시간 조회에는 쓰지 않는다.
(2) AI Hub(#74, #79, #242)는 앱에 넣지 않는다. 이용정책상 학습용으로만 쓸 수 있고 제3자 열람이 금지돼, 사진을 참조 이미지로 보여줄 수 없다. #74 에는 사진별 그램 라벨이 없고 양은 Q1~Q5 5단계뿐이다(제3자 확인, [미검증]). AI Hub 사진을 해외 API 로 보내 평가하는 것이 반출에 해당하는지도 불명확하다. 그래서 30끼 측정은 우리 사진으로 한다.
(3) 농진청 DB 는 10.4(3,366점, 2026-05)로 갱신됐다. FOOD-PLAN 의 3,272점은 10.0 기준이다. 원재료 100g 검산에만 쓰고 번들하지 않는다.
(4) 한식 모델 논문의 '81%'는 IEEE Access 2022 의 전체 정확도를 2차 인용한 수치다. 스튜디오 사진 기준이라 실사진에는 적용할 수 없다.

## 제품 규칙

- 자동 저장 없음. 사진 결과는 항상 검수 화면을 거치고, 사람이 저장 버튼을 누를 때만 기록된다.
- 양은 사람이 정한다. 반/1인분/1.5/2 프리셋이고 기본은 항상 1인분이다. 모델의 portion_word 는 힌트로만 보여주고, 그램 슬라이더는 기본 경로에 두지 않는다.
- 이름도 사람이 확정한다. 1순위와 후보 2개, '이건 아니에요·직접 찾기'를 둔다. 확신 낮음 항목은 미선택 상태로 띄운다.
- 내장 표에 없는 음식은 억지로 가장 가까운 항목에 붙이지 않고 '표에 없음 → 검색/직접 입력'으로 보낸다.
- 국·찌개에는 [다 먹음][반][건더기만]을 한 번 더 묻는다.
- 출처 배지를 모든 기록에 단다(📷 사진 / 🔍 표 / ✎ 직접). 주간 화면에 출처별 비율을 보여준다.
- 사진 결과에 점 추정 kcal, ±kcal, '정확도 N%'를 표시하지 않는다. 항목별 편차 등급(편차 작음/식당마다 다름/편차 큼)만 보여준다.
- '그냥 검색해서 고르기' 버튼이 사진 1단계부터 항상 보인다. photo_quality 가 unusable 이면 바로 수동으로 넘어간다.
- 처음 사진 버튼을 누를 때 '사진이 분석을 위해 서버와 Anthropic 으로 전송되고 저장되지 않는다'는 동의를 한 번 받는다. 설정의 '사진 분석 사용 안 함'으로 언제든 끄고, 꺼도 앱은 100% 동작한다.
- EXIF 는 보내기 전에 제거한다. 원본은 저장하지 않고 썸네일만 남긴다. 서버는 이미지와 본문을 로깅하지 않는다.
- 하루 한도(사용자 6장)에 닿으면 '오늘 사진 분석은 다 썼습니다. 검색으로 기록해 주세요'로 안내한다. 실패한 요청은 한도에서 빼지 않는다.
- '여러 장 찍기'는 만들지 않는다(연구상 효과 없음). 한 끼에 사진 한 장이다.
- 사진 기록을 체크인(체중 루프) 판단에 따로 가중하지 않는다. 30끼 측정에서 편향 부호가 음식군마다 뒤집히면 사진 항목을 달성률에 분리 표기하고 체크인에는 넘기지 않는다.

## 도입 단계

1. 0단계(지금, 코드 변경 없음): 수동 기록(검색·최근·즐겨찾기·1인분 프리셋)이 기본이다. 내장 표의 소주 행 불일치를 고치고, 식약처 15100070 CSV 로 432개를 교차검산해 ±20% 초과 목록을 만든다.
2. 1단계 측정 게이트(주말 이틀, 앱 변경 없음): 30끼를 찍으면서 주방저울로 밥·고기·반찬을 계량한다. 같은 사진을 Sonnet 5 와 Haiku 4.5 에 같은 스키마로 돌리고, 432개 후보 목록 넣기/안 넣기도 비교한다. 잴 것은 ① 내장표 매칭 후 이름 top-1·top-3, ② 표에 없는 음식 비율, ③ portion_word 가 '항상 1인분' 기본값보다 저울에 가까운지, ④ 편향의 부호가 음식군별로 일정한지, ⑤ 장당 실제 토큰(thinking 포함)과 p90 지연.
3. 중단·축소 기준(결과를 보기 전에 확정한다): top-1 < 60% 또는 top-3 < 80%이면 사진 기능을 만들지 않고 검색 개선에 집중한다. 표에 없는 음식이 30%를 넘으면 표 보강을 먼저 한다. portion_word 가 1인분 기본값보다 나쁘면 힌트를 숨기고 항상 1인분에서 시작한다. 장당 실제 비용이 40원을 넘거나 p90 지연이 10초를 넘으면 모델·프롬프트를 재검토한다. Haiku 의 top-1 이 Sonnet 대비 5%p 이내이면 Haiku 로 전환하고, 아니면 Sonnet 5 로 확정한다.
4. 2단계 구현과 소규모 베타(2주, 오너 포함 2명): /api/food-photo, 음식 전용 한도(사용자 6장/일, 전체 40장/일), 전용 워크스페이스 월 $20 한도, 검수 화면, source:'photo' 저장. 기능 플래그는 이 2명만 켠다. 이름 수정률이 40%를 넘거나, 사진 경로 한 끼 기록 시간이 검색 경로보다 길면 중단한다.
5. 3단계 전체 공개(10명): 첫 사용 동의를 받고 설정에서 끌 수 있게 한다. 월 1회 비용·수정률·출처 비율을 확인한다. 워크스페이스 한도에 닿는 달이 생기면 사용자 한도를 줄이고, 모델은 올리지 않는다.
6. 3개월 후 재검토: 한식 VLM 벤치마크, iOS 27 Foundation Models·ML Kit Prompt API 의 30끼 재측정, Qwen3.5 계열 자체 호스팅(프라이버시 요구가 생긴 경우에만)을 본다.

## 위험

- 프라이버시: 식사 사진이 해외 API(Anthropic)로 나간다. 완화책은 EXIF 제거, 저장·로깅 금지, 첫 사용 동의, 끄기 옵션이다. 프록시의 에러 로그가 본문을 남기는 것이 실수 1순위 경로다.
- 편향이 흔들리는 문제: 사진 오차는 음식 종류와 상관되고(국·볶음·튀김은 과소, 국·김치 분량은 과대), 체크인 체중 루프가 이 변동을 대사 변화로 착각할 수 있다.
- 이름 세분 오류: 김치찌개/부대찌개/김치찜처럼 비슷한 요리를 확신에 차서 틀릴 수 있다(DiningBench). 사람이 확정하지 않으면 조용히 기록이 오염된다.
- 표 밖 음식을 강제로 매칭하는 문제: 퍼지 검색이 표에 없는 음식을 가장 가까운 항목에 붙이면 틀린 숫자가 그럴듯하게 저장된다.
- 모델·API 변경: Opus 5.5 는 강제 tool_choice 에 400을 낸다. Sonnet 5 는 thinking 파라미터를 생략하면 출력 토큰이 늘 수 있다[미검증]. 모델 ID 만 바꾸는 운영 실수가 판독 전체를 멈출 수 있다.
- 비용 폭주: 가입이 열려 있으면 제3자가 계정을 만들어 판독을 태울 수 있다. 서버 한도와 워크스페이스 월 한도의 이중 차단이 필요하다. 리사이즈를 빠뜨리면 장당 토큰이 약 4.6배로 는다.
- 근거의 한계: 핵심 벤치(vlm-food-benchmark)는 유럽 식당 음식이고 논문은 심사 중이다. 논문 원문 대부분은 프록시 차단으로 검색 요약만 봤다. 한식 적용은 30끼 측정 전까지 추정이다.
- 섭식장애 위험: 사진 기록이 '매끼 찍어야 한다'는 압박이 되지 않도록 한다. 사진은 선택 경로이고 스트릭·질책 문구를 만들지 않는다(FOOD-PLAN §8 유지).
- 라이선스: AI Hub 데이터 사진을 노출하거나 영양표를 조회용으로 쓰면 이용정책 위반 소지가 있다. 농진청 책자는 공공누리 2유형(비상업)이다.
- 벤더 소멸: 음식 특화 API(Foodvisor 철수, Bite AI 불명)는 조용히 사라진다. 범용 모델 + 자체 표 구조가 이 위험을 피한다.

## 확인 못 한 것

- 한식 사진에서 Claude Sonnet 5·Haiku 4.5 의 이름 정확도: 공개 벤치 0건, 30끼 측정으로만 확인 가능
- Sonnet 5 에서 thinking 파라미터를 생략하면 adaptive thinking 이 켜져 출력 토큰이 느는지와 한국어 텍스트의 실제 토크나이저 증가율(count_tokens·실호출로 측정)
- 반/1/1.5/2 프리셋(저울 무게 아님)이 VLM 오차를 얼마나 줄이는지
- vlm-food-benchmark 는 논문 심사 중이고 데이터가 유럽 식당 음식이다. 최종 수치가 raw 파일과 같을지, 한식에 옮겨지는지
- DiningBench 리더보드 수치, OmniFood-Bench 세부 수치, Nutrition5k 10모델 논문 원문(PMC·arXiv·bioRxiv 차단, 검색 요약 2차)
- NIH 102끼 연구는 학회 초록이고 동료심사 전이다. Cal AI 가 자동 분량 추정을 광고한다는 부분도 미확인
- OpenAI gpt-5.6 계열·Gemini 3.x 단가와 이미지 토큰 산식(공식 페이지 차단), Gemini 2.5 퇴역일
- 두잉랩 FoodLens 의 현행 가격·무료 조건·인식 종수, FatSecret KR 이미지 인식 지원 여부, Passio 장당 요금
- Qwen3.5·Gemma 4 모델 카드 라이선스 원문(HF 차단), 오라클 A1 2코어에서 VLM 사진 1장 처리 시간('분 단위'는 추정), 오라클 무료 한도 공식 문서
- ML Kit GenAI 현재 지원 기기에 Galaxy S24·A시리즈가 들어갔는지, iOS 27 FM 의 이미지 포함 지연 절대값
- 식약처 15100070 의 74% 프랜차이즈·한식 대표식품 1,094개(제3자 한 곳 실측), 삼겹살·보쌈·계란말이 행 존재 여부, 15127578 운영계정 한도
- AI Hub #74 에 사진별 그램 라벨이 없는지와 용량 1.60TB, 74·79번의 내국인 한정 여부, AI Hub 사진을 해외 API 로 보내는 것이 반출에 해당하는지
- IEEE Access 2022 한식 분류 '전체 81%'(arXiv 2409.02448 의 2차 인용으로만 확인)
- 농진청 DB 10.4 파일 자체의 공공누리 유형
- '한국 영양사' 페르소나 프롬프트가 한식(큰 분량)에서 오차를 줄이는지 키우는지

## 출처

- [Anthropic — Pricing (Sonnet 5 $2/$10 정식 확정, Opus 5.5 $4/$20, 토크나이저 +30%)](https://platform.claude.com/docs/en/about-claude/pricing)
- [Anthropic — Vision (이미지 토큰 ⌈w/28⌉×⌈h/28⌉, 고해상도 등급)](https://platform.claude.com/docs/en/build-with-claude/vision)
- [Anthropic — Prompt caching (최소 길이·TTL 5분/1시간)](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [vlm-food-benchmark metrics_v2_all.csv (저울 계량 200끼, Sonnet 5·Qwen3.5·Gemma 4·MiniCPM-V)](https://github.com/Metabolic-Intelligence-Lab/vlm-food-benchmark/blob/main/analysis/outputs/metrics_v2_all.csv)
- [DiningBench (Meituan, ACL 2026) — 29모델 세분류 벤치](https://github.com/meituan/DiningBench)
- [OmniFood-Bench (arXiv 2607.08423)](https://arxiv.org/abs/2607.08423)
- [VLMs for Image-Based Dietary Assessment — Nutrition5k 10모델 (bioRxiv 2026-07)](https://www.biorxiv.org/content/10.64898/2026.07.26.740845v1)
- [Healio — NIH: AI photo calorie apps underestimate by 33% (NUTRITION 2026)](https://www.healio.com/news/primary-care/20260804/ai-photobased-calorietracking-tools-underestimate-them-by-33)
- [Prompt Engineering and Model Selection for LLM-Based Nutritional Estimation (Nutrients 18(12):2017)](https://doi.org/10.3390/nu18122017)
- [Model architecture dominates nutritional estimation accuracy in VLMs (Scientific Reports 2026)](https://pubmed.ncbi.nlm.nih.gov/42350490/)
- [Benchmarking Foundation Model Dietary Estimates from Meal Images (ACM-BCB 2025)](https://doi.org/10.1145/3765612.3767255)
- [TREX PR #4 — AI Hub 342종 YOLOv8n 온디바이스 실측](https://github.com/LeeDongHyun00/TREX/pull/4)
- [Evaluating food portion estimation accuracy with multi-angle photographs (Nutr Res Pract 2025)](https://pubmed.ncbi.nlm.nih.gov/40809887/)
- [tonyslowdown/kfood-server (GitHub 한식 인식 최고 별점, 2016 정지)](https://github.com/tonyslowdown/kfood-server)
- [WWDC26 Session 241 — Foundation Models 이미지 입력](https://developer.apple.com/videos/play/wwdc2026/241/)
- [Android Developers — ML Kit Prompt API (Gemini Nano 이미지+텍스트)](https://developer.android.com/blog/posts/ml-kit-s-prompt-api-unlock-custom-on-device-gemini-nano-experiences)
- [niney-life-pickr-v2 PLAN-meal.md — 식약처 15100070 실측(19,495행·1인분 참고량 공란)](https://github.com/niney/niney-life-pickr-v2/blob/93ae031aab70d758647711d6c47a560fe06f9f8d/docs/PLAN-meal.md)
- [Gainsy — 식약처 15127578 API 이용조건(일 10,000건·제한 없음)](https://github.com/KimGiii/Gainsy/blob/198a7b347450e49caa54bc96282b58c192fe36cb/docs/references/FOOD_CATALOG_DATA_REUSE_AND_STAGING_VERIFICATION_2026-06-18.md)
- [AI Hub 이용정책 (학습용으로만·제3자 열람 금지)](https://www.aihub.or.kr/intrcn/guid/usagepolicy.do?currMenu=151&topMenu=105)
- [스타트업엔 — 두잉랩 FoodLens API 공개(3개월 무료·월 5만 호출)](https://www.startupn.kr/news/articleView.html?idxno=24615)
