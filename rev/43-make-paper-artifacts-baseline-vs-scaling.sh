#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_SCALING="${IN_SCALING:-$(ls -t "$SUM_DIR"/p12_scaling_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_SCALING" ] || { echo "ERROR: scaling json introuvable: $IN_SCALING"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p12_paper_table_baseline_vs_scaling_${TS}.csv"
OUT_JSON="$SUM_DIR/p12_paper_table_baseline_vs_scaling_${TS}.json"
OUT_TEX="$SUM_DIR/p12_paper_table_baseline_vs_scaling_${TS}.tex"
OUT_F1_PNG="$SUM_DIR/p12_fig_f1_baseline_vs_scaling_${TS}.png"
OUT_FPR_PNG="$SUM_DIR/p12_fig_fpr_baseline_vs_scaling_${TS}.png"
OUT_ROUNDS_CSV="$SUM_DIR/p12_rounds_baseline_vs_scaling_${TS}.csv"

python3 - "$IN_BASELINE" "$IN_SCALING" "$OUT_TABLE" "$OUT_JSON" "$OUT_TEX" "$OUT_F1_PNG" "$OUT_FPR_PNG" "$OUT_ROUNDS_CSV" <<'PY'
import sys, json, csv
from pathlib import Path

p_base, p_sc, out_table, out_json, out_tex, out_f1, out_fpr, out_rounds = sys.argv[1:9]
base = json.load(open(p_base))
sc   = json.load(open(p_sc))

def per_round_as_dict(x):
    if isinstance(x, dict):
        return x
    if isinstance(x, list):
        d = {}
        for idx, e in enumerate(x, start=1):
            if isinstance(e, dict):
                r = e.get("round") or e.get("round_num") or idx
                try:
                    r = int(r)
                except Exception:
                    r = idx
                d[str(r)] = e
        return d
    return {}

def get_avg(entry, key):
    for k in (key, f"{key}_all", f"{key}_avg", f"{key}_mean"):
        v = entry.get(k)
        if isinstance(v, dict) and "avg" in v:
            return v["avg"]
        if isinstance(v, (int,float)):
            return float(v)
    return None

b_f1 = base["pooled_over_5rounds"]["f1"]["avg"]
b_fpr = base["pooled_over_5rounds"]["fpr"]["avg"]

h_f1 = sc["pooled_over_5rounds"]["honest"]["f1"]["avg"]
h_fpr = sc["pooled_over_5rounds"]["honest"]["fpr"]["avg"]
z_f1 = sc["pooled_over_5rounds"]["byz"]["f1"]["avg"]
z_fpr = sc["pooled_over_5rounds"]["byz"]["fpr"]["avg"]

rows = [
  {"group":"Baseline (no attack)","f1_avg":b_f1,"fpr_avg":b_fpr},
  {"group":"Scaling (honest)","f1_avg":h_f1,"fpr_avg":h_fpr},
  {"group":"Scaling (byzantine)","f1_avg":z_f1,"fpr_avg":z_fpr},
]

with open(out_table,"w",newline="") as f:
  w = csv.DictWriter(f, fieldnames=["group","f1_avg","fpr_avg"])
  w.writeheader()
  for r in rows:
    w.writerow(r)

tex = []
tex.append(r"\begin{table}[t]")
tex.append(r"\centering")
tex.append(r"\caption{Baseline vs. Scaling attack (5 rounds, pooled).}")
tex.append(r"\begin{tabular}{lcc}")
tex.append(r"\hline")
tex.append(r"Scenario & F1 (avg) & FPR (avg) \\")
tex.append(r"\hline")
for r in rows:
  tex.append(f"{r['group']} & {r['f1_avg']:.4f} & {r['fpr_avg']:.4f} \\\\")
tex.append(r"\hline")
tex.append(r"\end{tabular}")
tex.append(r"\end{table}")
Path(out_tex).write_text("\n".join(tex) + "\n")

out = {
  "inputs": {"baseline": p_base, "scaling": p_sc},
  "baseline": {"f1_avg": b_f1, "fpr_avg": b_fpr},
  "scaling_honest": {"f1_avg": h_f1, "fpr_avg": h_fpr},
  "scaling_byz": {"f1_avg": z_f1, "fpr_avg": z_fpr},
  "files": {"table_csv": out_table, "json": out_json, "tex": out_tex, "f1_png": out_f1, "fpr_png": out_fpr, "rounds_csv": out_rounds}
}
Path(out_json).write_text(json.dumps(out, indent=2))

import matplotlib.pyplot as plt

labels = ["Baseline","Honest","Byzantine"]
plt.figure()
plt.bar(labels, [b_f1, h_f1, z_f1])
plt.ylabel("F1")
plt.tight_layout()
plt.savefig(out_f1, dpi=200)
plt.close()

plt.figure()
plt.bar(labels, [b_fpr, h_fpr, z_fpr])
plt.ylabel("FPR")
plt.tight_layout()
plt.savefig(out_fpr, dpi=200)
plt.close()

r_base = per_round_as_dict(base.get("per_round", {}))
r_sc   = per_round_as_dict(sc.get("per_round", {}))

rounds = sorted(set(r_base.keys()) & set(r_sc.keys()), key=lambda x: int(x))

with open(out_rounds,"w",newline="") as f:
  w = csv.DictWriter(f, fieldnames=[
    "round",
    "baseline_f1","baseline_fpr",
    "scaling_honest_f1","scaling_honest_fpr",
    "scaling_byz_f1","scaling_byz_fpr"
  ])
  w.writeheader()
  for rr in rounds:
    rb = r_base[rr]
    rs = r_sc[rr]
    w.writerow({
      "round": int(rr),
      "baseline_f1": get_avg(rb, "f1"),
      "baseline_fpr": get_avg(rb, "fpr"),
      "scaling_honest_f1": ((rs.get("honest") or {}).get("f1") or {}).get("avg"),
      "scaling_honest_fpr": ((rs.get("honest") or {}).get("fpr") or {}).get("avg"),
      "scaling_byz_f1": ((rs.get("byz") or {}).get("f1") or {}).get("avg"),
      "scaling_byz_fpr": ((rs.get("byz") or {}).get("fpr") or {}).get("avg"),
    })

print("OK")
print("IN_BASELINE=", p_base)
print("IN_SCALING=", p_sc)
print("OUT_TABLE=", out_table)
print("OUT_JSON=", out_json)
print("OUT_TEX=", out_tex)
print("OUT_F1_PNG=", out_f1)
print("OUT_FPR_PNG=", out_fpr)
print("OUT_ROUNDS_CSV=", out_rounds)
PY
