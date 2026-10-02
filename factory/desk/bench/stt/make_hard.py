"""어려운 묶음: 디지털 합성(M1~M5)을 방 울림(RT60 0.6초) + 낮은 SNR(10dB · 5dB) 로 — 멀리서 한 말 흉내"""
import glob, json, os, numpy as np, soundfile as sf
D = os.path.dirname(os.path.abspath(__file__))
floor = np.load(f"{D}/floor.npy"); floor = floor / np.sqrt((floor ** 2).mean())
rng = np.random.default_rng(7)
def rir(rt60=0.6, sr=16000):
    n = int(sr * rt60); t = np.arange(n) / sr
    h = rng.standard_normal(n) * np.exp(-6.9 * t / rt60); h[0] = 3.0
    return (h / np.abs(h).sum() * 4).astype(np.float32)
meta, out = json.load(open(f"{D}/meta.json")), []
for m in meta:
    if m["vol"] != 1.0: continue
    a, _ = sf.read(f"{D}/{m['file']}", dtype="float32")
    sp = np.convolve(a, rir())[:len(a) + 8000]
    sig = np.sqrt((sp[sp != 0] ** 2).mean())
    for snr in (10, 5):
        s = rng.integers(0, len(floor) - len(sp))
        x = sp + floor[s:s + len(sp)] * sig / (10 ** (snr / 20)) * 0.7
        x = (x / np.abs(x).max() * 0.3).astype(np.float32)
        name = m["file"].replace("dig_", f"hard{snr}_")
        sf.write(f"{D}/{name}", x, 16000)
        out.append({**m, "file": name, "vol": snr})
json.dump(out, open(f"{D}/meta_hard.json", "w"), ensure_ascii=False, indent=1)
print(len(out))
