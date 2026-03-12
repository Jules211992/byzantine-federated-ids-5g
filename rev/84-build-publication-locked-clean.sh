#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SRC=$(ls -dt "$RUN_DIR"/final_graph_inputs_* 2>/dev/null | head -n 1 || true)
[ -n "${SRC:-}" ] || { echo "ERROR: final_graph_inputs introuvable"; exit 1; }

COMPARE=$(cat rev/.last_n20_compare_dir)
[ -d "${COMPARE:-}" ] || { echo "ERROR: COMPARE introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/publication_locked_clean_$TS"

mkdir -p \
  "$OUT"/baseline \
  "$OUT"/label_flip \
  "$OUT"/backdoor \
  "$OUT"/raw/label_flip \
  "$OUT"/figures_input \
  "$OUT"/tables_input \
  "$OUT"/manifest

cp -f "$SRC"/baseline/baseline_all_rounds_clean.json "$OUT"/baseline/
cp -f "$SRC"/backdoor/backdoor_all_rounds_clean.json "$OUT"/backdoor/

for r in 01 02 03 04 05; do
  cp -f "$SRC"/baseline/round${r}_clients.csv "$OUT"/baseline/
done

for r in 01 02 03 04 05; do
  cp -f "$SRC"/backdoor/round${r}_clients.csv "$OUT"/backdoor/
  cp -f "$SRC"/backdoor/round${r}_summary.json "$OUT"/backdoor/
done

for r in 01 02 03 04 05; do
  f_csv=$(ls -t "$RUN_DIR"/summary/p8_labelflip_round${r}_clients_*.csv 2>/dev/null | head -n 1 || true)
  f_json=$(ls -t "$RUN_DIR"/summary/p8_labelflip_round${r}_summary_*.json 2>/dev/null | head -n 1 || true)
  [ -n "${f_csv:-}" ] || { echo "ERROR: label_flip round${r} csv introuvable"; exit 1; }
  [ -n "${f_json:-}" ] || { echo "ERROR: label_flip round${r} summary introuvable"; exit 1; }
  cp -f "$f_csv" "$OUT"/label_flip/round${r}_clients.csv
  cp -f "$f_json" "$OUT"/label_flip/round${r}_summary.json
done

LF_POOLED=$(ls -t "$RUN_DIR"/summary/p8_labelflip_all_rounds_*.json 2>/dev/null | head -n 1 || true)
LF_TABLE=$(ls -t "$RUN_DIR"/summary/p8_labelflip_1_5_table_*.csv 2>/dev/null | head -n 1 || true)
[ -n "${LF_POOLED:-}" ] || { echo "ERROR: label_flip pooled json introuvable"; exit 1; }
[ -n "${LF_TABLE:-}" ] || { echo "ERROR: label_flip table csv introuvable"; exit 1; }

cp -f "$LF_POOLED" "$OUT"/label_flip/label_flip_all_rounds_clean.json
cp -f "$LF_TABLE" "$OUT"/label_flip/label_flip_1_5_table.csv

rm -rf "$OUT"/raw/label_flip/label_flip_raw
cp -rf "$COMPARE"/label_flip_raw "$OUT"/raw/label_flip/
cp -f "$COMPARE"/manifests/label_flip_collect_summary.json "$OUT"/raw/label_flip/ 2>/dev/null || true

python3 - "$OUT" <<'PY'
import csv, json, math, sys
from pathlib import Path

out = Path(sys.argv[1])

def pct(vals, p):
    vals = sorted(vals)
    n = len(vals)
    if n == 1:
        return vals[0]
    k = (n - 1) * p
    lo = int(math.floor(k))
    hi = int(math.ceil(k))
    if lo == hi:
        return vals[lo]
    return vals[lo] + (vals[hi] - vals[lo]) * (k - lo)

def load_csv_rows(path):
    rows = []
    with open(path, newline="") as f:
        rd = csv.DictReader(f)
        for row in rd:
            rows.append(row)
    return rows

def to_float(x):
    if x in (None, "", "None"):
        return None
    return float(x)

plot_rows = []

for r in range(1, 6):
    p = out / "baseline" / f"round{r:02d}_clients.csv"
    rows = load_csv_rows(p)
    f1 = [to_float(x["f1"]) for x in rows if to_float(x["f1"]) is not None]
    fpr = [to_float(x["fpr"]) for x in rows if to_float(x["fpr"]) is not None]
    ipfs = [to_float(x["ipfs_ms"]) for x in rows if to_float(x["ipfs_ms"]) is not None]
    tx = [to_float(x["tx_ms"]) for x in rows if to_float(x["tx_ms"]) is not None]
    total = [to_float(x["total_ms"]) for x in rows if to_float(x["total_ms"]) is not None]
    plot_rows.append({
        "scenario": "baseline",
        "round": r,
        "f1_avg": sum(f1) / len(f1),
        "f1_honest_avg": "",
        "f1_byz_avg": "",
        "fpr_avg": sum(fpr) / len(fpr),
        "fpr_honest_avg": "",
        "fpr_byz_avg": "",
        "ipfs_ms_p50": pct(ipfs, 0.50),
        "tx_ms_p50": pct(tx, 0.50),
        "total_ms_p50": pct(total, 0.50),
        "total_ms_p95": pct(total, 0.95),
        "n_clients": len(rows),
        "n_honest": len(rows),
        "n_byz": 0
    })

for r in range(1, 6):
    p = out / "label_flip" / f"round{r:02d}_clients.csv"
    rows = load_csv_rows(p)
    honest = [x for x in rows if int(float(x["is_byz"])) == 0]
    byz = [x for x in rows if int(float(x["is_byz"])) == 1]
    f1_all = [to_float(x["f1"]) for x in rows if to_float(x["f1"]) is not None]
    f1_h = [to_float(x["f1"]) for x in honest if to_float(x["f1"]) is not None]
    f1_b = [to_float(x["f1"]) for x in byz if to_float(x["f1"]) is not None]
    fpr_all = [to_float(x["fpr"]) for x in rows if to_float(x["fpr"]) is not None]
    fpr_h = [to_float(x["fpr"]) for x in honest if to_float(x["fpr"]) is not None]
    fpr_b = [to_float(x["fpr"]) for x in byz if to_float(x["fpr"]) is not None]
    plot_rows.append({
        "scenario": "label_flip",
        "round": r,
        "f1_avg": sum(f1_all) / len(f1_all),
        "f1_honest_avg": sum(f1_h) / len(f1_h),
        "f1_byz_avg": sum(f1_b) / len(f1_b),
        "fpr_avg": sum(fpr_all) / len(fpr_all),
        "fpr_honest_avg": sum(fpr_h) / len(fpr_h),
        "fpr_byz_avg": sum(fpr_b) / len(fpr_b),
        "ipfs_ms_p50": "",
        "tx_ms_p50": "",
        "total_ms_p50": "",
        "total_ms_p95": "",
        "n_clients": len(rows),
        "n_honest": len(honest),
        "n_byz": len(byz)
    })

for r in range(1, 6):
    p = out / "backdoor" / f"round{r:02d}_clients.csv"
    rows = load_csv_rows(p)
    honest = [x for x in rows if int(float(x["is_byz"])) == 0]
    byz = [x for x in rows if int(float(x["is_byz"])) == 1]
    f1_all = [to_float(x["f1"]) for x in rows if to_float(x["f1"]) is not None]
    f1_h = [to_float(x["f1"]) for x in honest if to_float(x["f1"]) is not None]
    f1_b = [to_float(x["f1"]) for x in byz if to_float(x["f1"]) is not None]
    fpr_all = [to_float(x["fpr"]) for x in rows if to_float(x["fpr"]) is not None]
    fpr_h = [to_float(x["fpr"]) for x in honest if to_float(x["fpr"]) is not None]
    fpr_b = [to_float(x["fpr"]) for x in byz if to_float(x["fpr"]) is not None]
    ipfs = [to_float(x["ipfs_ms"]) for x in rows if to_float(x["ipfs_ms"]) is not None]
    tx = [to_float(x["tx_ms"]) for x in rows if to_float(x["tx_ms"]) is not None]
    total = [to_float(x["total_ms"]) for x in rows if to_float(x["total_ms"]) is not None]
    plot_rows.append({
        "scenario": "backdoor",
        "round": r,
        "f1_avg": sum(f1_all) / len(f1_all),
        "f1_honest_avg": sum(f1_h) / len(f1_h),
        "f1_byz_avg": sum(f1_b) / len(f1_b),
        "fpr_avg": sum(fpr_all) / len(fpr_all),
        "fpr_honest_avg": sum(fpr_h) / len(fpr_h),
        "fpr_byz_avg": sum(fpr_b) / len(fpr_b),
        "ipfs_ms_p50": pct(ipfs, 0.50),
        "tx_ms_p50": pct(tx, 0.50),
        "total_ms_p50": pct(total, 0.50),
        "total_ms_p95": pct(total, 0.95),
        "n_clients": len(rows),
        "n_honest": len(honest),
        "n_byz": len(byz)
    })

plot_csv = out / "figures_input" / "plot_round_metrics.csv"
with open(plot_csv, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=[
        "scenario","round","f1_avg","f1_honest_avg","f1_byz_avg",
        "fpr_avg","fpr_honest_avg","fpr_byz_avg","ipfs_ms_p50","tx_ms_p50",
        "total_ms_p50","total_ms_p95","n_clients","n_honest","n_byz"
    ])
    w.writeheader()
    for row in sorted(plot_rows, key=lambda x: (x["scenario"], x["round"])):
        w.writerow(row)

baseline = json.loads((out / "baseline" / "baseline_all_rounds_clean.json").read_text())
labelflip = json.loads((out / "label_flip" / "label_flip_all_rounds_clean.json").read_text())
backdoor = json.loads((out / "backdoor" / "backdoor_all_rounds_clean.json").read_text())

paper_table = out / "tables_input" / "paper_main_metrics.csv"
with open(paper_table, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow([
        "scenario","honest_f1_avg","byzantine_f1_avg",
        "honest_fpr_avg","byzantine_fpr_avg",
        "ipfs_ms_p50","tx_ms_p50","total_ms_p50"
    ])
    w.writerow([
        "Baseline",
        baseline["f1"]["avg"], "",
        baseline["fpr"]["avg"], "",
        baseline["ipfs_ms"]["p50"], baseline["tx_ms"]["p50"], baseline["total_ms"]["p50"]
    ])
    w.writerow([
        "LabelFlip",
        labelflip["f1_honest"]["avg"], labelflip["f1_byz"]["avg"],
        labelflip["fpr_honest"]["avg"], labelflip["fpr_byz"]["avg"],
        "", "", ""
    ])
    w.writerow([
        "Backdoor",
        backdoor["f1_honest"]["avg"], backdoor["f1_byz"]["avg"],
        backdoor["fpr_honest"]["avg"], backdoor["fpr_byz"]["avg"],
        backdoor["ipfs_ms"]["p50"], backdoor["tx_ms"]["p50"], backdoor["total_ms"]["p50"]
    ])

manifest = {
    "locked_dataset": str(out),
    "baseline_summary": str(out / "baseline" / "baseline_all_rounds_clean.json"),
    "label_flip_summary": str(out / "label_flip" / "label_flip_all_rounds_clean.json"),
    "backdoor_summary": str(out / "backdoor" / "backdoor_all_rounds_clean.json"),
    "label_flip_raw_dir": str(out / "raw" / "label_flip" / "label_flip_raw"),
    "plot_csv": str(plot_csv),
    "paper_table_csv": str(paper_table)
}
(out / "manifest" / "LOCKED_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = "\n".join([
    "DATASET PUBLICATION VERROUILLE ET PROPRE",
    f"baseline_rows={baseline['n_rows']}",
    f"label_flip_rows={labelflip['n_rows']}",
    f"backdoor_rows={backdoor['n_rows']}",
    "label_flip_source=corrected_attack_aware_rerun",
    "Ce dossier doit servir de source unique pour les figures et tableaux du papier."
])
(out / "README.txt").write_text(readme + "\n")

print("LOCKED_OUT=", out)
print("README=", out / "README.txt")
print("MANIFEST=", out / "manifest" / "LOCKED_MANIFEST.json")
print("PLOT_CSV=", plot_csv)
print("PAPER_TABLE=", paper_table)
PY
