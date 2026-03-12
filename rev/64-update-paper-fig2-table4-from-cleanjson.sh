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

mkdir -p ~/byz-fed-ids-5g/paper/figures
mkdir -p ~/byz-fed-ids-5g/paper/tables

OUT_FIG_PNG=~/byz-fed-ids-5g/paper/figures/fig2_multikrum_robustness.png
OUT_FIG_PDF=~/byz-fed-ids-5g/paper/figures/fig2_multikrum_robustness.pdf
OUT_TAB_CSV=~/byz-fed-ids-5g/paper/tables/table4_security_dependability.csv
OUT_TAB_TEX=~/byz-fed-ids-5g/paper/tables/table4_security_dependability.tex

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_ARCH_CSV="$SUM_DIR/p16_attack_overview_${TS}.csv"
OUT_ARCH_TEX="$SUM_DIR/p16_attack_overview_${TS}.tex"
OUT_ARCH_PNG="$SUM_DIR/p16_attack_overview_${TS}.png"
OUT_ARCH_PDF="$SUM_DIR/p16_attack_overview_${TS}.pdf"

python3 - "$BASE" "$LF" "$SF" "$SC" "$GA" "$RA" "$BD" \
  "$OUT_TAB_CSV" "$OUT_TAB_TEX" "$OUT_FIG_PNG" "$OUT_FIG_PDF" \
  "$OUT_ARCH_CSV" "$OUT_ARCH_TEX" "$OUT_ARCH_PNG" "$OUT_ARCH_PDF" <<'PY'
import sys, json, csv, math
from pathlib import Path

p_base, p_lf, p_sf, p_sc, p_ga, p_ra, p_bd = sys.argv[1:8]
out_csv, out_tex, out_png, out_pdf = map(Path, sys.argv[8:12])
arch_csv, arch_tex, arch_png, arch_pdf = map(Path, sys.argv[12:16])

def load(p):
    if not p:
        return None
    pp = Path(p)
    if not pp.exists():
        return None
    return json.load(pp.open())

def safe_get(d, path, default=None):
    cur = d
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur

def extract_metrics(d):
    if d is None or not isinstance(d, dict):
        return None

    if "pooled_honest" in d and "pooled_byz" in d:
        hf1  = safe_get(d, ["pooled_honest","f1","avg"])
        hfpr = safe_get(d, ["pooled_honest","fpr","avg"])
        bf1  = safe_get(d, ["pooled_byz","f1","avg"])
        bfpr = safe_get(d, ["pooled_byz","fpr","avg"])
        return hf1, hfpr, bf1, bfpr

    po = d.get("pooled_over_5rounds")
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

base = load(p_base)
base_m = extract_metrics(base)
if base_m is None:
    raise SystemExit("ERROR: baseline metrics introuvables")
base_f1, base_fpr, _, _ = base_m
if base_f1 is None or base_fpr is None:
    raise SystemExit("ERROR: baseline f1/fpr introuvables")

cases = [
    ("Baseline", base),
    ("LabelFlip", load(p_lf)),
    ("SignFlip",  load(p_sf)),
    ("Scaling",   load(p_sc)),
    ("Gaussian",  load(p_ga)),
    ("Random",    load(p_ra)),
    ("Backdoor",  load(p_bd)),
]

rows=[]
for name, d in cases:
    m = extract_metrics(d)
    if m is None:
        continue
    hf1,hfpr,bf1,bfpr = m
    rows.append({
        "scenario": name,
        "honest_f1": hf1,
        "honest_fpr": hfpr,
        "byz_f1": bf1,
        "byz_fpr": bfpr,
        "delta_honest_f1_vs_baseline": (hf1-base_f1) if hf1 is not None else None,
        "delta_honest_fpr_vs_baseline": (hfpr-base_fpr) if hfpr is not None else None,
    })

def f(x):
    if x is None or (isinstance(x,float) and (math.isnan(x))):
        return ""
    return f"{x:.4f}"

with out_csv.open("w", newline="") as fp:
    w = csv.writer(fp)
    w.writerow(["scenario","honest_f1","honest_fpr","byz_f1","byz_fpr","delta_honest_f1_vs_baseline","delta_honest_fpr_vs_baseline"])
    for r in rows:
        w.writerow([r["scenario"], f(r["honest_f1"]), f(r["honest_fpr"]), f(r["byz_f1"]), f(r["byz_fpr"]), f(r["delta_honest_f1_vs_baseline"]), f(r["delta_honest_fpr_vs_baseline"])])

tex=[]
tex.append(r"\begin{table}[!t]")
tex.append(r"\centering")
tex.append(r"\caption{Security \& dependability summary (pooled over 5 rounds). Baseline is pooled over all clients; attacks report honest vs Byzantine pools.}")
tex.append(r"\label{tab:security}")
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
out_tex.write_text("\n".join(tex)+"\n")

arch_csv.write_text(out_csv.read_text())
arch_tex.write_text(out_tex.read_text())

import matplotlib.pyplot as plt
plt.rcParams.update({
    "font.size": 9,
    "axes.titlesize": 9,
    "axes.labelsize": 9,
    "legend.fontsize": 8,
})

labels=[r["scenario"] for r in rows]
x=list(range(len(labels)))
w=0.28

hf1=[r["honest_f1"] for r in rows]
hfpr=[r["honest_fpr"] for r in rows]
bf1=[float("nan") if r["byz_f1"] is None else r["byz_f1"] for r in rows]
bfpr=[float("nan") if r["byz_fpr"] is None else r["byz_fpr"] for r in rows]

fig, ax = plt.subplots(1,2, figsize=(11.5,3.2), dpi=300)

ax[0].bar([i-w for i in x], hf1, width=w, label="Honest pool")
ax[0].bar([i+w for i in x], bf1, width=w, label="Byzantine pool")
ax[0].set_title("Pooled F1 (5 rounds)")
ax[0].set_xticks(x)
ax[0].set_xticklabels(labels, rotation=20, ha="right")
ax[0].set_ylim(0,1.0)
ax[0].grid(axis="y", alpha=0.25)

ax[1].bar([i-w for i in x], hfpr, width=w, label="Honest pool")
ax[1].bar([i+w for i in x], bfpr, width=w, label="Byzantine pool")
ax[1].set_title("Pooled FPR (5 rounds)")
ax[1].set_xticks(x)
ax[1].set_xticklabels(labels, rotation=20, ha="right")
ax[1].set_ylim(0,1.0)
ax[1].grid(axis="y", alpha=0.25)

ax[0].legend(loc="upper left", frameon=False)

fig.tight_layout()
fig.savefig(out_png, bbox_inches="tight")
fig.savefig(out_pdf, bbox_inches="tight")
fig.savefig(arch_png, bbox_inches="tight")
fig.savefig(arch_pdf, bbox_inches="tight")

print("OK")
print("FIG_PNG=", out_png)
print("FIG_PDF=", out_pdf)
print("TAB_CSV=", out_csv)
print("TAB_TEX=", out_tex)
print("ARCH_CSV=", arch_csv)
print("ARCH_TEX=", arch_tex)
PY

echo OK
echo FIG_PNG="$OUT_FIG_PNG"
echo FIG_PDF="$OUT_FIG_PDF"
echo TABLE_CSV="$OUT_TAB_CSV"
echo TABLE_TEX="$OUT_TAB_TEX"
