#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SRC=$(ls -dt "$RUN_DIR"/final_graph_inputs_* 2>/dev/null | head -n 1 || true)
[ -n "${SRC:-}" ] || { echo "ERROR: final_graph_inputs introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/publication_locked_$TS"
mkdir -p "$OUT"/{baseline,label_flip,backdoor,figures_input,tables_input,manifest}

cp -f "$SRC"/baseline/baseline_all_rounds_clean.json "$OUT"/baseline/
cp -f "$SRC"/label_flip/label_flip_all_rounds_clean.json "$OUT"/label_flip/
cp -f "$SRC"/backdoor/backdoor_all_rounds_clean.json "$OUT"/backdoor/
cp -f "$SRC"/plot_round_metrics.csv "$OUT"/figures_input/

for f in "$SRC"/baseline/round*_clients.csv; do cp -f "$f" "$OUT"/baseline/; done
for f in "$SRC"/label_flip/round*_clients.csv "$SRC"/label_flip/round*_summary.json; do cp -f "$f" "$OUT"/label_flip/; done
for f in "$SRC"/backdoor/round*_clients.csv "$SRC"/backdoor/round*_summary.json; do cp -f "$f" "$OUT"/backdoor/; done

python3 - "$OUT" <<'PY'
import json, csv, sys
from pathlib import Path

out = Path(sys.argv[1])

baseline = json.loads((out / "baseline" / "baseline_all_rounds_clean.json").read_text())
labelflip = json.loads((out / "label_flip" / "label_flip_all_rounds_clean.json").read_text())
backdoor = json.loads((out / "backdoor" / "backdoor_all_rounds_clean.json").read_text())

paper_table = [
    {
        "scenario": "Baseline",
        "honest_f1_avg": round(baseline["f1"]["avg"], 6),
        "byzantine_f1_avg": "",
        "honest_fpr_avg": round(baseline["fpr"]["avg"], 6),
        "byzantine_fpr_avg": "",
        "ipfs_ms_p50": round(baseline["ipfs_ms"]["p50"], 3),
        "tx_ms_p50": round(baseline["tx_ms"]["p50"], 3),
        "total_ms_p50": round(baseline["total_ms"]["p50"], 3)
    },
    {
        "scenario": "LabelFlip",
        "honest_f1_avg": round(labelflip["f1_honest"]["avg"], 6),
        "byzantine_f1_avg": round(labelflip["f1_byz"]["avg"], 6),
        "honest_fpr_avg": round(labelflip["fpr_honest"]["avg"], 6),
        "byzantine_fpr_avg": round(labelflip["fpr_byz"]["avg"], 6),
        "ipfs_ms_p50": "",
        "tx_ms_p50": "",
        "total_ms_p50": ""
    },
    {
        "scenario": "Backdoor",
        "honest_f1_avg": round(backdoor["f1_honest"]["avg"], 6),
        "byzantine_f1_avg": round(backdoor["f1_byz"]["avg"], 6),
        "honest_fpr_avg": round(backdoor["fpr_honest"]["avg"], 6),
        "byzantine_fpr_avg": round(backdoor["fpr_byz"]["avg"], 6),
        "ipfs_ms_p50": round(backdoor["ipfs_ms"]["p50"], 3),
        "tx_ms_p50": round(backdoor["tx_ms"]["p50"], 3),
        "total_ms_p50": round(backdoor["total_ms"]["p50"], 3)
    }
]

with open(out / "tables_input" / "paper_main_metrics.csv", "w", newline="") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "scenario",
            "honest_f1_avg","byzantine_f1_avg",
            "honest_fpr_avg","byzantine_fpr_avg",
            "ipfs_ms_p50","tx_ms_p50","total_ms_p50"
        ]
    )
    w.writeheader()
    for r in paper_table:
        w.writerow(r)

manifest = {
    "locked_dataset": str(out),
    "baseline_summary": str(out / "baseline" / "baseline_all_rounds_clean.json"),
    "label_flip_summary": str(out / "label_flip" / "label_flip_all_rounds_clean.json"),
    "backdoor_summary": str(out / "backdoor" / "backdoor_all_rounds_clean.json"),
    "plot_csv": str(out / "figures_input" / "plot_round_metrics.csv"),
    "paper_table_csv": str(out / "tables_input" / "paper_main_metrics.csv")
}

(out / "manifest" / "LOCKED_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = []
readme.append("DATASET PUBLICATION VERROUILLE")
readme.append(f"baseline_rows={baseline['n_rows']}")
readme.append(f"label_flip_rows={labelflip['n_rows']}")
readme.append(f"backdoor_rows={backdoor['n_rows']}")
readme.append("Ce dossier doit servir de source unique pour les figures et tableaux du papier.")
(out / "README.txt").write_text("\n".join(readme) + "\n")
PY

echo "LOCKED_OUT=$OUT"
find "$OUT" -maxdepth 2 -type f | sort
