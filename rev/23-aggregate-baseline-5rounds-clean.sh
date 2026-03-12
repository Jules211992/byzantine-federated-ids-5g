#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé"
  exit 1
fi

SUM_DIR="$RUN_DIR/summary"
if [ ! -d "$SUM_DIR" ]; then
  echo "ERROR: summary dir introuvable: $SUM_DIR"
  exit 1
fi

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_TABLE="$SUM_DIR/p7_baseline_5rounds_table_${TS}.csv"
OUT_JSON="$SUM_DIR/p7_baseline_5rounds_clean_${TS}.json"

python3 - "$SUM_DIR" "$OUT_TABLE" "$OUT_JSON" <<'PY'
import sys, glob, os, csv, json, math

sum_dir = sys.argv[1]
out_table = sys.argv[2]
out_json = sys.argv[3]

def newest(pattern):
  files = glob.glob(os.path.join(sum_dir, pattern))
  if not files:
    return None
  files.sort(key=lambda p: os.path.getmtime(p))
  return files[-1]

def pctl(vals, p):
  vals=[v for v in vals if v is not None]
  if not vals:
    return None
  xs=sorted(vals)
  if len(xs)==1:
    return float(xs[0])
  k=(len(xs)-1)*(p/100.0)
  f=int(k)
  c=min(f+1,len(xs)-1)
  if f==c:
    return float(xs[f])
  d=k-f
  return float(xs[f]+(xs[c]-xs[f])*d)

def mean(vals):
  vals=[v for v in vals if v is not None]
  if not vals:
    return None
  return sum(vals)/len(vals)

def std(vals):
  vals=[v for v in vals if v is not None]
  if len(vals) < 2:
    return 0.0 if vals else None
  m = sum(vals)/len(vals)
  return math.sqrt(sum((x-m)**2 for x in vals)/(len(vals)-1))

chosen = {}
for r in range(1,6):
  pat = f"p7_baseline_round{r:02d}_clients_*.csv"
  f = newest(pat)
  if not f:
    raise SystemExit(f"ERROR: aucun fichier trouvé pour round {r:02d} pattern={pat}")
  chosen[r] = f

per_round = []
all_ipfs=[]
all_tx=[]
all_total=[]
all_f1=[]
all_fpr=[]

for r in range(1,6):
  f = chosen[r]
  rows=[]
  with open(f, newline="") as fh:
    rd = csv.DictReader(fh)
    for row in rd:
      def tofloat(x):
        if x is None: return None
        x=str(x).strip()
        if x=="" or x.lower()=="none": return None
        try: return float(x)
        except: return None
      rows.append({
        "f1": tofloat(row.get("f1")),
        "fpr": tofloat(row.get("fpr")),
        "ipfs_ms": tofloat(row.get("ipfs_ms")),
        "tx_ms": tofloat(row.get("tx_ms")),
        "total_ms": tofloat(row.get("total_ms")),
      })

  f1=[x["f1"] for x in rows]
  fpr=[x["fpr"] for x in rows]
  ipfs=[x["ipfs_ms"] for x in rows]
  tx=[x["tx_ms"] for x in rows]
  tot=[x["total_ms"] for x in rows]

  all_f1 += [v for v in f1 if v is not None]
  all_fpr += [v for v in fpr if v is not None]
  all_ipfs += [v for v in ipfs if v is not None]
  all_tx += [v for v in tx if v is not None]
  all_total += [v for v in tot if v is not None]

  per_round.append({
    "round": r,
    "csv": f,
    "f1_avg": mean(f1),
    "f1_min": min([v for v in f1 if v is not None]) if any(v is not None for v in f1) else None,
    "f1_max": max([v for v in f1 if v is not None]) if any(v is not None for v in f1) else None,
    "fpr_avg": mean(fpr),
    "fpr_min": min([v for v in fpr if v is not None]) if any(v is not None for v in fpr) else None,
    "fpr_max": max([v for v in fpr if v is not None]) if any(v is not None for v in fpr) else None,
    "ipfs_p50": pctl(ipfs,50),
    "ipfs_p95": pctl(ipfs,95),
    "ipfs_p99": pctl(ipfs,99),
    "tx_p50": pctl(tx,50),
    "tx_p95": pctl(tx,95),
    "tx_p99": pctl(tx,99),
    "total_p50": pctl(tot,50),
    "total_p95": pctl(tot,95),
    "total_p99": pctl(tot,99),
  })

with open(out_table,"w",newline="") as f:
  cols=["round","f1_avg","f1_min","f1_max","fpr_avg","fpr_min","fpr_max",
        "ipfs_p50","ipfs_p95","ipfs_p99","tx_p50","tx_p95","tx_p99","total_p50","total_p95","total_p99","csv"]
  w=csv.DictWriter(f, fieldnames=cols)
  w.writeheader()
  for r in per_round:
    w.writerow({k:r.get(k) for k in cols})

clean = {
  "rounds": [1,2,3,4,5],
  "chosen_csv_per_round": {str(k): v for k,v in chosen.items()},
  "per_round": per_round,
  "pooled_over_5rounds": {
    "n_points": len(all_total),
    "f1": {"avg": mean(all_f1), "std": std(all_f1), "min": (min(all_f1) if all_f1 else None), "max": (max(all_f1) if all_f1 else None)},
    "fpr": {"avg": mean(all_fpr), "std": std(all_fpr), "min": (min(all_fpr) if all_fpr else None), "max": (max(all_fpr) if all_fpr else None)},
    "ipfs_ms": {"p50": pctl(all_ipfs,50), "p95": pctl(all_ipfs,95), "p99": pctl(all_ipfs,99), "min": (min(all_ipfs) if all_ipfs else None), "max": (max(all_ipfs) if all_ipfs else None)},
    "tx_ms": {"p50": pctl(all_tx,50), "p95": pctl(all_tx,95), "p99": pctl(all_tx,99), "min": (min(all_tx) if all_tx else None), "max": (max(all_tx) if all_tx else None)},
    "total_ms": {"p50": pctl(all_total,50), "p95": pctl(all_total,95), "p99": pctl(all_total,99), "min": (min(all_total) if all_total else None), "max": (max(all_total) if all_total else None)}
  },
  "files": {"table_csv": out_table, "clean_json": out_json}
}

with open(out_json,"w") as f:
  json.dump(clean,f,indent=2)

print("OK")
print("TABLE_CSV=", out_table)
print("CLEAN_JSON=", out_json)
print("POOLED=", json.dumps(clean["pooled_over_5rounds"], indent=2))
PY
