#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/n20_live_audit_$TS"
mkdir -p "$OUT"/{scripts,lists}

FILES=(
  rev/21-run-baseline-n20-batch.sh
  rev/25-run-labelflip-n20-batch.sh
  rev/58-run-backdoor-n20-batch.sh
  phase7/multi_krum_aggregator.py
  phase8/fedavg_aggregator.py
  phase8/trimmed_mean_aggregator.py
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] && cp -f "$f" "$OUT/scripts/"
done

{
  echo "RUN_DIR=$RUN_DIR"
  echo "OUT=$OUT"
  echo
  for f in "${FILES[@]}"; do
    echo "===== FILE: $f ====="
    if [ -f "$f" ]; then
      grep -nE 'BASE_FABRIC|START_ROUND|END_ROUND|run_fl_round|multi_krum|fedavg|trimmed|selected|rejected|byzantine|global_metrics|aggregation_time_ms|krum_time_ms|summary|client_logs|edge_logs|fl-ids-|fl-byz-' "$f" || true
    else
      echo "MISSING"
    fi
    echo
  done
} > "$OUT/KEY_LINES.txt"

find "$RUN_DIR/p7_baseline"  -maxdepth 3 -type f 2>/dev/null | sort > "$OUT/lists/p7_baseline_files.txt" || true
find "$RUN_DIR/p8_labelflip" -maxdepth 3 -type f 2>/dev/null | sort > "$OUT/lists/p8_labelflip_files.txt" || true
find "$RUN_DIR/p15_backdoor" -maxdepth 3 -type f 2>/dev/null | sort > "$OUT/lists/p15_backdoor_files.txt" || true

python3 - <<'PY' "$RUN_DIR" "$OUT"
import json, sys
from pathlib import Path

run_dir = Path(sys.argv[1])
out = Path(sys.argv[2])

scenarios = {
    "baseline": run_dir / "p7_baseline",
    "label_flip": run_dir / "p8_labelflip",
    "backdoor": run_dir / "p15_backdoor",
}

summary = {
    "run_dir": str(run_dir),
    "audit_dir": str(out),
    "scenarios": {}
}

patterns_raw = ["fl-ids-*.json", "fl-byz-*.json"]
patterns_runfl = ["*.runfl.out"]
patterns_csv = ["*.csv"]
patterns_json = ["*.json"]

for name, root in scenarios.items():
    info = {
        "root_exists": root.exists(),
        "rounds": {}
    }
    if root.exists():
        rounds = sorted([p for p in root.iterdir() if p.is_dir() and p.name.startswith("round")])
        for rd in rounds:
            raw_json = []
            for pat in patterns_raw:
                raw_json.extend(list(rd.rglob(pat)))
            runfl = []
            for pat in patterns_runfl:
                runfl.extend(list(rd.rglob(pat)))
            csvs = []
            for pat in patterns_csv:
                csvs.extend(list(rd.rglob(pat)))
            jsons = []
            for pat in patterns_json:
                jsons.extend(list(rd.rglob(pat)))
            info["rounds"][rd.name] = {
                "raw_update_json_count": len(raw_json),
                "runfl_out_count": len(runfl),
                "csv_count": len(csvs),
                "json_count": len(jsons),
                "sample_raw_update_json": [str(p) for p in sorted(raw_json)[:10]],
                "sample_runfl": [str(p) for p in sorted(runfl)[:10]],
                "sample_csv": [str(p) for p in sorted(csvs)[:10]],
                "sample_json": [str(p) for p in sorted(jsons)[:10]],
            }
    summary["scenarios"][name] = info

(out / "LIVE_AUDIT_SUMMARY.json").write_text(json.dumps(summary, indent=2))
print("LIVE_AUDIT_SUMMARY=", out / "LIVE_AUDIT_SUMMARY.json")
PY

echo "AUDIT_DIR=$OUT"
echo "DONE"
