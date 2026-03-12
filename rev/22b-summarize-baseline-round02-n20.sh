#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

MAP="$RUN_DIR/config/edges_map_20.txt"
OUT_DIR="$RUN_DIR/p7_baseline/round02/client_logs"
SUM_DIR="$RUN_DIR/summary"
mkdir -p "$SUM_DIR"

if [ ! -f "$MAP" ]; then
  echo "ERROR: edges_map_20.txt introuvable: $MAP"
  exit 1
fi
if [ ! -d "$OUT_DIR" ]; then
  echo "ERROR: client_logs introuvable: $OUT_DIR"
  exit 1
fi

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_CSV="$SUM_DIR/p7_baseline_round02_clients_${TS}.csv"
OUT_JSON="$SUM_DIR/p7_baseline_round02_latency_pct_${TS}.json"

python3 - "$MAP" "$OUT_DIR" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, re, csv, json
from pathlib import Path

map_path = Path(sys.argv[1])
logs_dir = Path(sys.argv[2])
out_csv  = Path(sys.argv[3])
out_json = Path(sys.argv[4])

round_num = 2

clients = []
for line in map_path.read_text().splitlines():
    line=line.strip()
    if not line or line.startswith("#"): 
        continue
    cid, ip = line.split()
    clients.append(cid)

re_run_ok = re.compile(r'^\[(?P<cid>edge-client-\d+)\]\s+round=(?P<round>\d+)\s+fabric_round=(?P<fab>\d+)\s+CID=(?P<cidipfs>\S+)\s+F1=(?P<f1>[\d.]+)\s+FPR=(?P<fpr>[\d.]+)\s+OK', re.M)

re_lat = re.compile(r'^\[(?P<cid>edge-client-\d+)\]\s+round=(?P<fab>\d+)\s+CID=(?P<cidipfs>\S+)\s+ipfs=(?P<ipfs>\d+)ms\s+tx=(?P<tx>\d+)ms\s+total=(?P<total>\d+)ms', re.M)

rows=[]
ipfs_vals=[]; tx_vals=[]; total_vals=[]

for cid in sorted(clients, key=lambda x: int(x.split("-")[-1])):
    runfl = logs_dir / f"{cid}.runfl.out"
    fab   = logs_dir / f"{cid}.fl_fabric.out"
    f1=fpr=fab_round=cid_ipfs=None
    ipfs=tx=total=None

    if runfl.exists():
        m = list(re_run_ok.finditer(runfl.read_text(errors="ignore")))
        if m:
            mm=m[-1]
            f1=float(mm.group("f1"))
            fpr=float(mm.group("fpr"))
            fab_round=int(mm.group("fab"))
            cid_ipfs=mm.group("cidipfs")

    if fab.exists():
        m = list(re_lat.finditer(fab.read_text(errors="ignore")))
        if m:
            mm=m[-1]
            ipfs=int(mm.group("ipfs"))
            tx=int(mm.group("tx"))
            total=int(mm.group("total"))

    if ipfs is not None: ipfs_vals.append(ipfs)
    if tx   is not None: tx_vals.append(tx)
    if total is not None: total_vals.append(total)

    rows.append({
        "round": round_num,
        "client_id": cid,
        "fabric_round": fab_round,
        "f1": f1,
        "fpr": fpr,
        "ipfs_ms": ipfs,
        "tx_ms": tx,
        "total_ms": total,
        "cid": cid_ipfs
    })

out_csv.parent.mkdir(parents=True, exist_ok=True)
with out_csv.open("w", newline="") as f:
    w=csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

def pct(vals, p):
    if not vals:
        return None
    vals=sorted(vals)
    if len(vals)==1:
        return float(vals[0])
    k=(len(vals)-1)*p/100.0
    f=int(k); c=min(f+1, len(vals)-1)
    if f==c:
        return float(vals[f])
    d=k-f
    return float(vals[f]*(1-d) + vals[c]*d)

summary = {
    "round": round_num,
    "n_clients": len(rows),
    "n_with_fabric_lat": len(total_vals),
    "ipfs_ms":  {"p50": pct(ipfs_vals,50), "p95": pct(ipfs_vals,95), "p99": pct(ipfs_vals,99), "min": min(ipfs_vals) if ipfs_vals else None, "max": max(ipfs_vals) if ipfs_vals else None},
    "tx_ms":    {"p50": pct(tx_vals,50),   "p95": pct(tx_vals,95),   "p99": pct(tx_vals,99),   "min": min(tx_vals) if tx_vals else None,   "max": max(tx_vals) if tx_vals else None},
    "total_ms": {"p50": pct(total_vals,50),"p95": pct(total_vals,95),"p99": pct(total_vals,99),"min": min(total_vals) if total_vals else None,"max": max(total_vals) if total_vals else None},
    "files": {"csv": str(out_csv), "json": str(out_json)}
}

out_json.write_text(json.dumps(summary, indent=2))
print("OK")
print("CSV=", str(out_csv))
print("JSON=", str(out_json))
print("SUMMARY=", json.dumps(summary, indent=2))
PY
