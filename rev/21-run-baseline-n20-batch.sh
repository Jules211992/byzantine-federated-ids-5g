#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

MAP="$RUN_DIR/config/edges_map_20.txt"
if [ ! -f "$MAP" ]; then
  echo "ERROR: map introuvable: $MAP"
  exit 1
fi

SUM_DIR="$RUN_DIR/summary"
mkdir -p "$SUM_DIR"

START_ROUND="${START_ROUND:-1}"
END_ROUND="${END_ROUND:-5}"
BASE_FABRIC="${BASE_FABRIC:-63000}"

run_one_round () {
  local r="$1"
  local start_fabric=$((BASE_FABRIC + (r - 1) * 1000))

  echo
  echo "=============================="
  echo "RUN baseline N=20 round=$r START_FABRIC=$start_fabric"
  echo "=============================="

  START_FABRIC="$start_fabric" ROUND="$r" bash ~/byz-fed-ids-5g/rev/16b-run-p7-n20-baseline-smoke-v2.sh
}

summarize_round () {
  local r="$1"
  local r2
  r2=$(printf "%02d" "$r")
  local OUT_DIR="$RUN_DIR/p7_baseline/round${r2}/client_logs"

  if [ ! -d "$OUT_DIR" ]; then
    echo "ERROR: client_logs introuvable: $OUT_DIR"
    exit 1
  fi

  local TS
  TS=$(date -u +%Y%m%d_%H%M%S)

  local OUT_CSV="$SUM_DIR/p7_baseline_round${r2}_clients_${TS}.csv"
  local OUT_JSON="$SUM_DIR/p7_baseline_round${r2}_latency_pct_${TS}.json"

  python3 - "$MAP" "$OUT_DIR" "$r" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, re, csv, json
from pathlib import Path

map_path = Path(sys.argv[1])
out_dir  = Path(sys.argv[2])
round_num = int(sys.argv[3])
out_csv  = Path(sys.argv[4])
out_json = Path(sys.argv[5])

m = {}
for line in map_path.read_text().splitlines():
  line=line.strip()
  if not line:
    continue
  cid, ip = line.split()
  m[cid]=ip

def pctl(vals, p):
  if not vals:
    return None
  xs = sorted(vals)
  if len(xs) == 1:
    return float(xs[0])
  k = (len(xs)-1) * (p/100.0)
  f = int(k)
  c = min(f+1, len(xs)-1)
  if f == c:
    return float(xs[f])
  d = k - f
  return float(xs[f] + (xs[c]-xs[f]) * d)

rx_runfl = re.compile(r'F1=([0-9.]+)\s+FPR=([0-9.]+)')
rx_fabric = re.compile(r'ipfs=([0-9.]+)ms\s+tx=([0-9.]+)ms\s+total=([0-9.]+)ms')
rx_fabric_round = re.compile(r'round=([0-9]+)')

rows = []
ipfs_vals=[]
tx_vals=[]
total_vals=[]
f1_vals=[]
fpr_vals=[]

for cid, ip in sorted(m.items(), key=lambda x: x[0]):
  runfl = out_dir / f"{cid}.runfl.out"
  fab   = out_dir / f"{cid}.fl_fabric.out"

  f1 = None
  fpr = None
  if runfl.exists():
    t = runfl.read_text(errors="ignore")
    mm = rx_runfl.search(t)
    if mm:
      f1 = float(mm.group(1))
      fpr = float(mm.group(2))

  ipfs_ms = None
  tx_ms = None
  total_ms = None
  fabric_round = None
  if fab.exists():
    t = fab.read_text(errors="ignore")
    mm = rx_fabric.search(t)
    if mm:
      ipfs_ms = float(mm.group(1))
      tx_ms = float(mm.group(2))
      total_ms = float(mm.group(3))
    mmr = rx_fabric_round.search(t)
    if mmr:
      fabric_round = int(mmr.group(1))

  rows.append({
    "round": round_num,
    "client_id": cid,
    "edge_ip": ip,
    "fabric_round": fabric_round,
    "f1": f1,
    "fpr": fpr,
    "ipfs_ms": ipfs_ms,
    "tx_ms": tx_ms,
    "total_ms": total_ms
  })

  if ipfs_ms is not None: ipfs_vals.append(ipfs_ms)
  if tx_ms is not None: tx_vals.append(tx_ms)
  if total_ms is not None: total_vals.append(total_ms)
  if f1 is not None: f1_vals.append(f1)
  if fpr is not None: fpr_vals.append(fpr)

out_csv.parent.mkdir(parents=True, exist_ok=True)
with out_csv.open("w", newline="") as f:
  w = csv.DictWriter(f, fieldnames=["round","client_id","edge_ip","fabric_round","f1","fpr","ipfs_ms","tx_ms","total_ms"])
  w.writeheader()
  for r in rows:
    w.writerow(r)

summary = {
  "round": round_num,
  "n_clients": len(rows),
  "n_with_fabric_lat": len(total_vals),
  "f1": {"avg": (sum(f1_vals)/len(f1_vals) if f1_vals else None), "min": (min(f1_vals) if f1_vals else None), "max": (max(f1_vals) if f1_vals else None)},
  "fpr": {"avg": (sum(fpr_vals)/len(fpr_vals) if fpr_vals else None), "min": (min(fpr_vals) if fpr_vals else None), "max": (max(fpr_vals) if fpr_vals else None)},
  "ipfs_ms": {"p50": pctl(ipfs_vals,50), "p95": pctl(ipfs_vals,95), "p99": pctl(ipfs_vals,99), "min": (min(ipfs_vals) if ipfs_vals else None), "max": (max(ipfs_vals) if ipfs_vals else None)},
  "tx_ms": {"p50": pctl(tx_vals,50), "p95": pctl(tx_vals,95), "p99": pctl(tx_vals,99), "min": (min(tx_vals) if tx_vals else None), "max": (max(tx_vals) if tx_vals else None)},
  "total_ms": {"p50": pctl(total_vals,50), "p95": pctl(total_vals,95), "p99": pctl(total_vals,99), "min": (min(total_vals) if total_vals else None), "max": (max(total_vals) if total_vals else None)},
  "files": {"csv": str(out_csv), "json": str(out_json)}
}

out_json.write_text(json.dumps(summary, indent=2))
print("OK")
print("CSV=", out_csv)
print("JSON=", out_json)
print("SUMMARY=", json.dumps(summary, indent=2))
PY
}

final_summary () {
  local TS
  TS=$(date -u +%Y%m%d_%H%M%S)
  local OUT_JSON="$SUM_DIR/p7_baseline_all_rounds_${TS}.json"

  python3 - "$SUM_DIR" "$OUT_JSON" <<'PY'
import sys, glob, json, csv, os

sum_dir = sys.argv[1]
out_json = sys.argv[2]

files = sorted(glob.glob(os.path.join(sum_dir, "p7_baseline_round*_clients_*.csv")))
if not files:
  raise SystemExit("ERROR: no per-round CSV found in summary dir")

all_rows=[]
for f in files:
  with open(f, newline="") as fh:
    r = csv.DictReader(fh)
    for row in r:
      def conv(x):
        if x is None: return None
        x=str(x).strip()
        if x=="" or x.lower()=="none": return None
        try:
          if "." in x: return float(x)
          return int(x)
        except:
          return None
      row["round"]=conv(row.get("round"))
      row["fabric_round"]=conv(row.get("fabric_round"))
      row["f1"]=conv(row.get("f1"))
      row["fpr"]=conv(row.get("fpr"))
      row["ipfs_ms"]=conv(row.get("ipfs_ms"))
      row["tx_ms"]=conv(row.get("tx_ms"))
      row["total_ms"]=conv(row.get("total_ms"))
      all_rows.append(row)

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

ipfs=[r["ipfs_ms"] for r in all_rows]
tx=[r["tx_ms"] for r in all_rows]
tot=[r["total_ms"] for r in all_rows]
f1=[r["f1"] for r in all_rows]
fpr=[r["fpr"] for r in all_rows]

summary={
  "n_files": len(files),
  "n_rows": len(all_rows),
  "f1": {"avg": (sum([x for x in f1 if x is not None])/len([x for x in f1 if x is not None]) if any(x is not None for x in f1) else None),
         "min": (min([x for x in f1 if x is not None]) if any(x is not None for x in f1) else None),
         "max": (max([x for x in f1 if x is not None]) if any(x is not None for x in f1) else None)},
  "fpr": {"avg": (sum([x for x in fpr if x is not None])/len([x for x in fpr if x is not None]) if any(x is not None for x in fpr) else None),
          "min": (min([x for x in fpr if x is not None]) if any(x is not None for x in fpr) else None),
          "max": (max([x for x in fpr if x is not None]) if any(x is not None for x in fpr) else None)},
  "ipfs_ms": {"p50": pctl(ipfs,50), "p95": pctl(ipfs,95), "p99": pctl(ipfs,99), "min": (min([x for x in ipfs if x is not None]) if any(x is not None for x in ipfs) else None), "max": (max([x for x in ipfs if x is not None]) if any(x is not None for x in ipfs) else None)},
  "tx_ms": {"p50": pctl(tx,50), "p95": pctl(tx,95), "p99": pctl(tx,99), "min": (min([x for x in tx if x is not None]) if any(x is not None for x in tx) else None), "max": (max([x for x in tx if x is not None]) if any(x is not None for x in tx) else None)},
  "total_ms": {"p50": pctl(tot,50), "p95": pctl(tot,95), "p99": pctl(tot,99), "min": (min([x for x in tot if x is not None]) if any(x is not None for x in tot) else None), "max": (max([x for x in tot if x is not None]) if any(x is not None for x in tot) else None)},
  "inputs": files
}

with open(out_json,"w") as f:
  json.dump(summary,f,indent=2)

print("OK")
print("GLOBAL_JSON=", out_json)
print("GLOBAL_SUMMARY=", json.dumps(summary, indent=2))
PY
}

r="$START_ROUND"
while [ "$r" -le "$END_ROUND" ]; do
  run_one_round "$r"
  summarize_round "$r"
  r=$((r+1))
done

final_summary
