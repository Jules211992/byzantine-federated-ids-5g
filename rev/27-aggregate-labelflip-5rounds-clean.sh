#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p8_labelflip_5rounds_table_${TS}.csv"
OUT_JSON="$SUM_DIR/p8_labelflip_5rounds_clean_${TS}.json"

python3 - "$SUM_DIR" "$OUT_TABLE" "$OUT_JSON" "$BYZ_CLIENTS" <<'PY'
import sys, csv, json, re, math
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_table = Path(sys.argv[2])
out_json = Path(sys.argv[3])
byz_list = sys.argv[4].split()

def norm_ts(s: str) -> str:
    return re.sub(r"[^0-9]", "", s)

def pcts(vals, p):
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
    if not vals:
        return None
    n = len(vals)
    avg = sum(vals)/n
    var = sum((x-avg)**2 for x in vals)/n
    return {
        "avg": float(avg),
        "std": float(math.sqrt(var)),
        "min": float(min(vals)),
        "max": float(max(vals)),
        "p50": float(pcts(vals,50)),
        "p95": float(pcts(vals,95)),
        "p99": float(pcts(vals,99)),
        "n": int(n),
    }

def pick_latest_round_csv(r):
    pat = re.compile(rf"^p8_labelflip_round{r:02d}_clients_([0-9]{{8}}_[0-9]{{6}}|[0-9]{{14}})\.csv$")
    best = None
    for p in sum_dir.iterdir():
        m = pat.match(p.name)
        if not m:
            continue
        ts = norm_ts(m.group(1))
        if best is None or ts > best[0]:
            best = (ts, p)
    return best[1] if best else None

picked = {}
for r in range(1,6):
    p = pick_latest_round_csv(r)
    if not p:
        print(f"ERROR: missing csv for round {r} in {sum_dir}")
        print("HINT: existing p8_labelflip_round??_clients_* files:")
        for q in sorted(sum_dir.glob("p8_labelflip_round??_clients_*.csv"))[:30]:
            print(" -", q.name)
        sys.exit(1)
    picked[r] = p

def detect_cols(header):
    h = [x.strip() for x in header]
    low = [x.lower() for x in h]
    def find_one(cands):
        for c in cands:
            if c in low:
                return h[low.index(c)]
        return None
    c_client = find_one(["client_id","client","cid"])
    c_f1 = find_one(["f1","f1_score"])
    c_fpr = find_one(["fpr"])
    c_ipfs = find_one(["ipfs_ms","ipfs_add_ms","ipfs"])
    c_tx = find_one(["tx_ms","fabric_ms","tx"])
    c_total = find_one(["total_ms","total"])
    return c_client, c_f1, c_fpr, c_ipfs, c_tx, c_total

rows_all = []
per_round = []

for r in range(1,6):
    path = picked[r]
    with path.open() as f:
        rd = csv.DictReader(f)
        header = rd.fieldnames or []
        c_client, c_f1, c_fpr, c_ipfs, c_tx, c_total = detect_cols(header)
        if not c_client or not c_f1 or not c_fpr:
            print("ERROR: csv missing required columns:", path)
            print("HEADER:", header)
            sys.exit(1)

        byz_f1=[]; byz_fpr=[]; hon_f1=[]; hon_fpr=[]
        byz_ipfs=[]; byz_tx=[]; byz_total=[]
        hon_ipfs=[]; hon_tx=[]; hon_total=[]
        all_ipfs=[]; all_tx=[]; all_total=[]

        for row in rd:
            cid = (row.get(c_client,"") or "").strip()
            if not cid:
                continue
            try:
                f1 = float(row.get(c_f1,""))
                fpr = float(row.get(c_fpr,""))
            except:
                continue

            ipfs = tx = total = None
            try:
                if c_ipfs and row.get(c_ipfs,"") not in (None,""):
                    ipfs = float(row.get(c_ipfs,""))
                if c_tx and row.get(c_tx,"") not in (None,""):
                    tx = float(row.get(c_tx,""))
                if c_total and row.get(c_total,"") not in (None,""):
                    total = float(row.get(c_total,""))
            except:
                ipfs = tx = total = None

            is_byz = cid in byz_list
            rows_all.append({
                "round": r,
                "client_id": cid,
                "is_byz": int(is_byz),
                "f1": f1,
                "fpr": fpr,
                "ipfs_ms": ipfs,
                "tx_ms": tx,
                "total_ms": total,
                "src": str(path),
            })

            if ipfs is not None: all_ipfs.append(ipfs)
            if tx is not None: all_tx.append(tx)
            if total is not None: all_total.append(total)

            if is_byz:
                byz_f1.append(f1); byz_fpr.append(fpr)
                if ipfs is not None: byz_ipfs.append(ipfs)
                if tx is not None: byz_tx.append(tx)
                if total is not None: byz_total.append(total)
            else:
                hon_f1.append(f1); hon_fpr.append(fpr)
                if ipfs is not None: hon_ipfs.append(ipfs)
                if tx is not None: hon_tx.append(tx)
                if total is not None: hon_total.append(total)

        per_round.append({
            "round": r,
            "byz": {"f1": stats(byz_f1), "fpr": stats(byz_fpr), "ipfs_ms": stats(byz_ipfs), "tx_ms": stats(byz_tx), "total_ms": stats(byz_total)},
            "honest": {"f1": stats(hon_f1), "fpr": stats(hon_fpr), "ipfs_ms": stats(hon_ipfs), "tx_ms": stats(hon_tx), "total_ms": stats(hon_total)},
            "all": {"ipfs_ms": stats(all_ipfs), "tx_ms": stats(all_tx), "total_ms": stats(all_total)},
            "inputs": {"clients_csv": str(path)},
        })

def pooled_from(rows, filt):
    f1=[]; fpr=[]; ipfs=[]; tx=[]; total=[]
    for r in rows:
        if not filt(r):
            continue
        f1.append(r["f1"]); fpr.append(r["fpr"])
        if r["ipfs_ms"] is not None: ipfs.append(r["ipfs_ms"])
        if r["tx_ms"] is not None: tx.append(r["tx_ms"])
        if r["total_ms"] is not None: total.append(r["total_ms"])
    return {"f1": stats(f1), "fpr": stats(fpr), "ipfs_ms": stats(ipfs), "tx_ms": stats(tx), "total_ms": stats(total), "n_points": len(f1)}

pooled = {
    "byz_clients": byz_list,
    "picked_round_csv": {str(k): str(v) for k,v in picked.items()},
    "per_round": per_round,
    "pooled_all": pooled_from(rows_all, lambda r: True),
    "pooled_byz": pooled_from(rows_all, lambda r: r["is_byz"]==1),
    "pooled_honest": pooled_from(rows_all, lambda r: r["is_byz"]==0),
}

with out_table.open("w", newline="") as f:
    wr = csv.writer(f)
    wr.writerow(["round","group","f1_avg","f1_min","f1_max","fpr_avg","fpr_min","fpr_max","ipfs_p50","tx_p50","total_p50","n"])
    for pr in per_round:
        r = pr["round"]
        for grp in ["byz","honest"]:
            s_f1 = pr[grp]["f1"] or {}
            s_fpr = pr[grp]["fpr"] or {}
            s_ip = pr[grp]["ipfs_ms"] or {}
            s_tx = pr[grp]["tx_ms"] or {}
            s_tt = pr[grp]["total_ms"] or {}
            wr.writerow([
                r, grp,
                s_f1.get("avg"), s_f1.get("min"), s_f1.get("max"),
                s_fpr.get("avg"), s_fpr.get("min"), s_fpr.get("max"),
                s_ip.get("p50"), s_tx.get("p50"), s_tt.get("p50"),
                s_f1.get("n"),
            ])

out_json.write_text(json.dumps(pooled, indent=2))
print("OK")
print("TABLE_CSV=", str(out_table))
print("CLEAN_JSON=", str(out_json))
print("POOLED_BYZ_F1_AVG=", pooled["pooled_byz"]["f1"]["avg"] if pooled["pooled_byz"]["f1"] else None)
print("POOLED_HONEST_F1_AVG=", pooled["pooled_honest"]["f1"]["avg"] if pooled["pooled_honest"]["f1"] else None)
PY
