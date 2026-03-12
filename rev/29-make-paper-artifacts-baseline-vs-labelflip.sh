#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_LABELFLIP="${IN_LABELFLIP:-$(ls -t "$SUM_DIR"/p8_labelflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_LABELFLIP" ] || { echo "ERROR: labelflip json introuvable: $IN_LABELFLIP"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p9_paper_table_baseline_vs_labelflip_${TS}.csv"
OUT_JSON="$SUM_DIR/p9_paper_table_baseline_vs_labelflip_${TS}.json"
OUT_TEX="$SUM_DIR/p9_paper_table_baseline_vs_labelflip_${TS}.tex"
OUT_F1_PNG="$SUM_DIR/p9_fig_f1_baseline_vs_labelflip_${TS}.png"
OUT_FPR_PNG="$SUM_DIR/p9_fig_fpr_baseline_vs_labelflip_${TS}.png"

python3 - "$IN_BASELINE" "$IN_LABELFLIP" "$OUT_TABLE" "$OUT_JSON" "$OUT_TEX" "$OUT_F1_PNG" "$OUT_FPR_PNG" <<'PY'
import sys, json, csv, math

p_base, p_lf, out_csv, out_json, out_tex, out_f1_png, out_fpr_png = sys.argv[1:8]
base = json.load(open(p_base))
lf = json.load(open(p_lf))

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

def gavg(stats, metric):
    if not isinstance(stats, dict):
        return None
    m = stats.get(metric)
    if isinstance(m, dict):
        return m.get("avg")
    return None

def gstd(stats, metric):
    if not isinstance(stats, dict):
        return None
    m = stats.get(metric)
    if isinstance(m, dict):
        return m.get("std")
    return None

def gmin(stats, metric):
    if not isinstance(stats, dict):
        return None
    m = stats.get(metric)
    if isinstance(m, dict):
        return m.get("min")
    return None

def gmax(stats, metric):
    if not isinstance(stats, dict):
        return None
    m = stats.get(metric)
    if isinstance(m, dict):
        return m.get("max")
    return None

def delta(a,b):
    if a is None or b is None:
        return None
    return a-b

def pct(a,b):
    if a is None or b is None or b == 0:
        return None
    return (a-b)/b*100.0

base_stats = find_stats(base) or {}
base_f1 = gavg(base_stats, "f1")
base_fpr = gavg(base_stats, "fpr")

hon = find_key(lf, "pooled_honest")
byz = find_key(lf, "pooled_byz")
allp = find_key(lf, "pooled_all")

rows=[]

def add(group, metric, avg, std, mi, ma, base_ref):
    rows.append({
        "group": group,
        "metric": metric,
        "avg": avg,
        "std": std,
        "min": mi,
        "max": ma,
        "baseline_avg": base_ref,
        "delta_vs_baseline": delta(avg, base_ref),
        "pct_vs_baseline": pct(avg, base_ref),
    })

add("baseline", "f1", base_f1, gstd(base_stats,"f1"), gmin(base_stats,"f1"), gmax(base_stats,"f1"), base_f1)
add("baseline", "fpr", base_fpr, gstd(base_stats,"fpr"), gmin(base_stats,"fpr"), gmax(base_stats,"fpr"), base_fpr)

add("honest", "f1", gavg(hon,"f1"), gstd(hon,"f1"), gmin(hon,"f1"), gmax(hon,"f1"), base_f1)
add("honest", "fpr", gavg(hon,"fpr"), gstd(hon,"fpr"), gmin(hon,"fpr"), gmax(hon,"fpr"), base_fpr)

add("byz", "f1", gavg(byz,"f1"), gstd(byz,"f1"), gmin(byz,"f1"), gmax(byz,"f1"), base_f1)
add("byz", "fpr", gavg(byz,"fpr"), gstd(byz,"fpr"), gmin(byz,"fpr"), gmax(byz,"fpr"), base_fpr)

add("all", "f1", gavg(allp,"f1"), gstd(allp,"f1"), gmin(allp,"f1"), gmax(allp,"f1"), base_f1)
add("all", "fpr", gavg(allp,"fpr"), gstd(allp,"fpr"), gmin(allp,"fpr"), gmax(allp,"fpr"), base_fpr)

with open(out_csv,"w",newline="") as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

out = {
    "inputs": {"baseline": p_base, "labelflip": p_lf},
    "baseline": {"f1_avg": base_f1, "fpr_avg": base_fpr},
    "honest": {"f1_avg": gavg(hon,"f1"), "fpr_avg": gavg(hon,"fpr")},
    "byz": {"f1_avg": gavg(byz,"f1"), "fpr_avg": gavg(byz,"fpr")},
    "all": {"f1_avg": gavg(allp,"f1"), "fpr_avg": gavg(allp,"fpr")},
    "table_csv": out_csv
}
json.dump(out, open(out_json,"w"), indent=2)

def fmt(x):
    if x is None:
        return "-"
    if isinstance(x,(int,float)):
        return f"{x:.4f}"
    return str(x)

tex_lines=[]
tex_lines.append("\\begin{table}[t]")
tex_lines.append("\\centering")
tex_lines.append("\\caption{Baseline vs. Label-Flip (5 rounds, N=20)}")
tex_lines.append("\\label{tab:baseline-labelflip}")
tex_lines.append("\\begin{tabular}{lcccc}")
tex_lines.append("\\hline")
tex_lines.append("Group & F1 (avg) & FPR (avg) & $\\Delta$F1 vs BL & $\\Delta$FPR vs BL \\\\")
tex_lines.append("\\hline")

groups = ["baseline","honest","byz","all"]
def get(group, metric):
    for r in rows:
        if r["group"]==group and r["metric"]==metric:
            return r
    return None

for g in groups:
    rf1 = get(g,"f1")
    rfpr = get(g,"fpr")
    df1 = rf1["delta_vs_baseline"] if rf1 else None
    dfpr = rfpr["delta_vs_baseline"] if rfpr else None
    tex_lines.append(f"{g} & {fmt(rf1['avg'] if rf1 else None)} & {fmt(rfpr['avg'] if rfpr else None)} & {fmt(df1)} & {fmt(dfpr)} \\\\")
tex_lines.append("\\hline")
tex_lines.append("\\end{tabular}")
tex_lines.append("\\end{table}")
open(out_tex,"w").write("\n".join(tex_lines))

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

labels = ["baseline","honest","byz"]
f1_vals = [out["baseline"]["f1_avg"], out["honest"]["f1_avg"], out["byz"]["f1_avg"]]
fpr_vals = [out["baseline"]["fpr_avg"], out["honest"]["fpr_avg"], out["byz"]["fpr_avg"]]

plt.figure()
plt.bar(labels, f1_vals)
plt.ylabel("F1 (avg)")
plt.title("F1: Baseline vs Label-Flip (Honest vs Byz)")
plt.tight_layout()
plt.savefig(out_f1_png, dpi=200)
plt.close()

plt.figure()
plt.bar(labels, fpr_vals)
plt.ylabel("FPR (avg)")
plt.title("FPR: Baseline vs Label-Flip (Honest vs Byz)")
plt.tight_layout()
plt.savefig(out_fpr_png, dpi=200)
plt.close()

print("OK")
print("IN_BASELINE=", p_base)
print("IN_LABELFLIP=", p_lf)
print("OUT_TABLE=", out_csv)
print("OUT_JSON=", out_json)
print("OUT_TEX=", out_tex)
print("OUT_F1_PNG=", out_f1_png)
print("OUT_FPR_PNG=", out_fpr_png)
print("BASELINE_F1_AVG=", base_f1, " BASELINE_FPR_AVG=", base_fpr)
print("HONEST_F1_AVG=", out["honest"]["f1_avg"], " DELTA=", delta(out["honest"]["f1_avg"], base_f1),
      "| HONEST_FPR_AVG=", out["honest"]["fpr_avg"], " DELTA=", delta(out["honest"]["fpr_avg"], base_fpr))
print("BYZ_F1_AVG=", out["byz"]["f1_avg"], " DELTA=", delta(out["byz"]["f1_avg"], base_f1),
      "| BYZ_FPR_AVG=", out["byz"]["fpr_avg"], " DELTA=", delta(out["byz"]["fpr_avg"], base_fpr))
PY
