#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

CLEAN=$(ls -dt "$RUN_DIR"/clean_agg_r1_weighted_* 2>/dev/null | head -n 1 || true)
[ -n "${CLEAN:-}" ] || { echo "ERROR: clean_agg_r1_weighted introuvable"; exit 1; }

OUT="$RUN_DIR/clean_protocol_gap_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

python3 - <<'PY' "$RUN_DIR" "$BUNDLE" "$CLEAN" "$OUT"
import csv
import json
import math
import re
import sys
from pathlib import Path

run_dir = Path(sys.argv[1])
bundle = Path(sys.argv[2])
clean = Path(sys.argv[3])
out = Path(sys.argv[4])

def load_json(p):
    return json.loads(Path(p).read_text())

def load_csv_rows(p):
    with open(p, newline="") as f:
        return list(csv.DictReader(f))

def fnum(x):
    if x is None:
        return None
    s = str(x).strip()
    if s == "":
        return None
    return float(s)

paper = load_csv_rows(bundle / "tables_input" / "paper_main_metrics.csv")
plot = load_csv_rows(bundle / "figures_input" / "plot_round_metrics.csv")
clean_summary = load_csv_rows(clean / "tables_input" / "clean_r1_weighted_summary.csv")
baseline_json = load_json(bundle / "baseline" / "baseline_all_rounds_clean.json")

baseline_inputs = baseline_json.get("inputs", [])
baseline_round1_csv = None
for p in baseline_inputs:
    if "round01" in p:
        baseline_round1_csv = p
        break

baseline_round1_rows = []
if baseline_round1_csv and Path(baseline_round1_csv).exists():
    baseline_round1_rows = load_csv_rows(baseline_round1_csv)

def avg(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None

def weighted_f1_from_rows(rows):
    tp = fp = fn = tn = 0
    for r in rows:
        tp += int(float(r.get("tp", 0) or 0))
        fp += int(float(r.get("fp", 0) or 0))
        fn += int(float(r.get("fn", 0) or 0))
        tn += int(float(r.get("tn", 0) or 0))
    n = tp + fp + fn + tn
    acc = (tp + tn) / n if n else None
    prec = tp / (tp + fp) if (tp + fp) else 0.0
    rec = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0.0
    fpr = fp / (fp + tn) if (fp + tn) else 0.0
    return {
        "tp": tp,
        "fp": fp,
        "fn": fn,
        "tn": tn,
        "n": n,
        "accuracy": acc,
        "precision": prec,
        "recall": rec,
        "f1": f1,
        "fpr": fpr
    }

baseline_r1_local = weighted_f1_from_rows(baseline_round1_rows)

plot_baseline_r1 = next((r for r in plot if r.get("scenario") == "baseline" and str(r.get("round")) == "1"), None)
paper_baseline = next((r for r in paper if str(r.get("scenario","")).lower() == "baseline"), None)
clean_baseline = next((r for r in clean_summary if r.get("aggregator") == "fedavg"), None)

gap = {
    "reference_bundle_baseline_avg_f1": fnum(paper_baseline["honest_f1_avg"]) if paper_baseline else None,
    "reference_bundle_baseline_avg_fpr": fnum(paper_baseline["honest_fpr_avg"]) if paper_baseline else None,
    "reference_plot_round1_f1_avg": fnum(plot_baseline_r1["f1_avg"]) if plot_baseline_r1 else None,
    "reference_plot_round1_fpr_avg": fnum(plot_baseline_r1["fpr_avg"]) if plot_baseline_r1 else None,
    "recomputed_from_round01_clients_f1": baseline_r1_local["f1"],
    "recomputed_from_round01_clients_fpr": baseline_r1_local["fpr"],
    "clean_global_fedavg_weighted_f1": fnum(clean_baseline["weighted_f1"]) if clean_baseline else None,
    "clean_global_fedavg_f1": fnum(clean_baseline["f1"]) if clean_baseline else None,
    "clean_global_fedavg_accuracy": fnum(clean_baseline["accuracy"]) if clean_baseline else None,
    "clean_global_fedavg_fpr": fnum(clean_baseline["fpr"]) if clean_baseline else None,
    "clean_global_fedavg_roc_auc": fnum(clean_baseline["roc_auc"]) if clean_baseline else None
}

notes = []
notes.append("REFERENCE bundle baseline_all_rounds_clean.json = moyenne pooled sur 100 lignes client-level")
notes.append("REFERENCE plot_round_metrics.csv baseline round1 = moyenne round1 client-level")
notes.append("RECOMPUTED round01_clients.csv = reconstruction a partir du csv client-level du round 1")
notes.append("CLEAN benchmark = evaluation sur global_test_X/global_test_y concatene")
notes.append("Si round01_clients.csv et plot_round_metrics.csv matchent, alors la divergence vient bien du protocole global concatene et non d'une erreur de calcul simple")
notes.append("Si clean global reste plus bas, il faut ensuite aligner soit le threshold, soit la logique d'evaluation, soit la construction du global test, soit l'etat du modele")

report = {
    "run_dir": str(run_dir),
    "bundle": str(bundle),
    "clean": str(clean),
    "baseline_round1_csv": baseline_round1_csv,
    "baseline_round1_n_rows": len(baseline_round1_rows),
    "baseline_round1_recomputed": baseline_r1_local,
    "gap_summary": gap,
    "notes": notes
}

(out / "CLEAN_PROTOCOL_GAP.json").write_text(json.dumps(report, indent=2))

with open(out / "CLEAN_PROTOCOL_GAP.txt", "w") as f:
    f.write("CLEAN PROTOCOL GAP AUDIT\n")
    f.write(f"RUN_DIR={run_dir}\n")
    f.write(f"BUNDLE={bundle}\n")
    f.write(f"CLEAN={clean}\n")
    f.write(f"BASELINE_ROUND1_CSV={baseline_round1_csv}\n")
    f.write(f"BASELINE_ROUND1_N_ROWS={len(baseline_round1_rows)}\n\n")
    for k, v in gap.items():
        f.write(f"{k}={v}\n")
    f.write("\n")
    for n in notes:
        f.write(f"- {n}\n")

print("OUT=", out)
print("REPORT_JSON=", out / "CLEAN_PROTOCOL_GAP.json")
print("REPORT_TXT=", out / "CLEAN_PROTOCOL_GAP.txt")
PY

LATEST=$(ls -dt "$RUN_DIR"/clean_protocol_gap_* | head -n 1)

echo "===== GAP TXT ====="
cat "$LATEST/CLEAN_PROTOCOL_GAP.txt"

echo
echo "===== GAP JSON ====="
cat "$LATEST/CLEAN_PROTOCOL_GAP.json"
