#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/freeze_ref_$TS"
mkdir -p "$OUT"

mkdir -p "$OUT/scripts"
cp -f phase7/multi_krum_aggregator.py "$OUT/scripts/" 2>/dev/null || true
cp -f phase8/fedavg_aggregator.py "$OUT/scripts/" 2>/dev/null || true
cp -f phase8/run_experiment.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/70-run-agg-compare-n4.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/21-run-baseline-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/25-run-labelflip-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/58-run-backdoor-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true

LATEST_AGG=$(ls -dt "$RUN_DIR"/agg_compare_n4_* 2>/dev/null | head -n 1 || true)
if [ -n "${LATEST_AGG:-}" ]; then
  mkdir -p "$OUT/agg_compare_n4"
  cp -f "$LATEST_AGG"/agg_compare_n4_per_round.csv "$OUT/agg_compare_n4/" 2>/dev/null || true
  cp -f "$LATEST_AGG"/agg_compare_n4_summary.csv "$OUT/agg_compare_n4/" 2>/dev/null || true
fi

mkdir -p "$OUT/phase7_logs"
ls -t phase7/logs/p7_round*.json 2>/dev/null | head -n 20 | while read -r f; do
  cp -f "$f" "$OUT/phase7_logs/" 2>/dev/null || true
done

mkdir -p "$OUT/phase8_logs"
ls -t phase8/logs/*.json 2>/dev/null | head -n 40 | while read -r f; do
  cp -f "$f" "$OUT/phase8_logs/" 2>/dev/null || true
done

mkdir -p "$OUT/env"

python3 - <<'PY' "$OUT/env/local_manifest.json"
import json, os, glob, hashlib, subprocess, time, sys
out = sys.argv[1]

def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

files = [
    "phase7/multi_krum_aggregator.py",
    "phase8/fedavg_aggregator.py",
    "phase8/run_experiment.sh",
    "rev/70-run-agg-compare-n4.sh",
    "rev/21-run-baseline-n20-batch.sh",
    "rev/25-run-labelflip-n20-batch.sh",
    "rev/58-run-backdoor-n20-batch.sh",
    "config/config.env"
]

manifest = {
    "ts": int(time.time()),
    "cwd": os.getcwd(),
    "files": [],
    "phase6_splits": {},
    "phase8_recent_json": sorted(glob.glob("phase8/logs/*.json"))[-20:],
    "phase7_recent_json": sorted(glob.glob("phase7/logs/p7_round*.json"))[-20:]
}

for p in files:
    if os.path.exists(p):
        manifest["files"].append({
            "path": p,
            "sha256": sha256_file(p),
            "size": os.path.getsize(p)
        })

for p in [
    "phase6/splits/global_test_X.npy",
    "phase6/splits/global_test_y.npy",
    "phase6/splits/feature_names.json",
    "phase6/splits/feat_min.npy",
    "phase6/splits/feat_max.npy"
]:
    if os.path.exists(p):
        manifest["phase6_splits"][p] = {
            "sha256": sha256_file(p),
            "size": os.path.getsize(p)
        }

with open(out, "w") as f:
    json.dump(manifest, f, indent=2)
PY

for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
set -e
python3 - <<'"'"'PY'"'"'
import os, glob, json, hashlib, numpy as np

def sha256_file(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

out = {
    "host": os.uname().nodename,
    "client_py": None,
    "byz_py": None,
    "splits": {},
    "logs": sorted(glob.glob("/opt/fl-client/logs/*.json"))[-20:]
}

for p in ["/opt/fl-client/fl_ids_client.py", "/opt/fl-client/fl_ids_byzantine.py"]:
    if os.path.exists(p):
        entry = {"path": p, "sha256": sha256_file(p), "size": os.path.getsize(p)}
        if p.endswith("fl_ids_client.py"):
            out["client_py"] = entry
        else:
            out["byz_py"] = entry

for p in sorted(glob.glob("/opt/fl-client/splits/*_train_X.npy"))[:10]:
    x = np.load(p, mmap_mode="r")
    out["splits"][os.path.basename(p)] = list(x.shape)

for p in sorted(glob.glob("/opt/fl-client/splits/*_test_X.npy"))[:10]:
    x = np.load(p, mmap_mode="r")
    out["splits"][os.path.basename(p)] = list(x.shape)

print(json.dumps(out, indent=2))
PY
' > "$OUT/env/edge_${ip}.json"
done

python3 - <<'PY' "$OUT"
import csv, json, os, glob, statistics, sys
out = sys.argv[1]

rows = []
agg = glob.glob(os.path.join(out, "agg_compare_n4", "agg_compare_n4_summary.csv"))
if agg:
    with open(agg[0], newline="") as f:
        for r in csv.DictReader(f):
            rows.append(r)

summary = {
    "freeze_dir": out,
    "has_agg_compare_n4": bool(agg),
    "n_agg_rows": len(rows),
    "agg_rows": rows
}

with open(os.path.join(out, "FREEZE_SUMMARY.json"), "w") as f:
    json.dump(summary, f, indent=2)

print("FREEZE_DIR=", out)
print("SUMMARY_JSON=", os.path.join(out, "FREEZE_SUMMARY.json"))
print("LOCAL_MANIFEST=", os.path.join(out, "env", "local_manifest.json"))
PY

find "$OUT" -maxdepth 2 -type f | sort > "$OUT/INVENTORY.txt"

echo "DONE"
echo "$OUT"
