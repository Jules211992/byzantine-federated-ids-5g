#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_BACKDOOR="${IN_BACKDOOR:-$(ls -t "$SUM_DIR"/p15_backdoor_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_BACKDOOR" ] || { echo "ERROR: backdoor json introuvable: $IN_BACKDOOR"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p15_compare_baseline_vs_backdoor_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p15_compare_baseline_vs_backdoor_5rounds_${TS}.json"

python3 - "$IN_BASELINE" "$IN_BACKDOOR" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, csv

p_base, p_bd, out_csv, out_json = sys.argv[1:5]
base = json.load(open(p_base))
bd   = json.load(open(p_bd))

base_f1 = base["pooled_over_5rounds"]["f1"]["avg"]
base_fpr = base["pooled_over_5rounds"]["fpr"]["avg"]

hon_f1 = bd["pooled_honest"]["f1"]["avg"]
hon_fpr = bd["pooled_honest"]["fpr"]["avg"]
byz_f1 = bd["pooled_byz"]["f1"]["avg"]
byz_fpr = bd["pooled_byz"]["fpr"]["avg"]

rows = [
  ["baseline","all",base_f1,base_fpr,0.0,0.0],
  ["backdoor","honest",hon_f1,hon_fpr,hon_f1-base_f1,hon_fpr-base_fpr],
  ["backdoor","byz",byz_f1,byz_fpr,byz_f1-base_f1,byz_fpr-base_fpr],
]

with open(out_csv,"w",newline="") as f:
  w=csv.writer(f)
  w.writerow(["scenario","group","f1_avg","fpr_avg","delta_f1_vs_baseline","delta_fpr_vs_baseline"])
  w.writerows(rows)

out = {
  "inputs": {"baseline": p_base, "backdoor": p_bd},
  "baseline": {"f1_avg": base_f1, "fpr_avg": base_fpr},
  "backdoor": {
    "honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr},
    "byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr}
  }
}
json.dump(out, open(out_json,"w"), indent=2)

print("OK")
print("IN_BASELINE=", p_base)
print("IN_BACKDOOR=", p_bd)
print("OUT_CSV=", out_csv)
print("OUT_JSON=", out_json)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", hon_f1, " DELTA=", hon_f1-base_f1, "| HONEST_FPR_AVG=", hon_fpr, " DELTA=", hon_fpr-base_fpr)
print("BYZ_F1_AVG=", byz_f1, " DELTA=", byz_f1-base_f1, "| BYZ_FPR_AVG=", byz_fpr, " DELTA=", byz_fpr-base_fpr)
PY
