"""말 없는 소리 묶음: 바닥 소음 · 딸깍 소리(키보드 · 마우스) · 낮은 웅웅거림 — 상시 듣기가 잡음을 말로 잘라 넘길 때(로그의 "감사합니다")
받아쓰기가 얼마나 붙잡는지 잼. 1~12초 30개 → meta_noise.json"""
import json, os, numpy as np, soundfile as sf
D = os.environ.get("SET") or os.path.dirname(os.path.abspath(__file__))
floor = np.load(f"{D}/floor.npy"); floor = floor / np.sqrt((floor ** 2).mean())
rng = np.random.default_rng(11)
out = []
for i in range(30):
    sec = float(rng.choice([1.2, 2, 3, 5, 8, 12]))
    n = int(sec * 16000)
    s = rng.integers(0, len(floor) - n)
    x = floor[s:s + n] * 0.01
    kind = i % 3
    if kind == 1:                                     # 딸깍 · 탁 — 짧은 충격음
        for _ in range(int(sec * 3)):
            p = rng.integers(0, n - 800)
            x[p:p + 800] += rng.standard_normal(800) * np.exp(-np.arange(800) / 120) * 0.15
    elif kind == 2:                                   # 웅웅 · 팬 소리
        t = np.arange(n) / 16000
        x += 0.03 * np.sin(2 * np.pi * 120 * t) + 0.02 * rng.standard_normal(n) * np.sin(2 * np.pi * 0.5 * t) ** 2
    x = (x / max(1e-6, np.abs(x).max()) * rng.choice([0.05, 0.15, 0.3])).astype(np.float32)
    name = f"noise_{i:02d}.wav"
    sf.write(f"{D}/{name}", x, 16000)
    out.append({"file": name, "ref": "", "voice": "-", "vol": "noise", "sec": sec})
json.dump(out, open(f"{D}/meta_noise.json", "w"), ensure_ascii=False, indent=1)
print(len(out))
