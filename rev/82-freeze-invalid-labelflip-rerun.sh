#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

COMPARE=$(cat rev/.last_n20_compare_dir)
OUT="$RUN_DIR/invalid_labelflip_rerun_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

cp -f "$COMPARE/manifests/label_flip_collect_summary.json" "$OUT/" 2>/dev/null || true
cp -f "$RUN_DIR"/summary/p8_labelflip_round*_summary_20260310_13*.json "$OUT/" 2>/dev/null || true
cp -f "$RUN_DIR"/summary/p8_labelflip_round*_clients_20260310_13*.csv "$OUT/" 2>/dev/null || true
cp -f "$RUN_DIR"/summary/p8_labelflip_all_rounds_20260310_131217.json "$OUT/" 2>/dev/null || true
cp -f "$RUN_DIR"/summary/p8_labelflip_1_5_table_20260310_131217.csv "$OUT/" 2>/dev/null || true

python3 - <<'PY' "$OUT"
import json, csv, sys
from pathlib import Path

out = Path(sys.argv[1])

pooled = out / "p8_labelflip_all_rounds_20260310_131217.json"
latest_clean = Path("/home/ubuntu/byz-fed-ids-5g/rev/runs/rev_20260303_152740_5g/final_graph_inputs_20260310_030714/label_flip/label_flip_all_rounds_clean.json")

report = {"status": "invalid_rerun_detected"}

if pooled.exists():
    report["current_rerun"] = json.loads(pooled.read_text())
if latest_clean.exists():
    report["reference_locked"] = json.loads(latest_clean.read_text())

cur = report.get("current_rerun", {})
ref = report.get("reference_locked", {})

def grab(d, path, default=None):
    x = d
    for p in path:
        if not isinstance(x, dict) or p not in x:
            return default
        x = x[p]
    return x

report["diagnosis"] = {
    "current_f1_byz_avg": grab(cur, ["f1_byz", "avg"]),
    "reference_f1_byz_avg": grab(ref, ["f1_byz", "avg"]),
    "current_fpr_byz_avg": grab(cur, ["fpr_byz", "avg"]),
    "reference_fpr_byz_avg": grab(ref, ["fpr_byz", "avg"]),
    "conclusion": "label_flip attack not effectively injected in current rerun"
}

(out / "INVALID_LABELFLIP_REPORT.json").write_text(json.dumps(report, indent=2))

readme = []
readme.append("RERUN LABEL_FLIP A EXCLURE")
readme.append("")
readme.append("Constat:")
readme.append(f"- current_f1_byz_avg={report['diagnosis']['current_f1_byz_avg']}")
readme.append(f"- reference_f1_byz_avg={report['diagnosis']['reference_f1_byz_avg']}")
readme.append(f"- current_fpr_byz_avg={report['diagnosis']['current_fpr_byz_avg']}")
readme.append(f"- reference_fpr_byz_avg={report['diagnosis']['reference_fpr_byz_avg']}")
readme.append("")
readme.append("Conclusion: l'attaque label_flip n'est pas active dans ce rerun.")
(out / "README.txt").write_text("\n".join(readme) + "\n")

print("INVALID_DIR=", out)
print("REPORT=", out / "INVALID_LABELFLIP_REPORT.json")
PY
