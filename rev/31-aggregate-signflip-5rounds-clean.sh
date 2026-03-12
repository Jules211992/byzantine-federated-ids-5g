#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p10_signflip_5rounds_table_${TS}.csv"
OUT_JSON="$SUM_DIR/p10_signflip_5rounds_clean_${TS}.json"

python3 - "$SUM_DIR" "$OUT_TABLE" "$OUT_JSON" "$BYZ_CLIENTS" <<'PY'
import sys, csv, json, re, math
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_table = Path(sys.argv[2])
out_json = Path(sys.argv[3])
byz_set = set(sys.argv[4].split())

def pcts(vals, p):
    if not vals:
        return None
    s = sorted(vals)
    k = (len(s)-1) * (p/100.0)
    f = int(math.floor(k))
    c = int(math.ceil(k))
    if f == c:
        return s[f]
    return s[f] + (k - f) * (s[c] - s[f])

def stats(vals):
    if not vals:
        return None
    n = len(vals)
    avg = sum(vals)/n
    var = sum((x-avg)**2 for x in vals)/n
    return {
        "avg": avg,
        "std": var**0.5,
        "min": min(vals),
        "max": max(vals),
        "p50": pcts(vals,50),
        "p95": pcts(vals,95),
        "p99": pcts(vals,99),
        "n": n
    }

pat = re.compile(r"^p8_labelflip_round(0[1-5])_clients_.*\.csv$")
cands = sorted([p for p in sum_dir.iterdir() if pat.match(p.name)], key=lambda p: p.stat().st_mtime)

per_round = {}
rows_all = []

for r in range(1,6):
    rr=f"{r:02d}"
    rr_files=[p for p in cands if f"round{rr}_" in p.name]
    if not rr_files:
        raise SystemExit(f"ERROR: missing csv for round {r} in {sum_dir}")
    p = rr_files[-1]
    with p.open() as f:
        dr = csv.DictReader(f)
        rows = list(dr)

    f1_byz=[]; f1_h=[]; fpr_byz=[]; fpr_h=[]
    ipfs=[]; tx=[]; total=[]
    for row in rows:
        cid = row.get("client_id","")
        def getf(k):
            v=row.get(k,"")
            try: return float(v)
            except: return None
        f1=getf("f1"); fpr=getf("fpr")
        ip=getf("ipfs_ms"); txm=getf("tx_ms"); tm=getf("total_ms")
        if ip is not None: ipfs.append(ip)
        if txm is not None: tx.append(txm)
        if tm is not None: total.append(tm)

        if cid in byz_set:
            if f1 is not None: f1_byz.append(f1)
            if fpr is not None: fpr_byz.append(fpr)
        else:
            if f1 is not None: f1_h.append(f1)
            if fpr is not None: fpr_h.append(fpr)

        rows_all.append(row)

    per_round[r] = {
        "csv": str(p),
        "f1_byz": stats(f1_byz),
        "f1_honest": stats(f1_h),
        "fpr_byz": stats(fpr_byz),
        "fpr_honest": stats(fpr_h),
        "ipfs_ms": stats(ipfs),
        "tx_ms": stats(tx),
        "total_ms": stats(total),
    }

pooled = {
    "pooled_byz": {
        "f1": stats([float(r["f1"]) for r in rows_all if r.get("client_id","") in byz_set and r.get("f1","")!=""]),
        "fpr": stats([float(r["fpr"]) for r in rows_all if r.get("client_id","") in byz_set and r.get("fpr","")!=""]),
    },
    "pooled_honest": {
        "f1": stats([float(r["f1"]) for r in rows_all if r.get("client_id","") not in byz_set and r.get("f1","")!=""]),
        "fpr": stats([float(r["fpr"]) for r in rows_all if r.get("client_id","") not in byz_set and r.get("fpr","")!=""]),
    }
}

with out_table.open("w", newline="") as f:
    w=csv.writer(f)
    w.writerow(["round","group","f1_avg","f1_std","fpr_avg","fpr_std"])
    for r in range(1,6):
        pr=per_round[r]
        for grp in ["byz","honest"]:
            f1=pr[f"f1_{grp}"]; fpr=pr[f"fpr_{grp}"]
            w.writerow([r, grp,
                        None if not f1 else f1["avg"],
                        None if not f1 else f1["std"],
                        None if not fpr else fpr["avg"],
                        None if not fpr else fpr["std"]])

out = {
    "attack": "signflip",
    "byz_clients": sorted(byz_set),
    "per_round": per_round,
    "pooled_over_5rounds": pooled,
    "files": {
        "table_csv": str(out_table),
        "clean_json": str(out_json),
    }
}
out_json.write_text(json.dumps(out, indent=2))

print("OK")
print("TABLE_CSV=", out_table)
print("CLEAN_JSON=", out_json)
print("POOLED_BYZ_F1_AVG=", pooled["pooled_byz"]["f1"]["avg"])
print("POOLED_HONEST_F1_AVG=", pooled["pooled_honest"]["f1"]["avg"])
PY
