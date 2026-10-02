"""한 개씩 받아쓴 결과 · 걸린 시간을 남김 — cascade.py 가 이걸로 "turbo 먼저, 애매하면 large-v3" 를 소리 없이 흉내 냄
python percall.py <이름> <모델 T|F|F8|F4|허깅페이스 이름> <temps 예: 0 또는 0,0.2,0.4> <cap 0|1>  (META=meta_hard.json,meta_noise.json SET=녹음 폴더)"""
import json, os, sys, time
import numpy as np, soundfile as sf
import mlx_whisper
from configs import T, F, NEW2
D = os.environ.get("SET") or os.path.dirname(os.path.abspath(__file__))
name, model, temps, cap = sys.argv[1], {"T": T, "F": F, "F8": F + "-8bit", "F4": F + "-4bit"}.get(sys.argv[2], sys.argv[2]), tuple(float(t) for t in sys.argv[3].split(",")), sys.argv[4] == "1"
meta = [m for f in os.environ.get("META", "meta_hard.json").split(",") for m in json.load(open(f"{D}/{f}"))]
meta = [m for m in meta if m["vol"] != 0.04]          # meta.json 의 아주 작은 소리는 뺌(어려운 묶음 · 깨끗한 묶음 · 잡음만)
mlx_whisper.transcribe(np.zeros(16000, np.float32), path_or_hf_repo=model, language="ko")
out = []
for m in meta:
    a, _ = sf.read(f"{D}/{m['file']}", dtype="float32")
    kw = dict(path_or_hf_repo=model, language="ko", temperature=temps if len(temps) > 1 else temps[0],
              condition_on_previous_text=False, initial_prompt=NEW2, verbose=None)
    if cap:
        kw["sample_len"] = int(min(224, 32 + 12 * min(len(a) / 16000, 30)))
    t = time.time()
    r = mlx_whisper.transcribe(a, **kw)
    dt = time.time() - t
    segs = [{k: s.get(k) for k in ("text", "no_speech_prob", "avg_logprob", "compression_ratio", "temperature")} for s in r.get("segments", [])]
    out.append({**m, "raw": r.get("text", "").strip(), "segs": segs, "t": round(dt, 3), "sec": round(len(a) / 16000, 2)})
json.dump(out, open(f"{D}/pc_{name}.json", "w"), ensure_ascii=False, indent=1)
ts = [o["t"] for o in out]
print(name, len(out), f"평균 {np.mean(ts):.2f}초 · 가장 오래 {max(ts):.2f}초", flush=True)
