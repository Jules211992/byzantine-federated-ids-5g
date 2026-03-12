#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_SIGNFLIP="${IN_SIGNFLIP:-$(ls -t "$SUM_DIR"/p10_signflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_SIGNFLIP" ] || { echo "ERROR: signflip json introuvable: $IN_SIGNFLIP"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p11_compare_baseline_vs_signflip_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p11_compare_baseline_vs_signflip_5rounds_${TS}.json"

python3 - "$IN_BASELINE" "$IN_SIGNFLIP" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, csv

p_base, p_sf, out_csv, out_json = sys.argv[1:5]
base = json.load(open(p_base))
sf   = json.load(open(p_sf))

def get_avg(obj, path):
    cur = obj
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    if isinstance(cur, dict) and "avg" in cur:
        return float(cur["avg"])
    return None

base_f1 = get_avg(base, ["pooled_over_5rounds","f1"])
base_fpr = get_avg(base, ["pooled_over_5rounds","fpr"])

hon_f1 = get_avg(sf, ["pooled_over_5rounds","pooled_honest","f1"])
hon_fpr = get_avg(sf, ["pooled_over_5rounds","pooled_honest","fpr"])

byz_f1 = get_avg(sf, ["pooled_over_5rounds","pooled_byz","f1"])
byz_fpr = get_avg(sf, ["pooled_over_5rounds","pooled_byz","fpr"])

def delta(v, ref):
    if v is None or ref is None:
        return None
    return v - ref

rows = [
    ["baseline_all", base_f1, None, base_fpr, None],
    ["signflip_honest", hon_f1, delta(hon_f1, base_f1), hon_fpr, delta(hon_fpr, base_fpr)],
    ["signflip_byz", byz_f1, delta(byz_f1, base_f1), byz_fpr, delta(byz_fpr, base_fpr)],
]

with open(out_csv, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["group","f1_avg","delta_f1_vs_baseline","fpr_avg","delta_fpr_vs_baseline"])
    w.writerows(rows)

out = {
    "inputs": {"baseline": p_base, "signflip": p_sf},
    "baseline_all": {"f1_avg": base_f1, "fpr_avg": base_fpr},
    "signflip_honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr, "delta_vs_baseline": {"f1": delta(hon_f1, base_f1), "fpr": delta(hon_fpr, base_fpr)}},
    "signflip_byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr, "delta_vs_baseline": {"f1": delta(byz_f1, base_f1), "fpr": delta(byz_fpr, base_fpr)}},
    "files": {"csv": out_csv, "json": out_json},
}
open(out_json, "w").write(json.dumps(out, indent=2))

print("OK")
print("IN_BASELINE=", p_base)
print("IN_SIGNFLIP=", p_sf)
print("OUT_CSV=", out_csv)
print("OUT_JSON=", out_json)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", hon_f1, " DELTA=", delta(hon_f1, base_f1), "| HONEST_FPR_AVG=", hon_fpr, " DELTA=", delta(hon_fpr, base_fpr))
print("BYZ_F1_AVG=", byz_f1, " DELTA=", delta(byz_f1, base_f1), "| BYZ_FPR_AVG=", byz_fpr, " DELTA=", delta(byz_fpr, base_fpr))
PY
