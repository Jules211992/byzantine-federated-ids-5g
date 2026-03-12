#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

PUB=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
FGI=$(ls -dt "$RUN_DIR"/final_graph_inputs_* 2>/dev/null | head -n 1 || true)

OUT="$RUN_DIR/recovered_ipfs_blockchain_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"/publication_bundle
mkdir -p "$OUT"/final_graph_inputs
mkdir -p "$OUT"/summary

[ -n "${PUB:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }
[ -n "${FGI:-}" ] || { echo "ERROR: final_graph_inputs introuvable"; exit 1; }

cp -f "$PUB"/tables_input/paper_main_metrics.csv "$OUT"/publication_bundle/ 2>/dev/null || true
cp -f "$PUB"/figures_input/plot_round_metrics.csv "$OUT"/publication_bundle/ 2>/dev/null || true
cp -f "$PUB"/baseline/baseline_all_rounds_clean.json "$OUT"/publication_bundle/ 2>/dev/null || true
cp -f "$PUB"/label_flip/label_flip_all_rounds_clean.json "$OUT"/publication_bundle/ 2>/dev/null || true
cp -f "$PUB"/backdoor/backdoor_all_rounds_clean.json "$OUT"/publication_bundle/ 2>/dev/null || true

find "$FGI" -maxdepth 3 -type f \
  \( -name "*.csv" -o -name "*.json" \) \
  -exec cp -f {} "$OUT"/final_graph_inputs/ \; 2>/dev/null || true

find "$RUN_DIR"/summary -maxdepth 1 -type f \
  \( -name "p7_baseline_*" -o -name "p8_labelflip_*" -o -name "p15_backdoor_*" \) \
  -exec cp -f {} "$OUT"/summary/ \; 2>/dev/null || true

python3 - <<'PY' "$RUN_DIR" "$PUB" "$FGI" "$OUT"
import csv
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
pub = Path(sys.argv[2])
fgi = Path(sys.argv[3])
out = Path(sys.argv[4])

report = {
    "run_dir": str(run_dir),
    "publication_bundle": str(pub),
    "final_graph_inputs": str(fgi),
    "copied_to": str(out),
    "files": {}
}

targets = [
    pub / "tables_input" / "paper_main_metrics.csv",
    pub / "figures_input" / "plot_round_metrics.csv",
    pub / "baseline" / "baseline_all_rounds_clean.json",
    pub / "label_flip" / "label_flip_all_rounds_clean.json",
    pub / "backdoor" / "backdoor_all_rounds_clean.json",
]

for p in targets:
    report["files"][p.name] = {
        "exists": p.exists(),
        "path": str(p)
    }

paper = pub / "tables_input" / "paper_main_metrics.csv"
if paper.exists():
    rows = list(csv.DictReader(open(paper)))
    report["paper_main_metrics_rows"] = rows

plot = pub / "figures_input" / "plot_round_metrics.csv"
if plot.exists():
    rows = list(csv.DictReader(open(plot)))
    report["plot_round_metrics_head"] = rows[:15]

for name in ["baseline_all_rounds_clean.json","label_flip_all_rounds_clean.json","backdoor_all_rounds_clean.json"]:
    p = pub / name.replace(".json","") / name
    if not p.exists():
        p = pub / name
    if p.exists():
        try:
            report[name] = json.load(open(p))
        except Exception as e:
            report[name] = {"error": str(e), "path": str(p)}

(out / "RECOVERY_REPORT.json").write_text(json.dumps(report, indent=2))
PY

echo "===== RECOVERED FILES ====="
find "$OUT" -maxdepth 2 -type f | sort

echo
echo "===== PAPER MAIN METRICS ====="
cat "$OUT/publication_bundle/paper_main_metrics.csv" 2>/dev/null || true

echo
echo "===== PLOT ROUND METRICS HEAD ====="
sed -n '1,20p' "$OUT/publication_bundle/plot_round_metrics.csv" 2>/dev/null || true

echo
echo "OUT=$OUT"
