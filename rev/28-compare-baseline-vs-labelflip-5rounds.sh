#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p9_compare_baseline_vs_labelflip_5rounds_${TS}.csv"
OUT_JSON="$SUM_DIR/p9_compare_baseline_vs_labelflip_5rounds_${TS}.json"

python3 - "$SUM_DIR" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, json, re
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_csv = Path(sys.argv[2])
out_json = Path(sys.argv[3])

def norm_ts(s: str) -> str:
    return re.sub(r"[^0-9]", "", s)

def pick_latest(glob_pat):
    best = None
    for p in sum_dir.glob(glob_pat):
        m = re.search(r"_(\d{8}_\d{6}|\d{14})\.json$", p.name)
        if not m:
            continue
        ts = norm_ts(m.group(1))
        if best is None or ts > best[0]:
            best = (ts, p)
    return best[1] if best else None

baseline_path = pick_latest("p7_baseline_5rounds_clean_*.json")
labelflip_path = pick_latest("p8_labelflip_5rounds_clean_*.json")

if not baseline_path:
    print("ERROR: baseline clean json introuvable (p7_baseline_5rounds_clean_*.json)")
    sys.exit(1)
if not labelflip_path:
    print("ERROR: labelflip clean json introuvable (p8_labelflip_5rounds_clean_*.json)")
    sys.exit(1)

baseline = json.loads(baseline_path.read_text())
labelflip = json.loads(labelflip_path.read_text())

def get_pooled_baseline(obj):
    if isinstance(obj, dict) and "f1" in obj and "fpr" in obj and "n_points" in obj:
        return obj
    for k in ["pooled","POOLED","pooled_all","stats"]:
        if k in obj and isinstance(obj[k], dict):
            if "f1" in obj[k] and "fpr" in obj[k]:
                return obj[k]
    return obj

def safe_get(d, *keys):
    cur = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return None
        cur = cur[k]
    return cur

base_p = get_pooled_baseline(baseline)

lf_all = safe_get(labelflip, "pooled_all")
lf_byz = safe_get(labelflip, "pooled_byz")
lf_hon = safe_get(labelflip, "pooled_honest")

def row_pack(name, grp, p):
    if not isinstance(p, dict):
        return None
    f1 = p.get("f1") or {}
    fpr = p.get("fpr") or {}
    ipfs = p.get("ipfs_ms") or {}
    tx = p.get("tx_ms") or {}
    total = p.get("total_ms") or {}
    return {
        "scenario": name,
        "group": grp,
        "n_points": p.get("n_points") or (f1.get("n") if isinstance(f1, dict) else None),
        "f1_avg": (f1.get("avg") if isinstance(f1, dict) else None),
        "f1_std": (f1.get("std") if isinstance(f1, dict) else None),
        "fpr_avg": (fpr.get("avg") if isinstance(fpr, dict) else None),
        "fpr_std": (fpr.get("std") if isinstance(fpr, dict) else None),
        "ipfs_p50": (ipfs.get("p50") if isinstance(ipfs, dict) else None),
        "ipfs_p95": (ipfs.get("p95") if isinstance(ipfs, dict) else None),
        "tx_p50": (tx.get("p50") if isinstance(tx, dict) else None),
        "tx_p95": (tx.get("p95") if isinstance(tx, dict) else None),
        "total_p50": (total.get("p50") if isinstance(total, dict) else None),
        "total_p95": (total.get("p95") if isinstance(total, dict) else None),
    }

rows = []
rows.append(row_pack("baseline", "all", base_p))
if lf_all: rows.append(row_pack("labelflip", "all", lf_all))
if lf_hon: rows.append(row_pack("labelflip", "honest", lf_hon))
if lf_byz: rows.append(row_pack("labelflip", "byz", lf_byz))
rows = [r for r in rows if r]

base_f1 = rows[0].get("f1_avg")
base_fpr = rows[0].get("fpr_avg")

for r in rows:
    if r["scenario"] == "baseline" and r["group"] == "all":
        r["f1_delta_vs_baseline"] = 0.0
        r["fpr_delta_vs_baseline"] = 0.0
        r["f1_pct_vs_baseline"] = 0.0
        r["fpr_pct_vs_baseline"] = 0.0
        continue
    if base_f1 is not None and r.get("f1_avg") is not None:
        d = r["f1_avg"] - base_f1
        r["f1_delta_vs_baseline"] = d
        r["f1_pct_vs_baseline"] = (100.0 * d / base_f1) if base_f1 != 0 else None
    else:
        r["f1_delta_vs_baseline"] = None
        r["f1_pct_vs_baseline"] = None

    if base_fpr is not None and r.get("fpr_avg") is not None:
        d = r["fpr_avg"] - base_fpr
        r["fpr_delta_vs_baseline"] = d
        r["fpr_pct_vs_baseline"] = (100.0 * d / base_fpr) if base_fpr != 0 else None
    else:
        r["fpr_delta_vs_baseline"] = None
        r["fpr_pct_vs_baseline"] = None

hdr = [
    "scenario","group","n_points",
    "f1_avg","f1_std","f1_delta_vs_baseline","f1_pct_vs_baseline",
    "fpr_avg","fpr_std","fpr_delta_vs_baseline","fpr_pct_vs_baseline",
    "ipfs_p50","ipfs_p95","tx_p50","tx_p95","total_p50","total_p95"
]
out_csv.write_text(",".join(hdr) + "\n")
with out_csv.open("a") as f:
    for r in rows:
        vals = [r.get(k) for k in hdr]
        def fmt(x):
            if x is None: return ""
            if isinstance(x, float): return f"{x:.6f}".rstrip("0").rstrip(".")
            return str(x)
        f.write(",".join(fmt(v) for v in vals) + "\n")

summary = {
    "inputs": {
        "baseline_clean": str(baseline_path),
        "labelflip_clean": str(labelflip_path),
    },
    "rows": rows,
    "notes": [
        "baseline=pooled sur 5 rounds (100 points: 20 clients x 5 rounds).",
        "labelflip: comparaison pooled_all / pooled_honest / pooled_byz vs baseline.",
    ]
}
out_json.write_text(json.dumps(summary, indent=2))

print("OK")
print("IN_BASELINE=", str(baseline_path))
print("IN_LABELFLIP=", str(labelflip_path))
print("OUT_CSV=", str(out_csv))
print("OUT_JSON=", str(out_json))

def show(name, grp):
    for r in rows:
        if r["scenario"]==name and r["group"]==grp:
            return r
    return None

b = show("baseline","all")
h = show("labelflip","honest")
z = show("labelflip","byz")

if b:
    print("BASELINE_F1_AVG=", b.get("f1_avg"), " BASELINE_FPR_AVG=", b.get("fpr_avg"))
if h:
    print("HONEST_F1_AVG=", h.get("f1_avg"), " DELTA=", h.get("f1_delta_vs_baseline"),
          " | HONEST_FPR_AVG=", h.get("fpr_avg"), " DELTA=", h.get("fpr_delta_vs_baseline"))
if z:
    print("BYZ_F1_AVG=", z.get("f1_avg"), " DELTA=", z.get("f1_delta_vs_baseline"),
          " | BYZ_FPR_AVG=", z.get("fpr_avg"), " DELTA=", z.get("fpr_delta_vs_baseline"))
PY
