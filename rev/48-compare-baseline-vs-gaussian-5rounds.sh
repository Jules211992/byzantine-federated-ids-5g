#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_GAUSSIAN="${IN_GAUSSIAN:-$(ls -t "$SUM_DIR"/p13_gaussian_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_GAUSSIAN" ] || { echo "ERROR: gaussian json introuvable: $IN_GAUSSIAN"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p13_compare_baseline_vs_gaussian_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p13_compare_baseline_vs_gaussian_5rounds_${TS}.json"

python3 - "$IN_BASELINE" "$IN_GAUSSIAN" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, csv

p_base, p_g, out_csv, out_json = sys.argv[1:5]
base = json.load(open(p_base))
g    = json.load(open(p_g))

base_f1 = base["pooled_over_5rounds"]["f1"]["avg"]
base_fpr = base["pooled_over_5rounds"]["fpr"]["avg"]

hon_f1 = g["pooled_over_5rounds"]["pooled_honest"]["f1"]["avg"]
hon_fpr = g["pooled_over_5rounds"]["pooled_honest"]["fpr"]["avg"]
byz_f1 = g["pooled_over_5rounds"]["pooled_byz"]["f1"]["avg"]
byz_fpr = g["pooled_over_5rounds"]["pooled_byz"]["fpr"]["avg"]

res = {
  "inputs": {"baseline": p_base, "gaussian": p_g},
  "baseline": {"f1_avg": base_f1, "fpr_avg": base_fpr},
  "gaussian_honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr, "delta_f1": hon_f1-base_f1, "delta_fpr": hon_fpr-base_fpr},
  "gaussian_byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr, "delta_f1": byz_f1-base_f1, "delta_fpr": byz_fpr-base_fpr},
}

with open(out_csv,"w",newline="") as f:
    wr=csv.writer(f)
    wr.writerow(["metric","baseline","gaussian_honest","delta_honest","gaussian_byz","delta_byz"])
    wr.writerow(["f1", base_f1, hon_f1, hon_f1-base_f1, byz_f1, byz_f1-base_f1])
    wr.writerow(["fpr", base_fpr, hon_fpr, hon_fpr-base_fpr, byz_fpr, byz_fpr-base_fpr])

json.dump(res, open(out_json,"w"), indent=2)

print("OK")
print("IN_BASELINE=", p_base)
print("IN_GAUSSIAN=", p_g)
print("OUT_CSV=", out_csv)
print("OUT_JSON=", out_json)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", hon_f1, " DELTA=", hon_f1-base_f1, "| HONEST_FPR_AVG=", hon_fpr, " DELTA=", hon_fpr-base_fpr)
print("BYZ_F1_AVG=", byz_f1, " DELTA=", byz_f1-base_f1, "| BYZ_FPR_AVG=", byz_fpr, " DELTA=", byz_fpr-base_fpr)
PY
