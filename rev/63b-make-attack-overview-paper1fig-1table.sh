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

mkdir -p "$HOME/byz-fed-ids-5g/paper/figures" "$HOME/byz-fed-ids-5g/paper/tables"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$HOME/byz-fed-ids-5g/paper/tables/table4_attack_overview_${TS}.csv"
OUT_TEX="$HOME/byz-fed-ids-5g/paper/tables/table4_attack_overview_${TS}.tex"
OUT_PNG="$HOME/byz-fed-ids-5g/paper/figures/fig2_multikrum_robustness.png"
OUT_PDF="$HOME/byz-fed-ids-5g/paper/figures/fig2_multikrum_robustness.pdf"

python3 - "$BASE" "$LF" "$SF" "$SC" "$GA" "$RA" "$BD" "$OUT_CSV" "$OUT_TEX" "$OUT_PNG" "$OUT_PDF" <<'PY'
import sys, json, csv
from pathlib import Path
import matplotlib.pyplot as plt

p_base, p_lf, p_sf, p_sc, p_ga, p_ra, p_bd, out_csv, out_tex, out_png, out_pdf = sys.argv[1:12]
out_csv = Path(out_csv); out_tex = Path(out_tex); out_png = Path(out_png); out_pdf = Path(out_pdf)

def load(p):
    if not p: return None
    pp = Path(p)
    return json.load(pp.open()) if pp.exists() else None

def safe_get(d, path, default=None):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def extract(d):
    if d is None:
        return None
    po = d.get("pooled_over_5rounds", None) if isinstance(d, dict) else None
    if isinstance(po, dict) and "honest" in po and "byz" in po:
        hf1  = safe_get(po, ["honest","f1","avg"])
        hfpr = safe_get(po, ["honest","fpr","avg"])
        bf1  = safe_get(po, ["byz","f1","avg"])
        bfpr = safe_get(po, ["byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr
    if isinstance(po, dict) and "f1" in po and "fpr" in po:
        hf1  = safe_get(po, ["f1","avg"])
        hfpr = safe_get(po, ["fpr","avg"])
        return hf1, hfpr, None, None
    return None

cases = [
    ("Baseline", load(p_base)),
    ("LabelFlip", load(p_lf)),
    ("SignFlip",  load(p_sf)),
    ("Scaling",   load(p_sc)),
    ("Gaussian",  load(p_ga)),
    ("Random",    load(p_ra)),
    ("Backdoor",  load(p_bd)),
]

rows=[]
for name, d in cases:
    m = extract(d)
    if m is None:
        continue
    hf1,hfpr,bf1,bfpr = m
    rows.append({
        "scenario": name,
        "honest_f1": hf1,
        "honest_fpr": hfpr,
        "byz_f1": bf1,
        "byz_fpr": bfpr,
    })

def fmt(x):
    if x is None: return ""
    return f"{x:.4f}"

with out_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow(r)

tex=[]
tex.append(r"\begin{table}[!t]")
tex.append(r"\centering")
tex.append(r"\caption{Attack overview (pooled over 5 rounds). Baseline reports pooled metrics; attacks report honest vs Byzantine pools.}")
tex.append(r"\label{tab:attack_overview}")
tex.append(r"\footnotesize")
tex.append(r"\setlength{\tabcolsep}{3.2pt}")
tex.append(r"\renewcommand{\arraystretch}{1.05}")
tex.append(r"\begin{tabular}{lcccc}")
tex.append(r"\toprule")
tex.append(r"\textbf{Scenario} & \textbf{F1(h)} & \textbf{FPR(h)} & \textbf{F1(b)} & \textbf{FPR(b)}\\")
tex.append(r"\midrule")
for r in rows:
    tex.append(f"{r['scenario']} & {fmt(r['honest_f1'])} & {fmt(r['honest_fpr'])} & {fmt(r['byz_f1'])} & {fmt(r['byz_fpr'])} \\\\")
tex.append(r"\bottomrule")
tex.append(r"\end{tabular}")
tex.append(r"\end{table}")
out_tex.write_text("\n".join(tex) + "\n")

plt.rcParams.update({
    "font.family":"serif",
    "font.size":10,
    "axes.titlesize":10,
    "axes.labelsize":10,
    "legend.fontsize":8,
})

fig, ax = plt.subplots(figsize=(3.5, 2.6), dpi=300)

def point(x,y,marker,label,color):
    ax.scatter([x],[y], marker=marker, s=28, color=color, edgecolor="black", linewidth=0.3, zorder=3, label=label)

base = next((r for r in rows if r["scenario"]=="Baseline"), None)
if base:
    point(base["honest_fpr"], base["honest_f1"], "*", "Baseline", "black")
    ax.annotate("BASE", (base["honest_fpr"], base["honest_f1"]), xytext=(5,5), textcoords="offset points", fontsize=8)

for r in rows:
    if r["scenario"]=="Baseline":
        continue
    if r["honest_f1"] is not None and r["honest_fpr"] is not None:
        point(r["honest_fpr"], r["honest_f1"], "o", "Honest pool", "#1f77b4")
        ax.annotate(r["scenario"][:2].upper(), (r["honest_fpr"], r["honest_f1"]), xytext=(5,-10), textcoords="offset points", fontsize=8, color="#1f77b4")
    if r["byz_f1"] is not None and r["byz_fpr"] is not None:
        point(r["byz_fpr"], r["byz_f1"], "^", "Byzantine pool", "#d62728")
        ax.annotate(r["scenario"][:2].upper(), (r["byz_fpr"], r["byz_f1"]), xytext=(5,5), textcoords="offset points", fontsize=8, color="#d62728")

ax.set_xlabel("False Positive Rate (FPR)")
ax.set_ylabel("F1-score")
ax.set_xlim(0, 1.0)
ax.set_ylim(0, 1.0)
ax.grid(alpha=0.25)

handles, labels = ax.get_legend_handles_labels()
seen=set()
hh=[]
ll=[]
for h,l in zip(handles,labels):
    if l in seen:
        continue
    seen.add(l)
    hh.append(h); ll.append(l)
ax.legend(hh, ll, loc="lower left", frameon=False)

fig.tight_layout()
fig.savefig(out_png, bbox_inches="tight")
fig.savefig(out_pdf, bbox_inches="tight")
print("OK")
print("OUT_CSV=", out_csv)
print("OUT_TEX=", out_tex)
print("OUT_PNG=", out_png)
print("OUT_PDF=", out_pdf)
PY
