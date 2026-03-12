#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

IN_BASELINE="${IN_BASELINE:-$(ls -t "$SUM_DIR"/p7_baseline_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"
IN_SIGNFLIP="${IN_SIGNFLIP:-$(ls -t "$SUM_DIR"/p10_signflip_5rounds_clean_*.json 2>/dev/null | head -n 1 || true)}"

[ -f "$IN_BASELINE" ] || { echo "ERROR: baseline json introuvable: $IN_BASELINE"; exit 1; }
[ -f "$IN_SIGNFLIP" ] || { echo "ERROR: signflip json introuvable: $IN_SIGNFLIP"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p11_paper_table_baseline_vs_signflip_${TS}.csv"
OUT_JSON="$SUM_DIR/p11_paper_table_baseline_vs_signflip_${TS}.json"
OUT_TEX="$SUM_DIR/p11_paper_table_baseline_vs_signflip_${TS}.tex"
OUT_F1_PNG="$SUM_DIR/p11_fig_f1_baseline_vs_signflip_${TS}.png"
OUT_FPR_PNG="$SUM_DIR/p11_fig_fpr_baseline_vs_signflip_${TS}.png"
OUT_ROUNDS_CSV="$SUM_DIR/p11_rounds_baseline_vs_signflip_${TS}.csv"

python3 - "$IN_BASELINE" "$IN_SIGNFLIP" "$OUT_TABLE" "$OUT_JSON" "$OUT_TEX" "$OUT_F1_PNG" "$OUT_FPR_PNG" "$OUT_ROUNDS_CSV" <<'PY'
import sys, json, csv
from pathlib import Path

p_base, p_sf, out_table, out_json, out_tex, out_f1, out_fpr, out_rounds = sys.argv[1:9]
base = json.load(open(p_base))
sf   = json.load(open(p_sf))

def get_avg(obj, path):
    cur = obj
    for k in path:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    if isinstance(cur, dict) and "avg" in cur:
        return float(cur["avg"])
    return None

base_f1 = get_avg(base, ["pooled_over_5rounds","f1"])
base_fpr = get_avg(base, ["pooled_over_5rounds","fpr"])

hon_f1 = get_avg(sf, ["pooled_over_5rounds","pooled_honest","f1"])
hon_fpr = get_avg(sf, ["pooled_over_5rounds","pooled_honest","fpr"])

byz_f1 = get_avg(sf, ["pooled_over_5rounds","pooled_byz","f1"])
byz_fpr = get_avg(sf, ["pooled_over_5rounds","pooled_byz","fpr"])

def delta(v, ref):
    if v is None or ref is None:
        return None
    return v - ref

rows = [
    ["Baseline (all clients)", base_f1, base_fpr, None, None],
    ["Signflip (honest)", hon_f1, hon_fpr, delta(hon_f1, base_f1), delta(hon_fpr, base_fpr)],
    ["Signflip (byzantine)", byz_f1, byz_fpr, delta(byz_f1, base_f1), delta(byz_fpr, base_fpr)],
]

with open(out_table, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["scenario","f1_avg","fpr_avg","delta_f1_vs_baseline","delta_fpr_vs_baseline"])
    w.writerows(rows)

tex = []
tex.append("\\begin{table}[t]")
tex.append("\\centering")
tex.append("\\caption{Baseline vs Signflip (5 rounds, N=20).}")
tex.append("\\begin{tabular}{lcccc}")
tex.append("\\hline")
tex.append("Scenario & F1 (avg) & FPR (avg) & $\\Delta$F1 & $\\Delta$FPR\\\\")
tex.append("\\hline")
for sc,f1,fpr,df1,dfpr in rows:
    def fmt(x):
        return "--" if x is None else f"{x:.4f}"
    tex.append(f"{sc} & {fmt(f1)} & {fmt(fpr)} & {fmt(df1)} & {fmt(dfpr)}\\\\")
tex.append("\\hline")
tex.append("\\end{tabular}")
tex.append("\\end{table}")
Path(out_tex).write_text("\n".join(tex) + "\n")

def get_base_round_avg(r, metric):
    pr = base.get("per_round", {})
    k = str(r)
    if k in pr and isinstance(pr[k], dict):
        return get_avg(pr[k], [metric])
    return None

def get_sf_round_avg(r, group, metric):
    pr = sf.get("per_round", {})
    k = str(r)
    if k not in pr or not isinstance(pr[k], dict):
        return None
    key = f"{metric}_{group}"
    return get_avg(pr[k], [key])

round_rows=[]
for r in range(1,6):
    round_rows.append([
        r,
        get_base_round_avg(r,"f1"),
        get_base_round_avg(r,"fpr"),
        get_sf_round_avg(r,"honest","f1"),
        get_sf_round_avg(r,"byz","f1"),
        get_sf_round_avg(r,"honest","fpr"),
        get_sf_round_avg(r,"byz","fpr"),
    ])

with open(out_rounds, "w", newline="") as f:
    w=csv.writer(f)
    w.writerow(["round","baseline_f1","baseline_fpr","honest_f1","byz_f1","honest_fpr","byz_fpr"])
    w.writerows(round_rows)

try:
    import matplotlib.pyplot as plt

    rounds=[r[0] for r in round_rows]
    b_f1=[r[1] for r in round_rows]
    h_f1=[r[3] for r in round_rows]
    z_f1=[r[4] for r in round_rows]

    plt.figure()
    plt.plot(rounds, b_f1, marker="o", label="Baseline (all)")
    plt.plot(rounds, h_f1, marker="o", label="Signflip (honest)")
    plt.plot(rounds, z_f1, marker="o", label="Signflip (byz)")
    plt.xlabel("Round")
    plt.ylabel("F1 (avg)")
    plt.title("F1 per round: Baseline vs Signflip")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_f1, dpi=200)
    plt.close()

    b_fpr=[r[2] for r in round_rows]
    h_fpr=[r[5] for r in round_rows]
    z_fpr=[r[6] for r in round_rows]

    plt.figure()
    plt.plot(rounds, b_fpr, marker="o", label="Baseline (all)")
    plt.plot(rounds, h_fpr, marker="o", label="Signflip (honest)")
    plt.plot(rounds, z_fpr, marker="o", label="Signflip (byz)")
    plt.xlabel("Round")
    plt.ylabel("FPR (avg)")
    plt.title("FPR per round: Baseline vs Signflip")
    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_fpr, dpi=200)
    plt.close()

except Exception as e:
    print("WARN: matplotlib plot skipped:", e)

out = {
    "inputs": {"baseline": p_base, "signflip": p_sf},
    "summary_table_csv": out_table,
    "summary_table_tex": out_tex,
    "rounds_csv": out_rounds,
    "fig_f1_png": out_f1,
    "fig_fpr_png": out_fpr,
    "baseline_all": {"f1_avg": base_f1, "fpr_avg": base_fpr},
    "signflip_honest": {"f1_avg": hon_f1, "fpr_avg": hon_fpr},
    "signflip_byz": {"f1_avg": byz_f1, "fpr_avg": byz_fpr},
}
Path(out_json).write_text(json.dumps(out, indent=2))
print("OK")
print("IN_BASELINE=", p_base)
print("IN_SIGNFLIP=", p_sf)
print("OUT_TABLE=", out_table)
print("OUT_JSON=", out_json)
print("OUT_TEX=", out_tex)
print("OUT_F1_PNG=", out_f1)
print("OUT_FPR_PNG=", out_fpr)
PY

echo "OK"
echo "IN_BASELINE= $IN_BASELINE"
echo "IN_SIGNFLIP= $IN_SIGNFLIP"
echo "OUT_TABLE= $OUT_TABLE"
echo "OUT_JSON= $OUT_JSON"
echo "OUT_TEX= $OUT_TEX"
echo "OUT_F1_PNG= $OUT_F1_PNG"
echo "OUT_FPR_PNG= $OUT_FPR_PNG"
echo "OUT_ROUNDS_CSV= $OUT_ROUNDS_CSV"
