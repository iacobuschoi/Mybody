"""deskd 받아쓰기 그대로(WhisperSTT.transcribe — 토큰 한도 · 되풀이 끊기 · 상시 듣기의 잡음 다시 받아쓰기 건너뜀)로 한 개씩 → pc_<이름>.json
python e2e.py <이름> <모델 F|F8|…> [fist]   fist: 주먹 말처럼(direct=True)   (META=… SET=녹음 폴더)"""
import json, os, sys, time
import numpy as np, soundfile as sf
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from desk.stt import WhisperSTT
from configs import T, F, NEW2
D = os.environ.get("SET") or os.path.dirname(os.path.abspath(__file__))
name, model = sys.argv[1], {"T": T, "F": F, "F8": F + "-8bit", "F4": F + "-4bit"}.get(sys.argv[2], sys.argv[2])
direct = sys.argv[3:] == ["fist"]
meta = [m for f in os.environ.get("META", "meta_hard.json").split(",") for m in json.load(open(f"{D}/{f}"))]
meta = [m for m in meta if m["vol"] != 0.04]
stt = WhisperSTT(model, prompt=NEW2)
stt.warmup()
out = []
for m in meta:
    a, _ = sf.read(f"{D}/{m['file']}", dtype="float32")
    t = time.time()
    kept = stt.transcribe(a, direct=direct)
    out.append({**m, "raw": stt.last_raw.strip(), "kept": kept, "t": round(time.time() - t, 3), "sec": round(len(a) / 16000, 2)})
json.dump(out, open(f"{D}/pc_{name}.json", "w"), ensure_ascii=False, indent=1)
ts = [o["t"] for o in out]
print(name, len(out), f"평균 {np.mean(ts):.2f}초 · 가장 오래 {max(ts):.2f}초", flush=True)
