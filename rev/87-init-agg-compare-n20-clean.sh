#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/agg_compare_n20_final_$TS"

mkdir -p \
  "$OUT"/baseline \
  "$OUT"/label_flip \
  "$OUT"/backdoor \
  "$OUT"/fedavg/raw \
  "$OUT"/multikrum/raw \
  "$OUT"/trimmedmean/raw \
  "$OUT"/summary \
  "$OUT"/figures_input \
  "$OUT"/tables_input \
  "$OUT"/manifest \
  "$OUT"/logs

cp -f "$BUNDLE"/baseline/baseline_all_rounds_clean.json "$OUT"/baseline/
cp -f "$BUNDLE"/label_flip/label_flip_all_rounds_clean.json "$OUT"/label_flip/
cp -f "$BUNDLE"/backdoor/backdoor_all_rounds_clean.json "$OUT"/backdoor/
cp -f "$BUNDLE"/figures_input/plot_round_metrics.csv "$OUT"/figures_input/
cp -f "$BUNDLE"/tables_input/paper_main_metrics.csv "$OUT"/tables_input/

printf '%s\n' "$OUT" > rev/.last_n20_agg_compare_dir

python3 - <<'PY' "$OUT" "$RUN_DIR" "$BUNDLE"
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
run_dir = Path(sys.argv[2])
bundle = Path(sys.argv[3])

manifest = {
    "agg_compare_dir": str(out),
    "run_dir": str(run_dir),
    "source_bundle": str(bundle),
    "baseline_summary": str(out / "baseline" / "baseline_all_rounds_clean.json"),
    "label_flip_summary": str(out / "label_flip" / "label_flip_all_rounds_clean.json"),
    "backdoor_summary": str(out / "backdoor" / "backdoor_all_rounds_clean.json"),
    "plot_csv_reference": str(out / "figures_input" / "plot_round_metrics.csv"),
    "paper_table_reference": str(out / "tables_input" / "paper_main_metrics.csv"),
    "aggregators": {
        "fedavg": str(out / "fedavg" / "raw"),
        "multikrum": str(out / "multikrum" / "raw"),
        "trimmedmean": str(out / "trimmedmean" / "raw")
    }
}

(out / "manifest" / "AGG_COMPARE_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = "\n".join([
    "DOSSIER DEDIE A LA COMPARAISON N20 DES AGREGATEURS",
    f"run_dir={run_dir}",
    f"source_bundle={bundle}",
    f"agg_compare_dir={out}",
    "aggregateurs=FedAvg,MultiKrum,TrimmedMean",
    "scenarios=baseline,label_flip,backdoor",
    "ce dossier est reserve uniquement a la comparaison finale des agregateurs"
])
(out / "README.txt").write_text(readme + "\n")

print("AGG_COMPARE_DIR=", out)
print("README=", out / "README.txt")
print("MANIFEST=", out / "manifest" / "AGG_COMPARE_MANIFEST.json")
PY
