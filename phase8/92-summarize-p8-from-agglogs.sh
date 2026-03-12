#!/bin/bash
set -euo pipefail

OUT_DIR=/home/ubuntu/byz-fed-ids-5g/phase8/logs
mkdir -p "$OUT_DIR"
TS=$(date -u +%Y%m%d_%H%M%S)
OUT_JSON="$OUT_DIR/p8_agg_summary_${TS}.json"

python3 - <<'PY' > "$OUT_JSON"
import json, glob, os, time, statistics

logs = glob.glob("/home/ubuntu/byz-fed-ids-5g/phase7/logs/p7_round*.json")

now = time.time()
recent = [p for p in logs if now - os.path.getmtime(p) < 4*3600]
cand = sorted(recent, key=os.path.getmtime)
if len(cand) < 5:
  cand = sorted(logs, key=os.path.getmtime)[-5:]

items = []
for p in cand:
  try:
    d=json.load(open(p))
  except Exception:
    continue
  items.append((p,d))

items = sorted(items, key=lambda x: x[1].get("round", 0))

det = []
krum = []
f1 = []
fpr = []
rej = []
sel = []

for p,d in items:
  det.append(bool(d.get("byzantine_detected", False)))
  krum.append(float(d.get("krum_time_ms", 0.0)))
  gm=d.get("global_metrics", {}) or {}
  f1.append(float(gm.get("f1", 0.0)))
  fpr.append(float(gm.get("fpr", 0.0)))
  rej.append(len(d.get("rejected", []) or []))
  sel.append(len(d.get("selected", []) or []))

def avg(x): return sum(x)/len(x) if x else None

out = {
  "files": [p for p,_ in items],
  "rounds": [d.get("round") for _,d in items],
  "byzantine_detected_rate": avg([1 if x else 0 for x in det]),
  "rejected_avg": avg(rej),
  "selected_avg": avg(sel),
  "krum_time_ms": {"avg": avg(krum), "min": min(krum) if krum else None, "max": max(krum) if krum else None},
  "global_f1": {"avg": avg(f1), "min": min(f1) if f1 else None, "max": max(f1) if f1 else None},
  "global_fpr": {"avg": avg(fpr), "min": min(fpr) if fpr else None, "max": max(fpr) if fpr else None},
  "per_round": [
    {
      "round": d.get("round"),
      "byzantine_detected": d.get("byzantine_detected"),
      "rejected": d.get("rejected"),
      "selected": d.get("selected"),
      "krum_time_ms": d.get("krum_time_ms"),
      "global_metrics": d.get("global_metrics"),
      "cid_global": d.get("cid_global"),
      "hash_global": d.get("hash_global"),
    }
    for _,d in items
  ]
}

print(json.dumps(out, indent=2))
PY

echo "SAVED $OUT_JSON"
cat "$OUT_JSON"
