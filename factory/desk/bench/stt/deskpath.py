"""deskd 와 같은 받아쓰기 길(desk/stt.py WhisperSTT._run — 토큰 한도 · 되풀이 끊기)로 한 개씩 받아쓴 결과 · 시간을 남김.
python deskpath.py <이름> <모델 T|F|F8|F4> <temps 예: 0 또는 0,0.2,0.4>   (META=… SET=녹음 폴더)
결과 pc_<이름>.json 은 percall.py 와 같은 꼴 — cascade.py 로 "turbo 먼저, 애매하면 큰 모델" 을 흉내 냄"""
import json, os, sys, time
import numpy as np, soundfile as sf
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from desk.stt import WhisperSTT
from configs import T, F, NEW2
D = os.environ.get("SET") or os.path.dirname(os.path.abspath(__file__))
MODELS = {"T": T, "F": F, "F8": F + "-8bit", "F4": F + "-4bit"}
name, model = sys.argv[1], MODELS.get(sys.argv[2], sys.argv[2])
temps = tuple(float(t) for t in sys.argv[3].split(","))
temps = temps if len(temps) > 1 else temps[0]
meta = [m for f in os.environ.get("META", "meta_hard.json").split(",") for m in json.load(open(f"{D}/{f}"))]
meta = [m for m in meta if m["vol"] != 0.04]
stt = WhisperSTT(model, prompt=NEW2)
stt._run(model, np.zeros(16000, np.float32), 0.0)
out = []
for m in meta:
    a, _ = sf.read(f"{D}/{m['file']}", dtype="float32")
    t = time.time()
    r = stt._run(model, a, temps)
    dt = time.time() - t
    segs = [{k: s.get(k) for k in ("text", "no_speech_prob", "avg_logprob", "compression_ratio", "temperature")} for s in r.get("segments", [])]
    out.append({**m, "raw": r.get("text", "").strip(), "segs": segs, "t": round(dt, 3), "sec": round(len(a) / 16000, 2)})
json.dump(out, open(f"{D}/pc_{name}.json", "w"), ensure_ascii=False, indent=1)
ts = [o["t"] for o in out]
print(name, len(out), f"평균 {np.mean(ts):.2f}초 · 가장 오래 {max(ts):.2f}초", flush=True)
