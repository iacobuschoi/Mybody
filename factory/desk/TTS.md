# 책상 목소리 — 고른 것과 안 고른 것 (2026-09-28)

## 지금: Supertonic 3 (적용됨)
- `[tts] engine = "supertonic"` · `style = "F1"`(F1~F5 여 · M1~M5 남) · `speed` · `steps`.
- Supertone 이 공개한 온디바이스 TTS. ONNX, 66M 파라미터, 한국어 포함 31개 언어. 코드 MIT · 모델 OpenRAIL-M.
- 이 맥 미니(M1)에서 잰 값: 모델 뜨기 0.4~2.6초(처음엔 380MB 내려받기), 짧은 문장 합성 0.3~0.6초, 첫소리 0.6초 안팎.
  Whisper 로 되받아 적으면 거의 그대로 나옴("3건", "오후 9시" 포함).
- 못 쓰면(패키지 없음 · 모델 못 받음 · 스피커 오류) 그 자리에서 `say` 로 말함.
- 목소리 바꿔 듣기: `python -m desk selftest` 의 「말하기」, 또는 config 의 `style` 을 바꾸고 deskd 재시작.

## 무료지만 안 고른 것
- **Yuna (프리미엄)** — `say` 예비 목소리를 좋게 하는 가장 쉬운 방법. 설정 → 손쉬운 사용 → 읽기 및 말하기 → 시스템 음성 →
  한국어 → Yuna (프리미엄) 내려받기(사람이 눌러야 함). 받으면 `best_voice` 가 알아서 고름. Supertonic 보단 기계적.
- **Qwen3-TTS (mlx-audio)** — 0.6B/1.7B, 한국어 화자 · 감정 지시 가능, 더 표현력 있음. 대신 M1 16GB 에서 무겁고 느림
  (RAM 2~3GB, 첫소리 수 초) — 20초 안에 답해야 하는 비서엔 과함. 긴 글 낭독용이면 다시 볼 만함.
- **Edge TTS(ko-KR-SunHi/InJoon Neural)** — 키는 없지만 마이크로소프트 서버로 글을 보냄 · 비공식 사용이라 제외.

## 비밀값 · 결제가 필요해서 적용 안 한 것
| 서비스 | 필요한 것 | 특징 |
|---|---|---|
| 네이버 클로바 보이스(CLOVA Voice) | NCP API 키 · 결제 | 한국어 화자가 가장 많고 자연스러움 |
| Google Cloud TTS (Chirp 3 HD / Neural2 ko-KR) | GCP 키 · 결제(무료 할당 있음) | 품질 좋음, 스트리밍 |
| Azure Speech (ko-KR Neural) | Azure 키 · 결제(무료 할당 있음) | SSML 로 억양 · 속도 세밀 |
| OpenAI TTS (gpt-4o-mini-tts 등) | API 키 · 사용량 과금 | 말투 지시 가능, 한국어는 억양이 약간 외국인 |
| ElevenLabs (Multilingual v2 / Flash) | API 키 · 구독 | 가장 사람 같음, 목소리 복제 |
| 타입캐스트 · 셀바스 등 국내 | 계정 · 구독 | 한국어 캐릭터 목소리 |

붙인다면: `desk/tts.py` 의 `NeuralVoice._speak` 에서 `synthesize` 자리만 HTTP 호출로 바꾸면 되고, 키는 config 가 아니라
키체인(`security find-generic-password`)에서 읽게 할 것. 방의 모든 답이 외부로 나간다는 점도 같이 따질 것.
