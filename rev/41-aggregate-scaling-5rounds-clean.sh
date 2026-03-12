#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p12_scaling_5rounds_table_${TS}.csv"
OUT_JSON="$SUM_DIR/p12_scaling_5rounds_clean_${TS}.json"

python3 - "$SUM_DIR" "$OUT_TABLE" "$OUT_JSON" "$BYZ_CLIENTS" <<'PY'
import sys, csv, json, re, math
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_table = Path(sys.argv[2])
out_json = Path(sys.argv[3])
byz_set = set(sys.argv[4].split())

def safe_float(x):
    try:
        if x is None: return None
        s = str(x).strip()
        if s == "" or s.lower() in ("none","nan"): return None
        return float(s)
    except Exception:
        return None

def pct(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    k = (len(s)-1) * (p/100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(s[int(k)])
    return float(s[f] + (s[c]-s[f])*(k-f))

def stats(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    n = len(vals)
    avg = sum(vals)/n
    if n > 1:
        var = sum((v-avg)**2 for v in vals)/(n-1)
        std = math.sqrt(var)
    else:
        std = 0.0
    return {
        "avg": avg,
        "std": std,
        "min": min(vals),
        "max": max(vals),
        "p50": pct(vals,50),
        "p95": pct(vals,95),
        "p99": pct(vals,99),
        "n": n
    }

def pick_latest(pattern):
    files = list(sum_dir.glob(pattern))
    if not files:
        return None
    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return files[0]

def find_col(fields, want):
    f = [x for x in fields]
    low = [x.lower() for x in fields]

    if want == "client":
        for cand in ("client_id","client","cid"):
            if cand in low:
                return f[low.index(cand)]
        for i,n in enumerate(low):
            if "client" in n and "id" in n:
                return f[i]
        return f[0]

    if want == "f1":
        for i,n in enumerate(low):
            if ("test" in n and "f1" in n) or n == "f1":
                return f[i]
        for i,n in enumerate(low):
            if "f1" in n and "train" not in n:
                return f[i]
        return None

    if want == "fpr":
        for i,n in enumerate(low):
            if ("test" in n and "fpr" in n) or n == "fpr":
                return f[i]
        for i,n in enumerate(low):
            if "fpr" in n and "train" not in n:
                return f[i]
        return None

    if want == "ipfs":
        for i,n in enumerate(low):
            if "ipfs" in n and "ms" in n:
                return f[i]
        for i,n in enumerate(low):
            if "ipfs_add" in n:
                return f[i]
        return None

    if want == "tx":
        for i,n in enumerate(low):
            if n in ("tx_ms","fabric_ms"):
                return f[i]
        for i,n in enumerate(low):
            if "tx" in n and "ms" in n:
                return f[i]
        return None

    if want == "total":
        for i,n in enumerate(low):
            if n in ("total_ms","e2e_ms"):
                return f[i]
        for i,n in enumerate(low):
            if "total" in n and "ms" in n:
                return f[i]
        return None

    return None

chosen_csv = {}
per_round = {}

all_byz_f1, all_byz_fpr = [], []
all_h_f1, all_h_fpr = [], []
all_ipfs, all_tx, all_total = [], [], []

for r in range(1,6):
    pat = f"p12_scaling_round{r:02d}_clients_*.csv"
    f = pick_latest(pat)
    if f is None:
        raise SystemExit(f"ERROR: missing csv for round {r} in {sum_dir}")
    chosen_csv[str(r)] = str(f)

    rows = list(csv.DictReader(f.open()))
    if not rows:
        raise SystemExit(f"ERROR: empty csv {f}")

    fields = rows[0].keys()
    k_client = find_col(fields, "client")
    k_f1 = find_col(fields, "f1")
    k_fpr = find_col(fields, "fpr")
    k_ipfs = find_col(fields, "ipfs")
    k_tx = find_col(fields, "tx")
    k_total = find_col(fields, "total")

    byz_f1, byz_fpr = [], []
    h_f1, h_fpr = [], []
    ipfs_vals, tx_vals, total_vals = [], [], []

    for row in rows:
        cid = (row.get(k_client,"") or "").strip()
        f1 = safe_float(row.get(k_f1)) if k_f1 else None
        fpr = safe_float(row.get(k_fpr)) if k_fpr else None
        ipfs = safe_float(row.get(k_ipfs)) if k_ipfs else None
        tx = safe_float(row.get(k_tx)) if k_tx else None
        tot = safe_float(row.get(k_total)) if k_total else None

        if cid in byz_set:
            if f1 is not None: byz_f1.append(f1)
            if fpr is not None: byz_fpr.append(fpr)
        else:
            if f1 is not None: h_f1.append(f1)
            if fpr is not None: h_fpr.append(fpr)

        if ipfs is not None: ipfs_vals.append(ipfs)
        if tx is not None: tx_vals.append(tx)
        if tot is not None: total_vals.append(tot)

    all_byz_f1 += byz_f1
    all_byz_fpr += byz_fpr
    all_h_f1 += h_f1
    all_h_fpr += h_fpr
    all_ipfs += ipfs_vals
    all_tx += tx_vals
    all_total += total_vals

    per_round[str(r)] = {
        "round": r,
        "n_rows": len(rows),
        "n_byz": len(byz_f1),
        "n_honest": len(h_f1),
        "byz": {"f1": stats(byz_f1), "fpr": stats(byz_fpr)},
        "honest": {"f1": stats(h_f1), "fpr": stats(h_fpr)},
        "ipfs_ms": stats(ipfs_vals),
        "tx_ms": stats(tx_vals),
        "total_ms": stats(total_vals),
        "csv": str(f)
    }

pooled = {
    "n_points": len(all_byz_f1) + len(all_h_f1),
    "byz": {"f1": stats(all_byz_f1), "fpr": stats(all_byz_fpr)},
    "honest": {"f1": stats(all_h_f1), "fpr": stats(all_h_fpr)},
    "ipfs_ms": stats(all_ipfs),
    "tx_ms": stats(all_tx),
    "total_ms": stats(all_total),
}

with out_table.open("w", newline="") as w:
    cols = [
        "round","n_total","n_byz","n_honest",
        "byz_f1_avg","byz_fpr_avg","honest_f1_avg","honest_fpr_avg",
        "ipfs_p50","ipfs_p95","tx_p50","tx_p95","total_p50","total_p95",
        "csv_file"
    ]
    cw = csv.DictWriter(w, fieldnames=cols)
    cw.writeheader()
    for r in range(1,6):
        pr = per_round[str(r)]
        bf1 = (pr["byz"]["f1"] or {}).get("avg")
        bfpr = (pr["byz"]["fpr"] or {}).get("avg")
        hf1 = (pr["honest"]["f1"] or {}).get("avg")
        hfpr = (pr["honest"]["fpr"] or {}).get("avg")
        ip50 = (pr["ipfs_ms"] or {}).get("p50")
        ip95 = (pr["ipfs_ms"] or {}).get("p95")
        tx50 = (pr["tx_ms"] or {}).get("p50")
        tx95 = (pr["tx_ms"] or {}).get("p95")
        tt50 = (pr["total_ms"] or {}).get("p50")
        tt95 = (pr["total_ms"] or {}).get("p95")
        cw.writerow({
            "round": r,
            "n_total": pr["n_rows"],
            "n_byz": pr["n_byz"],
            "n_honest": pr["n_honest"],
            "byz_f1_avg": bf1,
            "byz_fpr_avg": bfpr,
            "honest_f1_avg": hf1,
            "honest_fpr_avg": hfpr,
            "ipfs_p50": ip50,
            "ipfs_p95": ip95,
            "tx_p50": tx50,
            "tx_p95": tx95,
            "total_p50": tt50,
            "total_p95": tt95,
            "csv_file": pr["csv"],
        })

out = {
    "scenario": "scaling",
    "rounds": [1,2,3,4,5],
    "byz_clients": sorted(byz_set),
    "chosen_csv_per_round": chosen_csv,
    "per_round": per_round,
    "pooled_over_5rounds": pooled,
    "files": {
        "table_csv": str(out_table),
        "clean_json": str(out_json)
    }
}
out_json.write_text(json.dumps(out, indent=2))

print("OK")
print("TABLE_CSV=", out_table)
print("CLEAN_JSON=", out_json)
print("POOLED_BYZ_F1_AVG=", (pooled["byz"]["f1"] or {}).get("avg"))
print("POOLED_HONEST_F1_AVG=", (pooled["honest"]["f1"] or {}).get("avg"))
PY
