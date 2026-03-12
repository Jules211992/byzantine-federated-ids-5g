#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/n20_agg_audit_$TS"
mkdir -p "$OUT"/{scripts,views}

cp -f rev/21-run-baseline-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/25-run-labelflip-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true
cp -f rev/58-run-backdoor-n20-batch.sh "$OUT/scripts/" 2>/dev/null || true
cp -f phase7/multi_krum_aggregator.py "$OUT/scripts/" 2>/dev/null || true
cp -f phase8/fedavg_aggregator.py "$OUT/scripts/" 2>/dev/null || true
cp -f phase8/run_experiment.sh "$OUT/scripts/" 2>/dev/null || true

TRIMMED=$(find ~/byz-fed-ids-5g -type f \( -iname '*trimmed*mean*.py' -o -iname '*trimmedmean*.py' \) 2>/dev/null | sort || true)
printf "%s\n" "$TRIMMED" > "$OUT/trimmedmean_candidates.txt"

sed -n '1,260p' rev/21-run-baseline-n20-batch.sh > "$OUT/views/rev21.txt" 2>/dev/null || true
sed -n '1,260p' rev/25-run-labelflip-n20-batch.sh > "$OUT/views/rev25.txt" 2>/dev/null || true
sed -n '1,260p' rev/58-run-backdoor-n20-batch.sh > "$OUT/views/rev58.txt" 2>/dev/null || true
sed -n '1,260p' phase7/multi_krum_aggregator.py > "$OUT/views/multi_krum_aggregator.txt" 2>/dev/null || true
sed -n '1,260p' phase8/fedavg_aggregator.py > "$OUT/views/fedavg_aggregator.txt" 2>/dev/null || true
sed -n '1,260p' phase8/run_experiment.sh > "$OUT/views/run_experiment.txt" 2>/dev/null || true

grep -Rni \
"multi_krum_aggregator.py\|fedavg_aggregator.py\|trimmedmean\|trimmed_mean\|TrimmedMean\|selected\|rejected\|byzantine_detected\|aggregation_time_ms\|krum_time_ms\|global_metrics\|algorithm\|phase7/\|phase8/" \
rev phase7 phase8 > "$OUT/grep_all.txt" || true

python3 - <<'PY' "$OUT"
import json, sys, pathlib, re

out = pathlib.Path(sys.argv[1])
grep_file = out / "grep_all.txt"
txt = grep_file.read_text(errors="ignore") if grep_file.exists() else ""

keys = {
    "rev21_calls": [],
    "rev25_calls": [],
    "rev58_calls": [],
    "trimmedmean_hits": [],
    "fedavg_hits": [],
    "multikrum_hits": [],
}

for line in txt.splitlines():
    low = line.lower()
    if "rev/21-run-baseline-n20-batch.sh" in line:
        keys["rev21_calls"].append(line)
    if "rev/25-run-labelflip-n20-batch.sh" in line:
        keys["rev25_calls"].append(line)
    if "rev/58-run-backdoor-n20-batch.sh" in line:
        keys["rev58_calls"].append(line)
    if "trimmedmean" in low or "trimmed_mean" in low:
        keys["trimmedmean_hits"].append(line)
    if "fedavg_aggregator.py" in low or 'algorithm": "fedavg"' in low:
        keys["fedavg_hits"].append(line)
    if "multi_krum_aggregator.py" in low or "krum_time_ms" in low:
        keys["multikrum_hits"].append(line)

summary = {
    "audit_dir": str(out),
    "trimmedmean_candidates_file": str(out / "trimmedmean_candidates.txt"),
    "grep_file": str(grep_file),
    "counts": {k: len(v) for k, v in keys.items()},
    "top_rev21_calls": keys["rev21_calls"][:20],
    "top_rev25_calls": keys["rev25_calls"][:20],
    "top_rev58_calls": keys["rev58_calls"][:20],
    "top_trimmedmean_hits": keys["trimmedmean_hits"][:20],
    "top_fedavg_hits": keys["fedavg_hits"][:20],
    "top_multikrum_hits": keys["multikrum_hits"][:20],
}
(out / "AUDIT_SUMMARY.json").write_text(json.dumps(summary, indent=2))
print("AUDIT_DIR=", out)
print("SUMMARY_JSON=", out / "AUDIT_SUMMARY.json")
print("TRIMMEDMEAN_CANDIDATES=", out / "trimmedmean_candidates.txt")
print("GREP_FILE=", out / "grep_all.txt")
PY

echo
echo "DONE"
echo "$OUT"
