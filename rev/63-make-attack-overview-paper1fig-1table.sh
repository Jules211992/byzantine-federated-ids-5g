#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

BASE=$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
LF=$(ls -t "$SUM_DIR"/p8_labelflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
SF=$(ls -t "$SUM_DIR"/p10_signflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
SC=$(ls -t "$SUM_DIR"/p12_scaling_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
GA=$(ls -t "$SUM_DIR"/p13_gaussian_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
RA=$(ls -t "$SUM_DIR"/p14_random_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)
BD=$(ls -t "$SUM_DIR"/p15_backdoor_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)

[ -f "$BASE" ] || { echo "ERROR: baseline json introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p16_attack_overview_${TS}.csv"
OUT_TEX="$SUM_DIR/p16_attack_overview_${TS}.tex"
OUT_PNG="$SUM_DIR/p16_attack_overview_${TS}.png"

python3 - "$BASE" "$LF" "$SF" "$SC" "$GA" "$RA" "$BD" "$OUT_CSV" "$OUT_TEX" "$OUT_PNG" <<'PY'
import sys, json, csv
from pathlib import Path
import math

p_base, p_lf, p_sf, p_sc, p_ga, p_ra, p_bd, out_csv, out_tex, out_png = sys.argv[1:11]
out_csv = Path(out_csv); out_tex = Path(out_tex); out_png = Path(out_png)

def load(p):
    if not p or p == "": return None
    pp = Path(p)
    return json.load(pp.open()) if pp.exists() else None

base = load(p_base)
cases = [
    ("Baseline", base),
    ("LabelFlip", load(p_lf)),
    ("SignFlip",  load(p_sf)),
    ("Scaling",   load(p_sc)),
    ("Gaussian",  load(p_ga)),
    ("Random",    load(p_ra)),
    ("Backdoor",  load(p_bd)),
]

def safe_get(d, path, default=None):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def extract_metrics(d):
    if d is None:
        return None

    # Pattern A: pooled_honest / pooled_byz
    if isinstance(d, dict) and "pooled_honest" in d and "pooled_byz" in d:
        hf1 = safe_get(d, ["pooled_honest","f1","avg"])
        hfpr= safe_get(d, ["pooled_honest","fpr","avg"])
        bf1 = safe_get(d, ["pooled_byz","f1","avg"])
        bfpr= safe_get(d, ["pooled_byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr

    # Pattern B: pooled_over_5rounds with honest/byz
    po = d.get("pooled_over_5rounds", None) if isinstance(d, dict) else None
    if isinstance(po, dict) and "honest" in po and "byz" in po:
        hf1 = safe_get(po, ["honest","f1","avg"])
        hfpr= safe_get(po, ["honest","fpr","avg"])
        bf1 = safe_get(po, ["byz","f1","avg"])
        bfpr= safe_get(po, ["byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr

    # Pattern C: pooled_over_5rounds direct f1/fpr (baseline)
    if isinstance(po, dict) and "f1" in po and "fpr" in po:
        hf1 = safe_get(po, ["f1","avg"])
        hfpr= safe_get(po, ["fpr","avg"])
        return hf1, hfpr, None, None

    return None

base_hf1, base_hfpr, _, _ = extract_metrics(base)
if base_hf1 is None or base_hfpr is None:
    raise SystemExit("ERROR: cannot read baseline pooled_over_5rounds f1/fpr")

rows=[]
for name, d in cases:
    m = extract_metrics(d)
    if m is None:
        continue
    hf1,hfpr,bf1,bfpr = m
    dhf1  = (hf1 - base_hf1) if (hf1 is not None) else None
    dhfpr = (hfpr - base_hfpr) if (hfpr is not None) else None
    rows.append({
        "scenario": name,
        "honest_f1": hf1,
        "honest_fpr": hfpr,
        "byz_f1": bf1,
        "byz_fpr": bfpr,
        "delta_honest_f1_vs_base": dhf1,
        "delta_honest_fpr_vs_base": dhfpr,
    })

def f(x):
    if x is None: return ""
    return f"{x:.4f}"

with out_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow(r)

# ---- LaTeX table (compact, IEEE-friendly) ----
tex = []
tex.append(r"\begin{table}[!t]")
tex.append(r"\centering")
tex.append(r"\caption{Attack overview (5 rounds, pooled averages). Baseline reports pooled metrics; attacks report honest vs Byzantine pools.}")
tex.append(r"\label{tab:attack_overview}")
tex.append(r"\footnotesize")
tex.append(r"\setlength{\tabcolsep}{3.6pt}")
tex.append(r"\renewcommand{\arraystretch}{1.08}")
tex.append(r"\begin{tabular}{lcccc}")
tex.append(r"\toprule")
tex.append(r"\textbf{Scenario} & \textbf{F1(h)} & \textbf{FPR(h)} & \textbf{F1(b)} & \textbf{FPR(b)}\\")
tex.append(r"\midrule")
for r in rows:
    tex.append(f"{r['scenario']} & {f(r['honest_f1'])} & {f(r['honest_fpr'])} & {f(r['byz_f1'])} & {f(r['byz_fpr'])} \\\\")
tex.append(r"\bottomrule")
tex.append(r"\end{tabular}")
tex.append(r"\end{table}")
out_tex.write_text("\n".join(tex) + "\n")

# ---- One research-grade figure: 2 panels (F1, FPR), grouped bars ----
import matplotlib.pyplot as plt

labels = [r["scenario"] for r in rows]
x = list(range(len(labels)))

hf1  = [r["honest_f1"] for r in rows]
hfpr = [r["honest_fpr"] for r in rows]
bf1  = [r["byz_f1"] for r in rows]
bfpr = [r["byz_fpr"] for r in rows]

def none_to_nan(a):
    return [float("nan") if v is None else v for v in a]

bf1  = none_to_nan(bf1)
bfpr = none_to_nan(bfpr)

plt.rcParams.update({
    "font.size": 9,
    "axes.titlesize": 9,
    "axes.labelsize": 9,
    "legend.fontsize": 8,
})

fig, ax = plt.subplots(1, 2, figsize=(11.5, 3.2), dpi=300)
w = 0.28

ax[0].bar([i - w for i in x], hf1, width=w, label="Honest pool")
ax[0].bar([i + w for i in x], bf1, width=w, label="Byzantine pool")
ax[0].set_title("Pooled F1 (5 rounds)")
ax[0].set_xticks(x)
ax[0].set_xticklabels(labels, rotation=20, ha="right")
ax[0].set_ylim(0, 1.0)
ax[0].grid(axis="y", alpha=0.25)

ax[1].bar([i - w for i in x], hfpr, width=w, label="Honest pool")
ax[1].bar([i + w for i in x], bfpr, width=w, label="Byzantine pool")
ax[1].set_title("Pooled FPR (5 rounds)")
ax[1].set_xticks(x)
ax[1].set_xticklabels(labels, rotation=20, ha="right")
ax[1].set_ylim(0, 1.0)
ax[1].grid(axis="y", alpha=0.25)

ax[0].legend(loc="upper left", frameon=False)
fig.tight_layout()
fig.savefig(out_png, bbox_inches="tight")
print("OK")
print("OUT_CSV=", out_csv)
print("OUT_TEX=", out_tex)
print("OUT_PNG=", out_png)
PY

