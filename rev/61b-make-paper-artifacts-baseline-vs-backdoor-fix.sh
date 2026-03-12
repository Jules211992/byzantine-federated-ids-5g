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
OUT_TABLE="$SUM_DIR/p15_paper_table_baseline_vs_backdoor_${TS}.csv"
OUT_JSON="$SUM_DIR/p15_paper_table_baseline_vs_backdoor_${TS}.json"
OUT_TEX="$SUM_DIR/p15_paper_table_baseline_vs_backdoor_${TS}.tex"
OUT_F1_PNG="$SUM_DIR/p15_fig_f1_baseline_vs_backdoor_${TS}.png"
OUT_FPR_PNG="$SUM_DIR/p15_fig_fpr_baseline_vs_backdoor_${TS}.png"
OUT_ROUNDS_CSV="$SUM_DIR/p15_rounds_baseline_vs_backdoor_${TS}.csv"

python3 - "$IN_BASELINE" "$IN_BACKDOOR" "$OUT_TABLE" "$OUT_JSON" "$OUT_TEX" "$OUT_F1_PNG" "$OUT_FPR_PNG" "$OUT_ROUNDS_CSV" <<'PY'
import sys, json, csv
from pathlib import Path

p_base, p_bd, out_table, out_json, out_tex, out_f1, out_fpr, out_rounds = sys.argv[1:9]
base = json.load(open(p_base))
bd   = json.load(open(p_bd))

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
    raise SystemExit("ERROR: cannot locate honest/byz pooled metrics in backdoor clean json")

_, hon_f1, hon_fpr = hon
_, byz_f1, byz_fpr = byz

rows = [
  ["baseline","all",base_f1,base_fpr,0.0,0.0],
  ["backdoor","honest",hon_f1,hon_fpr,hon_f1-base_f1,hon_fpr-base_fpr],
  ["backdoor","byz",byz_f1,byz_fpr,byz_f1-base_f1,byz_fpr-base_fpr],
]

with open(out_table,"w",newline="") as f:
    w=csv.writer(f)
    w.writerow(["scenario","group","f1_avg","fpr_avg","delta_f1_vs_baseline","delta_fpr_vs_baseline"])
    w.writerows(rows)

out = {
  "inputs": {"baseline": p_base, "backdoor": p_bd},
  "baseline": {"f1_avg": base_f1, "fpr_avg": base_fpr},
  "backdoor": {"honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr}, "byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr}},
  "files": {"table_csv": out_table, "table_tex": out_tex, "f1_png": out_f1, "fpr_png": out_fpr, "rounds_csv": out_rounds}
}
json.dump(out, open(out_json,"w"), indent=2)

tex = r"""\begin{table}[t]
\centering
\caption{Baseline vs Backdoor attack (5 rounds, N=20).}
\label{tab:baseline_backdoor}
\begin{tabular}{l l r r r r}
\hline
Scenario & Group & F1 & FPR & $\Delta$F1 & $\Delta$FPR \\
\hline
baseline & all & %.4f & %.4f & %.4f & %.4f \\
backdoor & honest & %.4f & %.4f & %.4f & %.4f \\
backdoor & byz & %.4f & %.4f & %.4f & %.4f \\
\hline
\end{tabular}
\end{table}
""" % (rows[0][2],rows[0][3],rows[0][4],rows[0][5],
       rows[1][2],rows[1][3],rows[1][4],rows[1][5],
       rows[2][2],rows[2][3],rows[2][4],rows[2][5])
Path(out_tex).write_text(tex)

# rounds csv (best-effort)
with open(out_rounds,"w",newline="") as f:
    w=csv.writer(f)
    w.writerow(["round","baseline_f1","baseline_fpr","honest_f1","honest_fpr","byz_f1","byz_fpr"])
    # if per_round exists, try to emit baseline values, else leave empty
    per_b = base.get("per_round", [])
    per_a = bd.get("per_round", [])
    n = max(len(per_b), len(per_a))
    for i in range(n):
        w.writerow([i+1,"","","","","",""])

# figs (simple bar)
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

labels = ["baseline","honest","byz"]
f1s = [base_f1, hon_f1, byz_f1]
fprs= [base_fpr, hon_fpr, byz_fpr]

plt.figure()
plt.bar(labels, f1s)
plt.ylabel("F1 (avg over 5 rounds)")
plt.tight_layout()
plt.savefig(out_f1)
plt.close()

plt.figure()
plt.bar(labels, fprs)
plt.ylabel("FPR (avg over 5 rounds)")
plt.tight_layout()
plt.savefig(out_fpr)
plt.close()

print("OK")
print("IN_BASELINE=", p_base)
print("IN_BACKDOOR=", p_bd)
print("OUT_TABLE=", out_table)
print("OUT_JSON=", out_json)
print("OUT_TEX=", out_tex)
print("OUT_F1_PNG=", out_f1)
print("OUT_FPR_PNG=", out_fpr)
print("OUT_ROUNDS_CSV=", out_rounds)
PY
