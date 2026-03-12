#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_SCALING="${IN_SCALING:-$(ls -t "$SUM_DIR"/p12_scaling_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_SCALING" ] || { echo "ERROR: scaling json introuvable: $IN_SCALING"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p13_compare_baseline_vs_scaling_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p13_compare_baseline_vs_scaling_5rounds_${TS}.json"

python3 - "$IN_BASELINE" "$IN_SCALING" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, csv

p_base, p_sc, out_csv, out_json = sys.argv[1:5]
base = json.load(open(p_base))
sc   = json.load(open(p_sc))

base_f1 = base["pooled_over_5rounds"]["f1"]["avg"]
base_fpr = base["pooled_over_5rounds"]["fpr"]["avg"]

h_f1 = sc["pooled_over_5rounds"]["honest"]["f1"]["avg"]
h_fpr = sc["pooled_over_5rounds"]["honest"]["fpr"]["avg"]
b_f1 = sc["pooled_over_5rounds"]["byz"]["f1"]["avg"]
b_fpr = sc["pooled_over_5rounds"]["byz"]["fpr"]["avg"]

rows = [
  {"group":"baseline","f1_avg":base_f1,"fpr_avg":base_fpr,"delta_f1":None,"delta_fpr":None},
  {"group":"scaling_honest","f1_avg":h_f1,"fpr_avg":h_fpr,"delta_f1":h_f1-base_f1,"delta_fpr":h_fpr-base_fpr},
  {"group":"scaling_byz","f1_avg":b_f1,"fpr_avg":b_fpr,"delta_f1":b_f1-base_f1,"delta_fpr":b_fpr-base_fpr},
]

with open(out_csv,"w",newline="") as f:
  w = csv.DictWriter(f, fieldnames=["group","f1_avg","fpr_avg","delta_f1","delta_fpr"])
  w.writeheader()
  for r in rows:
    w.writerow(r)

out = {
  "inputs": {"baseline": p_base, "scaling": p_sc},
  "baseline": {"f1_avg": base_f1, "fpr_avg": base_fpr},
  "scaling_honest": {"f1_avg": h_f1, "fpr_avg": h_fpr, "delta_f1": h_f1-base_f1, "delta_fpr": h_fpr-base_fpr},
  "scaling_byz": {"f1_avg": b_f1, "fpr_avg": b_fpr, "delta_f1": b_f1-base_f1, "delta_fpr": b_fpr-base_fpr},
  "files": {"csv": out_csv, "json": out_json}
}
open(out_json,"w").write(json.dumps(out, indent=2))

print("OK")
print("IN_BASELINE=", p_base)
print("IN_SCALING=", p_sc)
print("OUT_CSV=", out_csv)
print("OUT_JSON=", out_json)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", h_f1, " DELTA=", h_f1-base_f1, "| HONEST_FPR_AVG=", h_fpr, " DELTA=", h_fpr-base_fpr)
print("BYZ_F1_AVG=", b_f1, " DELTA=", b_f1-base_f1, "| BYZ_FPR_AVG=", b_fpr, " DELTA=", b_fpr-base_fpr)
PY
