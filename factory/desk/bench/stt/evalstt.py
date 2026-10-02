"""받아쓰기 설정 비교: python evalstt.py <설정이름...>  — 같은 녹음으로 글자 오류율(CER) · 버려진 수 · 낱말 맞춤"""
import json, os, re, sys, time
import numpy as np, soundfile as sf
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
import mlx_whisper
from desk.stt import clean_transcript
D = os.path.dirname(os.path.abspath(__file__))
meta = json.load(open(f"{D}/" + os.environ.get("META", "meta.json")))
if os.environ.get("LOUD"):
    meta = [m for m in meta if m["vol"] == 1.0]
OLD_PROMPT = "앱 공장, 상황판, 브리핑, 클로드, 깃허브, 맥 미니, 아이폰, 안드로이드, 워크플로, 출시"
KW = ["책상", "탭", "마우스", "포인터", "권한", "승인", "잘 먹네", "핸드마우스", "조이스틱", "더블클릭", "터미널", "사파리",
      "배포", "다이얼", "앱스토어", "마이바디", "깃허브", "상황판", "클로드", "맥 미니", "아이폰", "안드로이드", "브리핑",
      "워크플로", "카카오톡", "키보드", "리모트 컨트롤", "작업 공간", "녹화", "심사"]

def norm(s): return re.sub(r"[\s\.,!?~·…'\"“”‘’\-]+", "", s).lower()

def cer(ref, hyp):
    r, h = norm(ref), norm(hyp)
    d = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        p, d[0] = d[0], i
        for j in range(1, len(h) + 1):
            p, d[j] = d[j], min(d[j] + 1, d[j - 1] + 1, p + (r[i - 1] != h[j - 1]))
    return d[len(h)] / max(1, len(r))

def run(cfg):
    out = []
    t0 = time.time()
    for m in meta:
        a, _ = sf.read(f"{D}/{m['file']}", dtype="float32")
        if cfg.get("gain"):
            pk = float(np.percentile(np.abs(a), 99.9)) + 1e-6
            a = np.clip(a * min(cfg["gain"] / pk, 30.0), -1, 1).astype(np.float32)
        if cfg.get("pad"):
            a = np.concatenate([a, np.zeros(int(16000 * cfg["pad"]), np.float32)])
        kw = dict(path_or_hf_repo=cfg["model"], language="ko", temperature=cfg.get("temp", 0.0),
                  condition_on_previous_text=False, verbose=None)
        if cfg.get("prompt"): kw["initial_prompt"] = cfg["prompt"]
        for k in ("compression_ratio_threshold", "logprob_threshold", "no_speech_threshold", "hallucination_silence_threshold", "word_timestamps"):
            if k in cfg: kw[k] = cfg[k]
        r = mlx_whisper.transcribe(a, **kw)
        raw = r.get("text", "")
        kept = clean_transcript(raw, r.get("segments"), **cfg.get("clean", {}))
        segs = [{k: s.get(k) for k in ("text", "no_speech_prob", "avg_logprob", "compression_ratio")} for s in r.get("segments", [])]
        out.append({**m, "raw": raw.strip(), "kept": kept, "segs": segs})
    dt = time.time() - t0
    return out, dt

def score(name, out, dt):
    def agg(rows):
        c = np.mean([cer(o["ref"], o["kept"] or "") for o in rows])
        craw = np.mean([cer(o["ref"], o["raw"]) for o in rows])
        drop = sum(1 for o in rows if not o["kept"])
        kwt = kwh = 0
        for o in rows:
            for w in KW:
                if norm(w) in norm(o["ref"]):
                    kwt += 1; kwh += norm(w) in norm(o["kept"] or "")
        return c, craw, drop, kwh, kwt
    loud = [o for o in out if o["vol"] == 1.0]; quiet = [o for o in out if o["vol"] != 1.0]
    L, Q = agg(loud), agg(quiet) if quiet else (0, 0, 0, 0, 0)
    line = (f"{name:28s} 보통: CER {L[0]*100:5.1f}% (거르기 전 {L[1]*100:5.1f}%) 버림 {L[2]:2d}/{len(loud)} 낱말 {L[3]}/{L[4]} | "
            f"작게: CER {Q[0]*100:5.1f}% 버림 {Q[2]:2d}/{len(quiet)} 낱말 {Q[3]}/{Q[4]} | {dt/len(out):.2f}초/개")
    print(line, flush=True)
    return line

if __name__ == "__main__":
    from configs import CONFIGS
    res = {}
    for name in sys.argv[1:]:
        out, dt = run(CONFIGS[name])
        json.dump(out, open(f"{D}/out_{os.environ.get("TAG", "")}{name}.json", "w"), ensure_ascii=False, indent=1)
        res[name] = score(name, out, dt)
    with open(f"{D}/results.txt", "a") as f:
        for v in res.values(): f.write(v + "\n")
