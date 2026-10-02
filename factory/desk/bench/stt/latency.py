"""받아쓰기 걸리는 시간: 3 · 8 · 15초 말, turbo vs large-v3(full)"""
import json, os, time, numpy as np, soundfile as sf, mlx_whisper
from configs import T, F, NEW2
D = os.path.dirname(os.path.abspath(__file__))
meta = [m for m in json.load(open(f"{D}/meta_hard.json")) if m["vol"] == 10]
clips = [sf.read(f"{D}/{m['file']}", dtype="float32")[0] for m in meta]
def make(sec):
    out, i = [], 0
    while sum(map(len, out)) < sec * 16000:
        out.append(clips[i % len(clips)]); i += 1
    return np.concatenate(out)[: sec * 16000]
for model in (T, F):
    mlx_whisper.transcribe(np.zeros(16000, np.float32), path_or_hf_repo=model, language="ko")
    for sec in (3, 8, 15):
        ts = []
        for k in range(3):
            a = make(sec) if k == 0 else np.roll(make(sec), 8000 * k)
            t = time.time()
            mlx_whisper.transcribe(a, path_or_hf_repo=model, language="ko", temperature=(0.0, 0.2, 0.4),
                                   condition_on_previous_text=False, initial_prompt=NEW2, verbose=None)
            ts.append(time.time() - t)
        print(model.split("/")[-1], f"{sec}초 말: {np.median(ts):.2f}초 (", " ".join(f"{x:.2f}" for x in ts), ")", flush=True)
