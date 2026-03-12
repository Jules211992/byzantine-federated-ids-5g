#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

ROUND=1
START_FABRIC=95000

echo "RUN_DIR=$RUN_DIR"
echo "ROUND=$ROUND"
echo "START_FABRIC=$START_FABRIC"

START_FABRIC="$START_FABRIC" ROUND="$ROUND" bash ~/byz-fed-ids-5g/rev/16b-run-p7-n20-baseline-smoke-v2.sh

OUT_DIR="$RUN_DIR/p7_baseline/round$(printf "%02d" "$ROUND")/client_logs"
[ -d "$OUT_DIR" ] || { echo "ERROR: OUT_DIR introuvable: $OUT_DIR"; exit 1; }

echo
echo "===== COUNT FILES ====="
echo "runfl.out  = $(find "$OUT_DIR" -maxdepth 1 -name '*.runfl.out' | wc -l | tr -d ' ')"
echo "json       = $(find "$OUT_DIR" -maxdepth 1 -name '*.json' | wc -l | tr -d ' ')"
echo "fl_fabric  = $(find "$OUT_DIR" -maxdepth 1 -name '*.fl_fabric.out' | wc -l | tr -d ' ')"

echo
echo "===== SAMPLE LOGS ====="
ls -lt "$OUT_DIR" | head -20

echo
echo "===== FAILURES FILE ====="
cat "$RUN_DIR/p7_baseline/round01/edge_logs/failures.txt" 2>/dev/null || echo "Aucune failure enregistrée"

echo
echo "===== QUICK METRICS ====="
python3 - <<'PY' "$OUT_DIR"
import sys, json, glob, os

out_dir = sys.argv[1]
files = sorted(glob.glob(os.path.join(out_dir, "*.json")))
print("JSON_FILES=", len(files))

ok = 0
for p in files[:5]:
    try:
        d = json.load(open(p))
        cid = d.get("client_id", os.path.basename(p))
        tm = d.get("test_metrics", {})
        print(cid, "F1=", tm.get("f1"), "FPR=", tm.get("fpr"))
        ok += 1
    except Exception as e:
        print("ERROR", p, e)

print("SAMPLED_OK=", ok)
PY

echo
echo "DONE"
