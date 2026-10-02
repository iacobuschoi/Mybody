"""소리 내지 않는 시험 묶음: 디지털 합성(M1~M5) × 보통 · 작게 에 실제 Jabra 바닥 소음 섞기"""
import glob, json, os, numpy as np, soundfile as sf
from supertonic import TTS
D = os.path.dirname(os.path.abspath(__file__))
phr = [l.strip() for l in open(f"{D}/phrases.txt") if l.strip()]
meta = []
floor = np.load(f"{D}/floor.npy")          # 실제 Jabra 바닥 소음(0.1초 조각 중 아주 조용한 것만 — 말소리 없음)
tts = TTS(model="supertonic-3")
rng = np.random.default_rng(1)
for style, speed in [("M1", 1.0), ("M2", 1.05), ("M3", 1.15), ("M4", 1.0), ("M5", 0.95)]:
    st = tts.get_voice_style(style)
    for k, p in enumerate(phr):
        wav, _ = tts.synthesize(p, voice_style=st, lang="ko", total_steps=5, speed=speed)
        wav = np.asarray(wav, np.float32).reshape(-1)
        n = int(len(wav) * 16000 / tts.sample_rate)
        wav = np.interp(np.arange(n) * tts.sample_rate / 16000, np.arange(len(wav)), wav).astype(np.float32)
        for vol in (0.4, 0.04):                                  # 보통(방 녹음 봉우리 0.4 안팎) · 작게(멀리서)
            v = wav / (abs(wav).max() + 1e-9) * vol
            pad = np.zeros(int(16000 * 0.5), np.float32)
            a = np.concatenate([pad, v, pad[:4000]])
            s = rng.integers(0, len(floor) - len(a))
            a = a + floor[s:s + len(a)]
            name = f"dig_{style}_{vol}_{k:02d}.wav"
            sf.write(f"{D}/{name}", a, 16000)
            meta.append({"file": name, "ref": p, "voice": style, "vol": 1.0 if vol == 0.4 else vol})
json.dump(meta, open(f"{D}/meta.json", "w"), ensure_ascii=False, indent=1)
print(len(meta))
