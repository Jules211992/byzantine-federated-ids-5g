#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

MAP="$RUN_DIR/config/edges_map_20.txt"
OUT_DIR="$RUN_DIR/p7_baseline/round01/client_logs"
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
OUT_CSV="$SUM_DIR/p7_baseline_round01_clients_${TS}.csv"
OUT_JSON="$SUM_DIR/p7_baseline_round01_latency_pct_${TS}.json"

python3 - "$MAP" "$OUT_DIR" "$OUT_CSV" "$OUT_JSON" <<'PY'
import sys, re, csv, json
from pathlib import Path
import math

map_path = Path(sys.argv[1])
logs_dir = Path(sys.argv[2])
out_csv  = Path(sys.argv[3])
out_json = Path(sys.argv[4])

rx_runfl = re.compile(r"\[(?P<client>[^\]]+)\]\s+round=(?P<round>\d+)\s+fabric_round=(?P<fabric>\d+)\s+CID=(?P<cid>[A-Za-z0-9]+).*?F1=(?P<f1>[\d.]+)\s+FPR=(?P<fpr>[\d.]+)\s+OK")
rx_fabric = re.compile(r"\[(?P<client>[^\]]+)\]\s+round=(?P<fabric>\d+)\s+CID=(?P<cid>[A-Za-z0-9]+).*?ipfs=(?P<ipfs>\d+)ms\s+tx=(?P<tx>\d+)ms\s+total=(?P<total>\d+)ms")

def pct(values, p):
    if not values:
        return None
    xs = sorted(values)
    if len(xs) == 1:
        return float(xs[0])
    k = (len(xs) - 1) * (p/100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return float(xs[int(k)])
    d0 = xs[f] * (c - k)
    d1 = xs[c] * (k - f)
    return float(d0 + d1)

mapping = []
for line in map_path.read_text().splitlines():
    line=line.strip()
    if not line:
        continue
    parts=line.split()
    if len(parts) < 2:
        continue
    mapping.append((parts[0], parts[1]))

rows=[]
ipfs_vals=[]
tx_vals=[]
total_vals=[]

for client, ip in mapping:
    runfl_file = logs_dir / f"{client}.runfl.out"
    fab_file   = logs_dir / f"{client}.fl_fabric.out"

    round_id = None
    fabric_round = None
    cid_runfl = None
    f1 = None
    fpr = None

    if runfl_file.exists():
        txt = runfl_file.read_text(errors="ignore")
        m = rx_runfl.search(txt)
        if m:
            round_id = int(m.group("round"))
            fabric_round = int(m.group("fabric"))
            cid_runfl = m.group("cid")
            f1 = float(m.group("f1"))
            fpr = float(m.group("fpr"))

    cid_fab = None
    ipfs_ms = None
    tx_ms = None
    total_ms = None
    if fab_file.exists():
        txt = fab_file.read_text(errors="ignore")
        m = rx_fabric.search(txt)
        if m:
            cid_fab = m.group("cid")
            ipfs_ms = int(m.group("ipfs"))
            tx_ms = int(m.group("tx"))
            total_ms = int(m.group("total"))
            ipfs_vals.append(ipfs_ms)
            tx_vals.append(tx_ms)
            total_vals.append(total_ms)

    rows.append({
        "client_id": client,
        "ip": ip,
        "round": round_id,
        "fabric_round": fabric_round,
        "cid_runfl": cid_runfl,
        "cid_fabric": cid_fab,
        "f1": f1,
        "fpr": fpr,
        "ipfs_ms": ipfs_ms,
        "tx_ms": tx_ms,
        "total_ms": total_ms,
        "has_runfl_log": int(runfl_file.exists()),
        "has_fabric_log": int(fab_file.exists()),
    })

with out_csv.open("w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader()
    w.writerows(rows)

summary = {
    "round": 1,
    "n_clients": len(rows),
    "n_with_fabric_lat": sum(1 for r in rows if r["total_ms"] is not None),
    "ipfs_ms": {"p50": pct(ipfs_vals,50), "p95": pct(ipfs_vals,95), "p99": pct(ipfs_vals,99), "min": min(ipfs_vals) if ipfs_vals else None, "max": max(ipfs_vals) if ipfs_vals else None},
    "tx_ms":   {"p50": pct(tx_vals,50),   "p95": pct(tx_vals,95),   "p99": pct(tx_vals,99),   "min": min(tx_vals) if tx_vals else None,   "max": max(tx_vals) if tx_vals else None},
    "total_ms":{"p50": pct(total_vals,50),"p95": pct(total_vals,95),"p99": pct(total_vals,99),"min": min(total_vals) if total_vals else None,"max": max(total_vals) if total_vals else None},
    "files": {"csv": str(out_csv), "json": str(out_json)}
}

out_json.write_text(json.dumps(summary, indent=2))

print("OK")
print("CSV=", out_csv)
print("JSON=", out_json)
print("SUMMARY=", json.dumps(summary, indent=2))
PY
