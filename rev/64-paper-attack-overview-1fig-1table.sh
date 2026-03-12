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

FIG_DIR="$HOME/byz-fed-ids-5g/paper/figures/final6"
TAB_DIR="$HOME/byz-fed-ids-5g/paper/tables"
mkdir -p "$FIG_DIR" "$TAB_DIR"

OUT_CSV="$TAB_DIR/table4_security_dependability.csv"
OUT_TEX="$TAB_DIR/table4_security_dependability.tex"
OUT_PNG="$FIG_DIR/fig2_multikrum_robustness.png"
OUT_PDF="$FIG_DIR/fig2_multikrum_robustness.pdf"

python3 - "$BASE" "$LF" "$SF" "$SC" "$GA" "$RA" "$BD" "$OUT_CSV" "$OUT_TEX" "$OUT_PNG" "$OUT_PDF" <<'PY'
import sys, json, csv
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

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

def extract_metrics(d):
    if d is None:
        return None

    if isinstance(d, dict) and "pooled_honest" in d and "pooled_byz" in d:
        hf1 = safe_get(d, ["pooled_honest","f1","avg"])
        hfpr= safe_get(d, ["pooled_honest","fpr","avg"])
        bf1 = safe_get(d, ["pooled_byz","f1","avg"])
        bfpr= safe_get(d, ["pooled_byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr

    po = d.get("pooled_over_5rounds", None) if isinstance(d, dict) else None
    if isinstance(po, dict) and "honest" in po and "byz" in po:
        hf1 = safe_get(po, ["honest","f1","avg"])
        hfpr= safe_get(po, ["honest","fpr","avg"])
        bf1 = safe_get(po, ["byz","f1","avg"])
        bfpr= safe_get(po, ["byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr

    if isinstance(po, dict) and "f1" in po and "fpr" in po:
        hf1 = safe_get(po, ["f1","avg"])
        hfpr= safe_get(po, ["fpr","avg"])
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

base = cases[0][1]
bm = extract_metrics(base)
if bm is None:
    raise SystemExit("ERROR: cannot read baseline pooled metrics")
base_f1, base_fpr, _, _ = bm

rows=[]
for name, d in cases:
    m = extract_metrics(d)
    if m is None:
        continue
    hf1,hfpr,bf1,bfpr = m
    rows.append({
        "Scenario": name,
        "F1_honest": hf1,
        "FPR_honest": hfpr,
        "F1_byz": bf1,
        "FPR_byz": bfpr,
        "Delta_F1_h_vs_base": (hf1 - base_f1) if hf1 is not None else None,
        "Delta_FPR_h_vs_base": (hfpr - base_fpr) if hfpr is not None else None,
    })

def fmt(x):
    if x is None:
        return ""
    return f"{x:.4f}"

with out_csv.open("w", newline="") as fp:
    w = csv.DictWriter(fp, fieldnames=list(rows[0].keys()))
    w.writeheader()
    for r in rows:
        w.writerow({k:(fmt(v) if isinstance(v,float) or v is None else v) for k,v in r.items()})

tex=[]
tex.append(r"\begin{table}[!t]")
tex.append(r"\centering")
tex.append(r"\caption{Attack overview (5 rounds, pooled averages). Baseline reports pooled metrics; attacks report honest vs Byzantine pools.}")
tex.append(r"\label{tab:security_dependability}")
tex.append(r"\footnotesize")
tex.append(r"\setlength{\tabcolsep}{3.8pt}")
tex.append(r"\renewcommand{\arraystretch}{1.06}")
tex.append(r"\begin{tabular}{lcccc}")
tex.append(r"\toprule")
tex.append(r"\textbf{Scenario} & \textbf{F1(h)} & \textbf{FPR(h)} & \textbf{F1(b)} & \textbf{FPR(b)}\\")
tex.append(r"\midrule")
for r in rows:
    tex.append(f"{r['Scenario']} & {fmt(r['F1_honest'])} & {fmt(r['FPR_honest'])} & {fmt(r['F1_byz'])} & {fmt(r['FPR_byz'])} \\\\")
tex.append(r"\bottomrule")
tex.append(r"\end{tabular}")
tex.append(r"\end{table}")
out_tex.write_text("\n".join(tex) + "\n")

plt.rcParams.update({
    "font.family": "serif",
    "font.size": 11,
    "axes.titlesize": 12,
    "axes.labelsize": 11,
    "figure.dpi": 300
})

labels = [r["Scenario"] for r in rows]
x = np.arange(len(labels))
w = 0.34

hf1  = [r["F1_honest"] for r in rows]
hfpr = [r["FPR_honest"] for r in rows]
bf1  = [np.nan if r["F1_byz"] is None else r["F1_byz"] for r in rows]
bfpr = [np.nan if r["FPR_byz"] is None else r["FPR_byz"] for r in rows]

fig, ax = plt.subplots(1, 2, figsize=(11.5, 3.2), dpi=300)

b1 = ax[0].bar(x - w/2, hf1, width=w, alpha=0.85, label="Honest pool")
b2 = ax[0].bar(x + w/2, bf1, width=w, alpha=0.85, label="Byzantine pool")
ax[0].set_title("Pooled F1 (5 rounds)")
ax[0].set_xticks(x)
ax[0].set_xticklabels(labels, rotation=18, ha="right")
ax[0].set_ylim(0, 1.0)
ax[0].grid(axis="y", alpha=0.25)
for bar in b1:
    ax[0].text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.015, f"{bar.get_height():.3f}", ha="center", fontsize=9)
for bar in b2:
    if not np.isnan(bar.get_height()):
        ax[0].text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.015, f"{bar.get_height():.3f}", ha="center", fontsize=9)

b3 = ax[1].bar(x - w/2, hfpr, width=w, alpha=0.85, label="Honest pool")
b4 = ax[1].bar(x + w/2, bfpr, width=w, alpha=0.85, label="Byzantine pool")
ax[1].set_title("Pooled FPR (5 rounds)")
ax[1].set_xticks(x)
ax[1].set_xticklabels(labels, rotation=18, ha="right")
ax[1].set_ylim(0, 1.0)
ax[1].grid(axis="y", alpha=0.25)
for bar in b3:
    ax[1].text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.015, f"{bar.get_height():.3f}", ha="center", fontsize=9)
for bar in b4:
    if not np.isnan(bar.get_height()):
        ax[1].text(bar.get_x()+bar.get_width()/2, bar.get_height()+0.015, f"{bar.get_height():.3f}", ha="center", fontsize=9)

ax[0].legend(loc="upper left", frameon=False, fontsize=9)
fig.tight_layout()
fig.savefig(out_png, bbox_inches="tight")
fig.savefig(out_pdf, bbox_inches="tight")

print("OK")
print("TABLE_CSV=", out_csv)
print("TABLE_TEX=", out_tex)
print("FIG_PNG=", out_png)
print("FIG_PDF=", out_pdf)
PY
