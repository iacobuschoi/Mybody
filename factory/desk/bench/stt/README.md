# 받아쓰기 비교 (10월 2일)

소리를 내지 않고, 같은 녹음으로 받아쓰기 설정을 비교합니다. 녹음 파일은 저장소에 넣지 않습니다(다시 만듦).

1. `make_digital.py` — phrases.txt(주인이 쓰는 말 36개)를 Supertonic 남자 목소리 M1~M5 로 합성하고, 실제 Jabra 바닥 소음(`floor.npy`, 조용한 0.1초 조각만 이어 붙인 것)을 섞음. 소리를 내지 않음.
2. `make_hard.py` — 방 울림(RT60 0.6초) + SNR 10 · 5dB 로 멀리서 한 말 흉내 → `meta_hard.json`
3. `META=meta_hard.json TAG=hard_ python evalstt.py base full_new2_fb …` — configs.py 의 설정마다 글자 오류율(CER) · 버린 수 · 낱말 맞춤
4. `latency.py` — 3 · 8 · 15초 말에 걸리는 시간

결과는 results-2026-10-02.txt. 합성 목소리라 주인 목소리보다 쉽고(깨끗한 소리는 모든 설정이 4~5%), 차이는 "어려운" 묶음에서만 보입니다.
주인이 `[stt] keep_audio_days` 를 켜면 실제 목소리(~/.local/share/desk/heard)로 같은 비교를 할 수 있습니다.

**소리를 스피커로 내는 시험은 주인이 확실히 없을 때만** — 10월 2일 16:14 주인이 말하는 중에 시험 소리를 내 방해했습니다.
