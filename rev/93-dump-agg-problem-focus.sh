#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

LIVE=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* 2>/dev/null | head -n 1 || true)
[ -n "${LIVE:-}" ] || { echo "ERROR: agg_compare_n20_live introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

AGG=$(cat rev/.last_n20_agg_compare_dir 2>/dev/null || true)
[ -n "${AGG:-}" ] || { echo "ERROR: .last_n20_agg_compare_dir introuvable"; exit 1; }

OUT="$RUN_DIR/agg_problem_focus_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

cp -f "$LIVE/tables_input/agg_compare_summary_live.csv" "$OUT/" 2>/dev/null || true
cp -f "$LIVE/tables_input/agg_compare_paper_table_live.csv" "$OUT/" 2>/dev/null || true
cp -f "$LIVE/figures_input/agg_compare_round_metrics_live.csv" "$OUT/" 2>/dev/null || true
cp -f "$LIVE/manifest/LIVE_BENCHMARK_MANIFEST.json" "$OUT/" 2>/dev/null || true

cp -f "$BUNDLE/tables_input/paper_main_metrics.csv" "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE/figures_input/plot_round_metrics.csv" "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE/baseline/baseline_all_rounds_clean.json" "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE/label_flip/label_flip_all_rounds_clean.json" "$OUT/" 2>/dev/null || true
cp -f "$BUNDLE/backdoor/backdoor_all_rounds_clean.json" "$OUT/" 2>/dev/null || true

cp -f "$AGG/tables_input/agg_compare_summary_native.csv" "$OUT/" 2>/dev/null || true
cp -f "$AGG/tables_input/agg_compare_paper_table_native.csv" "$OUT/" 2>/dev/null || true
cp -f "$AGG/figures_input/agg_compare_round_metrics_native.csv" "$OUT/" 2>/dev/null || true
cp -f "$AGG/manifest/NATIVE_REPLAY_MANIFEST.json" "$OUT/" 2>/dev/null || true

python3 - <<'PY' "$RUN_DIR" "$LIVE" "$BUNDLE" "$AGG" "$OUT"
import csv
import json
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
live = Path(sys.argv[2])
bundle = Path(sys.argv[3])
agg = Path(sys.argv[4])
out = Path(sys.argv[5])

def read_json(p):
    return json.loads(Path(p).read_text())

def read_csv_rows(p):
    with open(p, newline="") as f:
        return list(csv.DictReader(f))

bundle_ref = {
    "baseline": read_json(bundle / "baseline" / "baseline_all_rounds_clean.json"),
    "label_flip": read_json(bundle / "label_flip" / "label_flip_all_rounds_clean.json"),
    "backdoor": read_json(bundle / "backdoor" / "backdoor_all_rounds_clean.json"),
}

live_rows = read_csv_rows(live / "figures_input" / "agg_compare_round_metrics_live.csv")
native_rows = []
native_csv = agg / "figures_input" / "agg_compare_round_metrics_native.csv"
if native_csv.exists():
    native_rows = read_csv_rows(native_csv)

interesting = {
    "live_multikrum_backdoor_r04": live / "multikrum" / "raw" / "backdoor_multikrum_r04.json",
    "live_multikrum_backdoor_r05": live / "multikrum" / "raw" / "backdoor_multikrum_r05.json",
    "live_fedavg_labelflip_r05": live / "fedavg" / "raw" / "label_flip_fedavg_r05.json",
    "live_trimmedmean_backdoor_r05": live / "trimmedmean" / "raw" / "backdoor_trimmedmean_r05.json",
}

picked = {}
for k, p in interesting.items():
    if p.exists():
        picked[k] = read_json(p)

summary = {
    "run_dir": str(run_dir),
    "live_dir": str(live),
    "bundle_dir": str(bundle),
    "agg_dir": str(agg),
    "bundle_reference": {
        "baseline_f1_avg": bundle_ref["baseline"]["f1"]["avg"],
        "baseline_fpr_avg": bundle_ref["baseline"]["fpr"]["avg"],
        "label_flip_honest_f1_avg": bundle_ref["label_flip"]["f1_honest"]["avg"],
        "label_flip_byz_f1_avg": bundle_ref["label_flip"]["f1_byz"]["avg"],
        "label_flip_honest_fpr_avg": bundle_ref["label_flip"]["fpr_honest"]["avg"],
        "label_flip_byz_fpr_avg": bundle_ref["label_flip"]["fpr_byz"]["avg"],
        "backdoor_honest_f1_avg": bundle_ref["backdoor"]["f1_honest"]["avg"],
        "backdoor_byz_f1_avg": bundle_ref["backdoor"]["f1_byz"]["avg"],
        "backdoor_honest_fpr_avg": bundle_ref["backdoor"]["fpr_honest"]["avg"],
        "backdoor_byz_fpr_avg": bundle_ref["backdoor"]["fpr_byz"]["avg"],
    },
    "live_rows_count": len(live_rows),
    "native_rows_count": len(native_rows),
    "picked_jsons": picked,
}

(out / "FOCUS_SUMMARY.json").write_text(json.dumps(summary, indent=2))

with open(out / "FOCUS_NOTES.txt", "w") as f:
    f.write("FOCUS DATASET FOR AGGREGATOR PROBLEM\n")
    f.write(f"RUN_DIR={run_dir}\n")
    f.write(f"LIVE={live}\n")
    f.write(f"BUNDLE={bundle}\n")
    f.write(f"AGG={agg}\n")
    f.write("\nREFERENCE FROM BUNDLE\n")
    f.write(f"baseline_f1_avg={bundle_ref['baseline']['f1']['avg']}\n")
    f.write(f"baseline_fpr_avg={bundle_ref['baseline']['fpr']['avg']}\n")
    f.write(f"label_flip_honest_f1_avg={bundle_ref['label_flip']['f1_honest']['avg']}\n")
    f.write(f"label_flip_byz_f1_avg={bundle_ref['label_flip']['f1_byz']['avg']}\n")
    f.write(f"label_flip_honest_fpr_avg={bundle_ref['label_flip']['fpr_honest']['avg']}\n")
    f.write(f"label_flip_byz_fpr_avg={bundle_ref['label_flip']['fpr_byz']['avg']}\n")
    f.write(f"backdoor_honest_f1_avg={bundle_ref['backdoor']['f1_honest']['avg']}\n")
    f.write(f"backdoor_byz_f1_avg={bundle_ref['backdoor']['f1_byz']['avg']}\n")
    f.write(f"backdoor_honest_fpr_avg={bundle_ref['backdoor']['fpr_honest']['avg']}\n")
    f.write(f"backdoor_byz_fpr_avg={bundle_ref['backdoor']['fpr_byz']['avg']}\n")

print(f"OUT={out}")
print(f"FOCUS_SUMMARY={out/'FOCUS_SUMMARY.json'}")
print(f"FOCUS_NOTES={out/'FOCUS_NOTES.txt'}")
PY

FOCUS=$(ls -dt "$RUN_DIR"/agg_problem_focus_* | head -n 1)

echo "===== FOCUS NOTES ====="
cat "$FOCUS/FOCUS_NOTES.txt"

echo
echo "===== LIVE SUMMARY CSV ====="
cat "$FOCUS/agg_compare_summary_live.csv"

echo
echo "===== LIVE PAPER CSV ====="
cat "$FOCUS/agg_compare_paper_table_live.csv"

echo
echo "===== BUNDLE PAPER TABLE ====="
cat "$FOCUS/paper_main_metrics.csv"

echo
echo "===== BACKDOOR MULTIKRUM R04 ====="
cat "$LIVE/multikrum/raw/backdoor_multikrum_r04.json"

echo
echo "===== BACKDOOR MULTIKRUM R05 ====="
cat "$LIVE/multikrum/raw/backdoor_multikrum_r05.json"

echo
echo "===== LABEL_FLIP FEDAVG R05 ====="
cat "$LIVE/fedavg/raw/label_flip_fedavg_r05.json"
