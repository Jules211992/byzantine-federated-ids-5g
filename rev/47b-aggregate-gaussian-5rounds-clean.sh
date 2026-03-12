#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

SUM_DIR="$RUN_DIR/summary"
[ -d "$SUM_DIR" ] || { echo "ERROR: summary dir introuvable: $SUM_DIR"; exit 1; }

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p13_gaussian_5rounds_table_${TS}.csv"
OUT_JSON="$SUM_DIR/p13_gaussian_5rounds_clean_${TS}.json"

python3 - "$SUM_DIR" "$OUT_TABLE" "$OUT_JSON" "$BYZ_CLIENTS" <<'PY'
import sys, csv, json, re, math
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_table = Path(sys.argv[2])
out_json = Path(sys.argv[3])
byz = set(sys.argv[4].split())

def pct(vals, p):
    vals=[v for v in vals if v is not None]
    if not vals:
        return None
    s=sorted(vals)
    k=(len(s)-1)*(p/100.0)
    f=math.floor(k); c=math.ceil(k)
    if f==c:
        return s[int(k)]
    return s[f]*(c-k)+s[c]*(k-f)

def stats(vals):
    vals=[v for v in vals if v is not None]
    if not vals:
        return None
    avg=sum(vals)/len(vals)
    var=sum((v-avg)**2 for v in vals)/len(vals)
    return {"avg":avg,"std":math.sqrt(var),"min":min(vals),"max":max(vals),"p50":pct(vals,50),"p95":pct(vals,95),"p99":pct(vals,99),"n":len(vals)}

def tofloat(x):
    try:
        if x is None: return None
        x=str(x).strip()
        if x=="": return None
        return float(x)
    except:
        return None

def pick_latest(round_num: int):
    patt = re.compile(rf"p13_gaussian_round{round_num:02d}_clients_(\d+)\.csv$")
    best=None
    best_ts=-1
    for p in sum_dir.glob(f"p13_gaussian_round{round_num:02d}_clients_*.csv"):
        m=patt.search(p.name)
        if not m:
            continue
        ts=int(m.group(1))
        if ts>best_ts:
            best_ts=ts
            best=p
    return best

chosen={}
missing=[]
for r in range(1,6):
    p=pick_latest(r)
    if p is None:
        missing.append(r)
    else:
        chosen[r]=str(p)

if missing:
    print("ERROR: missing csv for rounds:", missing)
    found=sorted([p.name for p in sum_dir.glob("p13_gaussian_round*_clients_*.csv")])
    print("FOUND_FILES:")
    for f in found[:200]:
        print(" ", f)
    raise SystemExit(1)

per_round={}
pool_byz_f1=[]; pool_hon_f1=[]
pool_byz_fpr=[]; pool_hon_fpr=[]
pool_ipfs=[]; pool_tx=[]; pool_total=[]

for r in range(1,6):
    rows=[]
    with open(chosen[r], newline="") as f:
        rd=csv.DictReader(f)
        for row in rd:
            rows.append(row)

    ok=[rw for rw in rows if str(rw.get("rc","")).strip()=="0"]

    byz_rows=[rw for rw in ok if rw.get("client_id","") in byz]
    hon_rows=[rw for rw in ok if rw.get("client_id","") and rw.get("client_id","") not in byz]

    byz_f1=[tofloat(rw.get("f1","")) for rw in byz_rows]
    hon_f1=[tofloat(rw.get("f1","")) for rw in hon_rows]
    byz_fpr=[tofloat(rw.get("fpr","")) for rw in byz_rows]
    hon_fpr=[tofloat(rw.get("fpr","")) for rw in hon_rows]

    ipfs=[tofloat(rw.get("ipfs_ms","")) for rw in ok]
    tx=[tofloat(rw.get("tx_ms","")) for rw in ok]
    total=[tofloat(rw.get("total_ms","")) for rw in ok]

    per_round[r]={
        "csv": chosen[r],
        "n_ok": len(ok),
        "byz": {"f1": stats(byz_f1), "fpr": stats(byz_fpr)},
        "honest": {"f1": stats(hon_f1), "fpr": stats(hon_fpr)},
        "ipfs_ms": stats(ipfs),
        "tx_ms": stats(tx),
        "total_ms": stats(total),
    }

    pool_byz_f1 += [v for v in byz_f1 if v is not None]
    pool_hon_f1 += [v for v in hon_f1 if v is not None]
    pool_byz_fpr += [v for v in byz_fpr if v is not None]
    pool_hon_fpr += [v for v in hon_fpr if v is not None]
    pool_ipfs += [v for v in ipfs if v is not None]
    pool_tx += [v for v in tx if v is not None]
    pool_total += [v for v in total if v is not None]

pooled={
    "byz": {"f1": stats(pool_byz_f1), "fpr": stats(pool_byz_fpr)},
    "honest": {"f1": stats(pool_hon_f1), "fpr": stats(pool_hon_fpr)},
    "ipfs_ms": stats(pool_ipfs),
    "tx_ms": stats(pool_tx),
    "total_ms": stats(pool_total),
}

out={
    "rounds":[1,2,3,4,5],
    "byz_clients": sorted(list(byz)),
    "chosen_csv_per_round": chosen,
    "per_round": per_round,
    "pooled_over_5rounds": pooled,
    "files": {"table_csv": str(out_table), "clean_json": str(out_json)}
}

json.dump(out, open(out_json,"w"), indent=2)

with open(out_table,"w", newline="") as f:
    w=csv.writer(f)
    w.writerow(["round","byz_f1_avg","byz_fpr_avg","honest_f1_avg","honest_fpr_avg","ipfs_p50","ipfs_p95","tx_p50","tx_p95","total_p50","total_p95"])
    for r in range(1,6):
        pr=per_round[r]
        b1=pr["byz"]["f1"]["avg"] if pr["byz"]["f1"] else ""
        b2=pr["byz"]["fpr"]["avg"] if pr["byz"]["fpr"] else ""
        h1=pr["honest"]["f1"]["avg"] if pr["honest"]["f1"] else ""
        h2=pr["honest"]["fpr"]["avg"] if pr["honest"]["fpr"] else ""
        ip50=pr["ipfs_ms"]["p50"] if pr["ipfs_ms"] else ""
        ip95=pr["ipfs_ms"]["p95"] if pr["ipfs_ms"] else ""
        tx50=pr["tx_ms"]["p50"] if pr["tx_ms"] else ""
        tx95=pr["tx_ms"]["p95"] if pr["tx_ms"] else ""
        t50=pr["total_ms"]["p50"] if pr["total_ms"] else ""
        t95=pr["total_ms"]["p95"] if pr["total_ms"] else ""
        w.writerow([r,b1,b2,h1,h2,ip50,ip95,tx50,tx95,t50,t95])

print("OK")
print("TABLE_CSV=", out_table)
print("CLEAN_JSON=", out_json)
print("POOLED_BYZ_F1_AVG=", pooled["byz"]["f1"]["avg"] if pooled["byz"]["f1"] else None)
print("POOLED_HONEST_F1_AVG=", pooled["honest"]["f1"]["avg"] if pooled["honest"]["f1"] else None)
PY
