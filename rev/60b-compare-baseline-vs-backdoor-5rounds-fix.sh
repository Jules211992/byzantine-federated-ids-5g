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

def get_path(d, path):
    cur = d
    for k in path.split("."):
        if isinstance(cur, dict) and k in cur:
            cur = cur[k]
        else:
            return None
    return cur

def metric_avg(obj, key):
    if not isinstance(obj, dict): return None
    v = obj.get(key)
    if isinstance(v, dict) and "avg" in v: return v["avg"]
    return None

def scan_metrics(d):
    found = []
    def rec(o, path="root"):
        if isinstance(o, dict):
            if "f1" in o and "fpr" in o and isinstance(o["f1"], dict) and "avg" in o["f1"] and isinstance(o["fpr"], dict) and "avg" in o["fpr"]:
                found.append((path, o["f1"]["avg"], o["fpr"]["avg"]))
            for k,v in o.items():
                rec(v, path + "." + str(k))
        elif isinstance(o, list):
            for i,v in enumerate(o):
                rec(v, f"{path}[{i}]")
    rec(d)
    return found

def pick_group(d, keyword):
    candidates = scan_metrics(d)
    kw = keyword.lower()
    hits = [c for c in candidates if kw in c[0].lower()]
    if hits:
        hits.sort(key=lambda x: len(x[0]))
        return hits[-1]
    return None

base_f1 = base["pooled_over_5rounds"]["f1"]["avg"]
base_fpr = base["pooled_over_5rounds"]["fpr"]["avg"]

hon = pick_group(bd, "honest")
byz = pick_group(bd, "byz")

if hon is None or byz is None:
    top_keys = list(bd.keys()) if isinstance(bd, dict) else type(bd).__name__
    raise SystemExit(f"ERROR: cannot locate honest/byz pooled metrics. TOP_KEYS={top_keys}")

_, hon_f1, hon_fpr = hon
_, byz_f1, byz_fpr = byz

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
