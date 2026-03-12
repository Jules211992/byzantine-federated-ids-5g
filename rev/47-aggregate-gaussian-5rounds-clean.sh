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
import sys, csv, json, math, glob, os, re
from pathlib import Path

sum_dir = Path(sys.argv[1])
out_table = Path(sys.argv[2])
out_json = Path(sys.argv[3])
byz = set(sys.argv[4].split())

def tofloat(x):
    try: return float(x)
    except: return None

def stats(vals):
    vals=[v for v in vals if v is not None]
    if not vals: return None
    avg=sum(vals)/len(vals)
    var=sum((v-avg)**2 for v in vals)/len(vals)
    s=sorted(vals)
    def pct(p):
        k=(len(s)-1)*(p/100.0)
        f=math.floor(k); c=math.ceil(k)
        if f==c: return s[int(k)]
        return s[f]*(c-k)+s[c]*(k-f)
    return {"avg":avg,"std":math.sqrt(var),"min":min(vals),"max":max(vals),"p50":pct(50),"p95":pct(95),"p99":pct(99),"n":len(vals)}

def ok_count(p):
    try:
        with open(p,newline="") as f:
            rd=csv.DictReader(f)
            return sum(1 for r in rd if str(r.get("rc",""))=="0")
    except:
        return -1

picked={}
for r in range(1,6):
    pat=str(sum_dir / f"p13_gaussian_round{r:02d}_clients_*.csv")
    cands=sorted(glob.glob(pat), reverse=True)
    if not cands:
        raise SystemExit(f"ERROR: missing csv for round {r} in {sum_dir}")
    best=None
    best_ok=-1
    for p in cands:
        ok=ok_count(p)
        if ok>best_ok:
            best_ok=ok; best=p
        if ok==20:
            best=p; best_ok=ok
            break
    if best_ok<20:
        raise SystemExit(f"ERROR: round {r} has ok={best_ok}/20 (need 20). best={best}")
    picked[r]=best

rows=[]
for r in range(1,6):
    with open(picked[r], newline="") as f:
        rd=csv.DictReader(f)
        for row in rd:
            row["round"]=r
            rows.append(row)

byz_f1=[tofloat(r.get("f1","")) for r in rows if r.get("client_id","") in byz]
hon_f1=[tofloat(r.get("f1","")) for r in rows if r.get("client_id","") and r.get("client_id","") not in byz]
byz_fpr=[tofloat(r.get("fpr","")) for r in rows if r.get("client_id","") in byz]
hon_fpr=[tofloat(r.get("fpr","")) for r in rows if r.get("client_id","") and r.get("client_id","") not in byz]

ipfs=[tofloat(r.get("ipfs_ms","")) for r in rows]
tx=[tofloat(r.get("tx_ms","")) for r in rows]
tot=[tofloat(r.get("total_ms","")) for r in rows]

pooled={
  "n_points": len(rows),
  "pooled_byz": {"f1": stats(byz_f1), "fpr": stats(byz_fpr)},
  "pooled_honest": {"f1": stats(hon_f1), "fpr": stats(hon_fpr)},
  "ipfs_ms": stats(ipfs),
  "tx_ms": stats(tx),
  "total_ms": stats(tot),
}

with open(out_table,"w",newline="") as f:
    wr=csv.writer(f)
    wr.writerow(["round","client_id","ip","fabric_round","rc","cid","f1","fpr","ipfs_ms","tx_ms","total_ms"])
    for r in rows:
        wr.writerow([r.get("round",""),r.get("client_id",""),r.get("ip",""),r.get("fabric_round",""),r.get("rc",""),
                     r.get("cid",""),r.get("f1",""),r.get("fpr",""),r.get("ipfs_ms",""),r.get("tx_ms",""),r.get("total_ms","")])

out={
  "rounds":[1,2,3,4,5],
  "chosen_csv_per_round": picked,
  "pooled_over_5rounds": pooled,
  "byz_clients": sorted(list(byz)),
  "files":{"table_csv": str(out_table)}
}
json.dump(out, open(out_json,"w"), indent=2)

print("OK")
print("TABLE_CSV=", out_table)
print("CLEAN_JSON=", out_json)
print("POOLED_BYZ_F1_AVG=", out["pooled_over_5rounds"]["pooled_byz"]["f1"]["avg"])
print("POOLED_HONEST_F1_AVG=", out["pooled_over_5rounds"]["pooled_honest"]["f1"]["avg"])
PY
