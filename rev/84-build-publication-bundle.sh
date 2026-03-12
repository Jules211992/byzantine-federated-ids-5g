#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SRC=$(ls -dt "$RUN_DIR"/final_graph_inputs_* 2>/dev/null | head -n 1 || true)
[ -n "${SRC:-}" ] || { echo "ERROR: final_graph_inputs introuvable"; exit 1; }

COMPARE=$(cat rev/.last_n20_compare_dir)
[ -d "${COMPARE:-}" ] || { echo "ERROR: COMPARE introuvable"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/publication_bundle_$TS"

mkdir -p \
  "$OUT"/baseline \
  "$OUT"/label_flip \
  "$OUT"/backdoor \
  "$OUT"/raw/label_flip \
  "$OUT"/raw/backdoor \
  "$OUT"/ipfs \
  "$OUT"/caliper \
  "$OUT"/figures_input \
  "$OUT"/tables_input \
  "$OUT"/manifest

cp -f "$SRC"/baseline/baseline_all_rounds_clean.json "$OUT"/baseline/
cp -f "$SRC"/backdoor/backdoor_all_rounds_clean.json "$OUT"/backdoor/

for r in 01 02 03 04 05; do
  f_csv=$(ls -t "$RUN_DIR"/summary/p7_baseline_round${r}_clients_*.csv 2>/dev/null | head -n 1 || true)
  f_lat=$(ls -t "$RUN_DIR"/summary/p7_baseline_round${r}_latency_pct_*.json 2>/dev/null | head -n 1 || true)
  [ -n "${f_csv:-}" ] || { echo "ERROR: baseline round${r} csv introuvable"; exit 1; }
  cp -f "$f_csv" "$OUT"/baseline/round${r}_clients.csv
  [ -n "${f_lat:-}" ] && cp -f "$f_lat" "$OUT"/baseline/round${r}_latency.json
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
[ -n "${LF_TABLE:-}" ] || { echo "ERROR: label_flip pooled table introuvable"; exit 1; }
cp -f "$LF_POOLED" "$OUT"/label_flip/label_flip_all_rounds_clean.json
cp -f "$LF_TABLE" "$OUT"/label_flip/label_flip_1_5_table.csv

for r in 01 02 03 04 05; do
  f_csv=$(ls -t "$RUN_DIR"/summary/p15_backdoor_round${r}_clients_*.csv 2>/dev/null | head -n 1 || true)
  f_json=$(ls -t "$RUN_DIR"/summary/p15_backdoor_round${r}_summary_*.json 2>/dev/null | head -n 1 || true)
  [ -n "${f_csv:-}" ] || { echo "ERROR: backdoor round${r} csv introuvable"; exit 1; }
  [ -n "${f_json:-}" ] || { echo "ERROR: backdoor round${r} summary introuvable"; exit 1; }
  cp -f "$f_csv" "$OUT"/backdoor/round${r}_clients.csv
  cp -f "$f_json" "$OUT"/backdoor/round${r}_summary.json
done

rm -rf "$OUT"/raw/label_flip/label_flip_raw
cp -rf "$COMPARE"/label_flip_raw "$OUT"/raw/label_flip/
cp -f "$COMPARE"/manifests/label_flip_collect_summary.json "$OUT"/raw/label_flip/ 2>/dev/null || true

for r in 01 02 03 04 05; do
  SRC_DIR="$RUN_DIR/p15_backdoor/round${r}/client_logs"
  if [ -d "$SRC_DIR" ]; then
    mkdir -p "$OUT/raw/backdoor/round${r}"
    find "$SRC_DIR" -maxdepth 1 -type f -name 'fl-ids-*.json' -exec cp -f {} "$OUT/raw/backdoor/round${r}/" \;
    find "$SRC_DIR" -maxdepth 1 -type f -name 'fl-byz-*.json' -exec cp -f {} "$OUT/raw/backdoor/round${r}/" \;
  fi
done

find "$HOME"/byz-fed-ids-5g \
  -type f \
  \( -iname '*ipfs*' -o -iname '*cid*' \) \
  ! -path "$OUT/*" \
  ! -path '*/node_modules/*' \
  ! -path '*/.git/*' \
  2>/dev/null | sort > "$OUT/ipfs/ipfs_candidates.txt"

while read -r f; do
  [ -n "$f" ] || continue
  rel="${f#$HOME/byz-fed-ids-5g/}"
  dest="$OUT/ipfs/files/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -f "$f" "$dest" 2>/dev/null || true
done < "$OUT/ipfs/ipfs_candidates.txt"

find "$HOME"/byz-fed-ids-5g \
  -type f \
  \( -iname '*.html' -o -iname '*caliper*.json' -o -iname '*benchmark*.json' -o -iname '*report*.json' \) \
  ! -path "$OUT/*" \
  ! -path '*/node_modules/*' \
  ! -path '*/.git/*' \
  2>/dev/null | sort > "$OUT/caliper/caliper_candidates.txt"

while read -r f; do
  [ -n "$f" ] || continue
  rel="${f#$HOME/byz-fed-ids-5g/}"
  dest="$OUT/caliper/files/$rel"
  mkdir -p "$(dirname "$dest")"
  cp -f "$f" "$dest" 2>/dev/null || true
done < "$OUT/caliper/caliper_candidates.txt"

python3 - "$OUT" "$BYZ_CLIENTS" <<'PY'
import csv, json, math, sys
from pathlib import Path

out = Path(sys.argv[1])
byz_clients = set(sys.argv[2].split())

def to_float(x):
    if x in (None, "", "None"):
        return None
    return float(x)

def pct(vals, p):
    vals = sorted(vals)
    n = len(vals)
    if n == 0:
        return None
    if n == 1:
        return vals[0]
    k = (n - 1) * p
    lo = int(math.floor(k))
    hi = int(math.ceil(k))
    if lo == hi:
        return vals[lo]
    return vals[lo] + (vals[hi] - vals[lo]) * (k - lo)

def avg(vals):
    vals = [v for v in vals if v is not None]
    return sum(vals) / len(vals) if vals else None

def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    vals = sorted(vals)
    n = len(vals)
    a = sum(vals) / n
    var = sum((x - a) * (x - a) for x in vals) / n
    return {
        "avg": a,
        "std": math.sqrt(var),
        "min": vals[0],
        "max": vals[-1],
        "p50": pct(vals, 0.50),
        "p95": pct(vals, 0.95),
        "p99": pct(vals, 0.99),
        "n": n
    }

def load_rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))

def infer_is_byz(row):
    if "is_byz" in row and row["is_byz"] not in ("", None):
        return int(float(row["is_byz"]))
    cid = row.get("client_id", "")
    return 1 if cid in byz_clients else 0

plot_rows = []

for r in range(1, 6):
    rows = load_rows(out / "baseline" / f"round{r:02d}_clients.csv")
    f1 = [to_float(x.get("f1")) for x in rows]
    fpr = [to_float(x.get("fpr")) for x in rows]
    ipfs = [to_float(x.get("ipfs_ms")) for x in rows]
    tx = [to_float(x.get("tx_ms")) for x in rows]
    total = [to_float(x.get("total_ms")) for x in rows]
    plot_rows.append({
        "scenario": "baseline",
        "round": r,
        "f1_avg": avg(f1),
        "f1_honest_avg": "",
        "f1_byz_avg": "",
        "fpr_avg": avg(fpr),
        "fpr_honest_avg": "",
        "fpr_byz_avg": "",
        "ipfs_ms_p50": pct([x for x in ipfs if x is not None], 0.50),
        "tx_ms_p50": pct([x for x in tx if x is not None], 0.50),
        "total_ms_p50": pct([x for x in total if x is not None], 0.50),
        "total_ms_p95": pct([x for x in total if x is not None], 0.95),
        "n_clients": len(rows),
        "n_honest": len(rows),
        "n_byz": 0
    })

for scenario in ["label_flip", "backdoor"]:
    for r in range(1, 6):
        rows = load_rows(out / scenario / f"round{r:02d}_clients.csv")
        honest = [x for x in rows if infer_is_byz(x) == 0]
        byz = [x for x in rows if infer_is_byz(x) == 1]
        f1_all = [to_float(x.get("f1")) for x in rows]
        f1_h = [to_float(x.get("f1")) for x in honest]
        f1_b = [to_float(x.get("f1")) for x in byz]
        fpr_all = [to_float(x.get("fpr")) for x in rows]
        fpr_h = [to_float(x.get("fpr")) for x in honest]
        fpr_b = [to_float(x.get("fpr")) for x in byz]
        ipfs = [to_float(x.get("ipfs_ms")) for x in rows]
        tx = [to_float(x.get("tx_ms")) for x in rows]
        total = [to_float(x.get("total_ms")) for x in rows]
        plot_rows.append({
            "scenario": scenario,
            "round": r,
            "f1_avg": avg(f1_all),
            "f1_honest_avg": avg(f1_h),
            "f1_byz_avg": avg(f1_b),
            "fpr_avg": avg(fpr_all),
            "fpr_honest_avg": avg(fpr_h),
            "fpr_byz_avg": avg(fpr_b),
            "ipfs_ms_p50": pct([x for x in ipfs if x is not None], 0.50),
            "tx_ms_p50": pct([x for x in tx if x is not None], 0.50),
            "total_ms_p50": pct([x for x in total if x is not None], 0.50),
            "total_ms_p95": pct([x for x in total if x is not None], 0.95),
            "n_clients": len(rows),
            "n_honest": len(honest),
            "n_byz": len(byz)
        })

plot_csv = out / "figures_input" / "plot_round_metrics.csv"
with open(plot_csv, "w", newline="") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "scenario","round","f1_avg","f1_honest_avg","f1_byz_avg",
            "fpr_avg","fpr_honest_avg","fpr_byz_avg","ipfs_ms_p50","tx_ms_p50",
            "total_ms_p50","total_ms_p95","n_clients","n_honest","n_byz"
        ]
    )
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

ipfs_summary = {
    "baseline": {
        "ipfs_ms": baseline.get("ipfs_ms"),
        "tx_ms": baseline.get("tx_ms"),
        "total_ms": baseline.get("total_ms")
    },
    "backdoor": {
        "ipfs_ms": backdoor.get("ipfs_ms"),
        "tx_ms": backdoor.get("tx_ms"),
        "total_ms": backdoor.get("total_ms")
    },
    "label_flip": {
        "ipfs_ms": labelflip.get("ipfs_ms"),
        "tx_ms": labelflip.get("tx_ms"),
        "total_ms": labelflip.get("total_ms")
    }
}
(out / "ipfs" / "ipfs_summary_from_clean_metrics.json").write_text(json.dumps(ipfs_summary, indent=2))

manifest = {
    "publication_bundle": str(out),
    "baseline_summary": str(out / "baseline" / "baseline_all_rounds_clean.json"),
    "label_flip_summary": str(out / "label_flip" / "label_flip_all_rounds_clean.json"),
    "backdoor_summary": str(out / "backdoor" / "backdoor_all_rounds_clean.json"),
    "label_flip_raw_dir": str(out / "raw" / "label_flip" / "label_flip_raw"),
    "backdoor_raw_dir": str(out / "raw" / "backdoor"),
    "ipfs_candidates": str(out / "ipfs" / "ipfs_candidates.txt"),
    "caliper_candidates": str(out / "caliper" / "caliper_candidates.txt"),
    "ipfs_summary": str(out / "ipfs" / "ipfs_summary_from_clean_metrics.json"),
    "plot_csv": str(plot_csv),
    "paper_table_csv": str(paper_table)
}
(out / "manifest" / "BUNDLE_MANIFEST.json").write_text(json.dumps(manifest, indent=2))

readme = "\n".join([
    "BUNDLE PUBLICATION PROPRE",
    f"baseline_rows={baseline['n_rows']}",
    f"label_flip_rows={labelflip['n_rows']}",
    f"backdoor_rows={backdoor['n_rows']}",
    "label_flip_source=corrected_attack_aware_rerun",
    "Ce dossier est la source unique pour les tableaux, figures, IPFS et Caliper."
])
(out / "README.txt").write_text(readme + "\n")

print("BUNDLE_OUT=", out)
print("README=", out / "README.txt")
print("MANIFEST=", out / "manifest" / "BUNDLE_MANIFEST.json")
print("PLOT_CSV=", plot_csv)
print("PAPER_TABLE=", paper_table)
print("IPFS_SUMMARY=", out / "ipfs" / "ipfs_summary_from_clean_metrics.json")
print("CALIPER_LIST=", out / "caliper" / "caliper_candidates.txt")
print("IPFS_LIST=", out / "ipfs" / "ipfs_candidates.txt")
PY
