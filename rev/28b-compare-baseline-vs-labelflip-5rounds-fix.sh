#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_LABELFLIP="${IN_LABELFLIP:-$(ls -t "$SUM_DIR"/p8_labelflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable (IN_BASELINE)"; echo "SUM_DIR=$SUM_DIR"; ls -lh "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null || true; exit 1; }
[ -f "$IN_LABELFLIP" ] || { echo "ERROR: labelflip json introuvable (IN_LABELFLIP)"; echo "SUM_DIR=$SUM_DIR"; ls -lh "$SUM_DIR"/p8_labelflip_5rounds_clean_*.json 2>/dev/null || true; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p9_compare_baseline_vs_labelflip_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p9_compare_baseline_vs_labelflip_5rounds_${TS}.json"

python3 - "$IN_BASELINE" "$IN_LABELFLIP" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, csv

p_base, p_lf, out_csv, out_json = sys.argv[1:5]
base = json.load(open(p_base))
lf   = json.load(open(p_lf))

def find_stats(obj):
    if isinstance(obj, dict):
        if "f1" in obj and "fpr" in obj:
            f1=obj["f1"]; fpr=obj["fpr"]
            if isinstance(f1, dict) and "avg" in f1 and isinstance(fpr, dict) and "avg" in fpr:
                return obj
        for v in obj.values():
            r = find_stats(v)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_stats(v)
            if r is not None:
                return r
    return None

def find_key(obj, key):
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for v in obj.values():
            r = find_key(v, key)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for v in obj:
            r = find_key(v, key)
            if r is not None:
                return r
    return None

def avg_of(stats, metric):
    if not isinstance(stats, dict):
        return None
    m = stats.get(metric)
    if isinstance(m, dict):
        return m.get("avg")
    return None

base_stats = find_stats(base) or {}
base_f1  = avg_of(base_stats, "f1")
base_fpr = avg_of(base_stats, "fpr")

honest_stats = find_key(lf, "pooled_honest")
byz_stats    = find_key(lf, "pooled_byz")
all_stats    = find_key(lf, "pooled_all")

def delta(a,b):
    if a is None or b is None: return None
    return a-b

def pct(a,b):
    if a is None or b is None or b == 0: return None
    return (a-b)/b*100.0

rows=[]
def add_row(group, metric, val):
    rows.append({
        "group": group,
        "metric": metric,
        "avg": val,
        "baseline_avg": base_f1 if metric=="f1" else base_fpr,
        "delta_vs_baseline": delta(val, base_f1 if metric=="f1" else base_fpr),
        "pct_vs_baseline": pct(val, base_f1 if metric=="f1" else base_fpr),
    })

add_row("baseline", "f1",  base_f1)
add_row("baseline", "fpr", base_fpr)

add_row("honest", "f1",  avg_of(honest_stats, "f1"))
add_row("honest", "fpr", avg_of(honest_stats, "fpr"))

add_row("byz", "f1",  avg_of(byz_stats, "f1"))
add_row("byz", "fpr", avg_of(byz_stats, "fpr"))

add_row("all", "f1",  avg_of(all_stats, "f1"))
add_row("all", "fpr", avg_of(all_stats, "fpr"))

with open(out_csv,"w",newline="") as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

out={
    "inputs":{"baseline":p_base,"labelflip":p_lf},
    "baseline":{"f1_avg":base_f1,"fpr_avg":base_fpr},
    "honest":{"f1_avg":avg_of(honest_stats,"f1"),"fpr_avg":avg_of(honest_stats,"fpr")},
    "byz":{"f1_avg":avg_of(byz_stats,"f1"),"fpr_avg":avg_of(byz_stats,"fpr")},
    "all":{"f1_avg":avg_of(all_stats,"f1"),"fpr_avg":avg_of(all_stats,"fpr")},
}
json.dump(out, open(out_json,"w"), indent=2)

print("OK")
print("IN_BASELINE=", p_base)
print("IN_LABELFLIP=", p_lf)
print("OUT_CSV=", out_csv)
print("OUT_JSON=", out_json)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", out["honest"]["f1_avg"], " DELTA=", delta(out["honest"]["f1_avg"], base_f1),
      "| HONEST_FPR_AVG=", out["honest"]["fpr_avg"], " DELTA=", delta(out["honest"]["fpr_avg"], base_fpr))
print("BYZ_F1_AVG=", out["byz"]["f1_avg"], " DELTA=", delta(out["byz"]["f1_avg"], base_f1),
      "| BYZ_FPR_AVG=", out["byz"]["fpr_avg"], " DELTA=", delta(out["byz"]["fpr_avg"], base_fpr))
PY
