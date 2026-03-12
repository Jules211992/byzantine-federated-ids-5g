#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_GAUSSIAN="${IN_GAUSSIAN:-$(ls -t "$SUM_DIR"/p13_gaussian_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_GAUSSIAN" ] || { echo "ERROR: gaussian json introuvable: $IN_GAUSSIAN"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p13_paper_table_baseline_vs_gaussian_${TS}.csv"
OUT_JSON="$SUM_DIR/p13_paper_table_baseline_vs_gaussian_${TS}.json"
OUT_TEX="$SUM_DIR/p13_paper_table_baseline_vs_gaussian_${TS}.tex"
OUT_F1_PNG="$SUM_DIR/p13_fig_f1_baseline_vs_gaussian_${TS}.png"
OUT_FPR_PNG="$SUM_DIR/p13_fig_fpr_baseline_vs_gaussian_${TS}.png"
OUT_ROUNDS_CSV="$SUM_DIR/p13_rounds_baseline_vs_gaussian_${TS}.csv"

python3 - "$IN_BASELINE" "$IN_GAUSSIAN" "$OUT_TABLE" "$OUT_JSON" "$OUT_TEX" "$OUT_F1_PNG" "$OUT_FPR_PNG" "$OUT_ROUNDS_CSV" <<'PY'
import sys, json, csv, math
from pathlib import Path

p_base, p_g, out_table, out_json, out_tex, out_f1, out_fpr, out_rounds = sys.argv[1:9]
base = json.load(open(p_base))
g = json.load(open(p_g))

def fmt(x, nd=4):
    try:
        return f"{float(x):.{nd}f}"
    except:
        return ""

def pm(avg, std, nd=4):
    try:
        return f"{float(avg):.{nd}f} ± {float(std):.{nd}f}"
    except:
        return ""

def get_round_entry(per_round, r):
    if per_round is None:
        return None
    if isinstance(per_round, dict):
        return per_round.get(str(r)) or per_round.get(r)
    if isinstance(per_round, list):
        for e in per_round:
            if isinstance(e, dict) and (e.get("round") == r or e.get("round") == str(r)):
                return e
    return None

def get_chosen_csv(chosen, r):
    if chosen is None:
        return None
    if isinstance(chosen, dict):
        return chosen.get(str(r)) or chosen.get(r)
    if isinstance(chosen, list):
        idx = r - 1
        if 0 <= idx < len(chosen):
            return chosen[idx]
    return None

bpool = base.get("pooled_over_5rounds") or base.get("pooled") or {}
gpool = g.get("pooled_over_5rounds") or g.get("pooled") or {}

baseline_f1 = bpool["f1"]["avg"]
baseline_f1s = bpool["f1"].get("std", 0.0)
baseline_fpr = bpool["fpr"]["avg"]
baseline_fprs = bpool["fpr"].get("std", 0.0)

hon = gpool.get("pooled_honest") or {}
byz = gpool.get("pooled_byz") or {}

hon_f1 = hon["f1"]["avg"]; hon_f1s = hon["f1"].get("std", 0.0)
hon_fpr = hon["fpr"]["avg"]; hon_fprs = hon["fpr"].get("std", 0.0)

byz_f1 = byz["f1"]["avg"]; byz_f1s = byz["f1"].get("std", 0.0)
byz_fpr = byz["fpr"]["avg"]; byz_fprs = byz["fpr"].get("std", 0.0)

b_tot_p95 = bpool.get("total_ms", {}).get("p95", None)
g_tot_p95 = gpool.get("total_ms", {}).get("p95", None)

b_ipfs_p95 = bpool.get("ipfs_ms", {}).get("p95", None)
b_tx_p95   = bpool.get("tx_ms", {}).get("p95", None)

g_ipfs_p95 = gpool.get("ipfs_ms", {}).get("p95", None)
g_tx_p95   = gpool.get("tx_ms", {}).get("p95", None)

rows = [
  ["baseline(all)", pm(baseline_f1, baseline_f1s), pm(baseline_fpr, baseline_fprs), fmt(b_ipfs_p95,2), fmt(b_tx_p95,2), fmt(b_tot_p95,2)],
  ["gaussian(honest)", pm(hon_f1, hon_f1s), pm(hon_fpr, hon_fprs), fmt(g_ipfs_p95,2), fmt(g_tx_p95,2), fmt(g_tot_p95,2)],
  ["gaussian(byz)", pm(byz_f1, byz_f1s), pm(byz_fpr, byz_fprs), fmt(g_ipfs_p95,2), fmt(g_tx_p95,2), fmt(g_tot_p95,2)],
]

with open(out_table,"w",newline="") as f:
    wr=csv.writer(f)
    wr.writerow(["group","f1(avg±std)","fpr(avg±std)","ipfs_p95_ms","tx_p95_ms","total_p95_ms"])
    wr.writerows(rows)

tex = r"""\begin{table}[t]
\centering
\caption{Baseline vs Gaussian noise attack (5 rounds, N=20). Metrics reported as mean $\pm$ std across clients.}
\label{tab:baseline-vs-gaussian}
\begin{tabular}{lccc}
\hline
Group & F1 & FPR & Total p95 (ms)\\
\hline
%s \\
%s \\
%s \\
\hline
\end{tabular}
\end{table}
""" % (
    f"Baseline (all) & {pm(baseline_f1, baseline_f1s)} & {pm(baseline_fpr, baseline_fprs)} & {fmt(b_tot_p95,2)}",
    f"Gaussian (honest) & {pm(hon_f1, hon_f1s)} & {pm(hon_fpr, hon_fprs)} & {fmt(g_tot_p95,2)}",
    f"Gaussian (byz) & {pm(byz_f1, byz_f1s)} & {pm(byz_fpr, byz_fprs)} & {fmt(g_tot_p95,2)}",
)
Path(out_tex).write_text(tex)

byz_clients = g.get("byz_clients")
if isinstance(byz_clients, str):
    byz_set = set(byz_clients.split())
elif isinstance(byz_clients, list):
    byz_set = set(byz_clients)
else:
    byz_set = set(["edge-client-1","edge-client-6","edge-client-11","edge-client-16"])

def avg_from_csv(path, want="f1", honest=None):
    vals=[]
    with open(path, newline="") as f:
        rd=csv.DictReader(f)
        for r in rd:
            cid=r.get("client_id","")
            if honest is True and cid in byz_set:
                continue
            if honest is False and cid not in byz_set:
                continue
            try:
                vals.append(float(r.get(want,"")))
            except:
                pass
    return sum(vals)/len(vals) if vals else None

with open(out_rounds,"w",newline="") as f:
    wr=csv.writer(f)
    wr.writerow(["round","baseline_f1","baseline_fpr","gaussian_honest_f1","gaussian_honest_fpr","gaussian_byz_f1","gaussian_byz_fpr"])
    for r in range(1,6):
        be = get_round_entry(base.get("per_round"), r)
        bf1 = be.get("f1",{}).get("avg") if isinstance(be, dict) else None
        bfpr = be.get("fpr",{}).get("avg") if isinstance(be, dict) else None

        gcsv = get_chosen_csv(g.get("chosen_csv_per_round"), r)
        if not gcsv:
            patt = list(Path(Path(p_g).parent).glob(f"p13_gaussian_round{r:02d}_clients_*.csv"))
            gcsv = str(sorted(patt)[-1]) if patt else None

        hf1 = avg_from_csv(gcsv, "f1", honest=True) if gcsv else None
        hfpr = avg_from_csv(gcsv, "fpr", honest=True) if gcsv else None
        yf1 = avg_from_csv(gcsv, "f1", honest=False) if gcsv else None
        yfpr = avg_from_csv(gcsv, "fpr", honest=False) if gcsv else None

        wr.writerow([r, bf1, bfpr, hf1, hfpr, yf1, yfpr])

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

labels=["Baseline","Gaussian-Honest","Gaussian-Byz"]

plt.figure()
plt.bar(labels, [baseline_f1, hon_f1, byz_f1])
plt.ylabel("F1 (avg)")
plt.tight_layout()
plt.savefig(out_f1, dpi=200)
plt.close()

plt.figure()
plt.bar(labels, [baseline_fpr, hon_fpr, byz_fpr])
plt.ylabel("FPR (avg)")
plt.tight_layout()
plt.savefig(out_fpr, dpi=200)
plt.close()

res = {
  "inputs": {"baseline": p_base, "gaussian": p_g},
  "outputs": {"table_csv": out_table, "table_tex": out_tex, "f1_png": out_f1, "fpr_png": out_fpr, "rounds_csv": out_rounds, "json": out_json},
  "baseline": {"f1_avg": baseline_f1, "fpr_avg": baseline_fpr},
  "gaussian_honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr},
  "gaussian_byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr},
}
json.dump(res, open(out_json,"w"), indent=2)

print("OK")
print("IN_BASELINE=", p_base)
print("IN_GAUSSIAN=", p_g)
print("OUT_TABLE=", out_table)
print("OUT_JSON=", out_json)
print("OUT_TEX=", out_tex)
print("OUT_F1_PNG=", out_f1)
print("OUT_FPR_PNG=", out_fpr)
print("OUT_ROUNDS_CSV=", out_rounds)
PY
