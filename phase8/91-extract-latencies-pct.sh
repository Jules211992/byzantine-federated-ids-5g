#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

MAP=/home/ubuntu/byz-fed-ids-5g/config/edges_map.txt
OUT_DIR=/home/ubuntu/byz-fed-ids-5g/phase8/logs
mkdir -p "$OUT_DIR"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT_JSON="$OUT_DIR/p8_latencies_percentiles_${TS}.json"

python3 - <<'PY' > "$OUT_JSON"
import re, json, math, subprocess, time

MAP = "/home/ubuntu/byz-fed-ids-5g/config/edges_map.txt"
SSH_KEY = "/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem"

def sh(cmd):
  return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.STDOUT)

def pct(vals, p):
  if not vals:
    return None
  vals = sorted(vals)
  k = (len(vals)-1) * (p/100.0)
  f = int(math.floor(k))
  c = int(math.ceil(k))
  if f == c:
    return vals[f]
  return vals[f] + (vals[c]-vals[f])*(k-f)

edges = []
for line in open(MAP):
  line=line.strip()
  if not line:
    continue
  cid, ip = line.split()
  edges.append((cid, ip))

rx = re.compile(r"ipfs=(\d+)ms.*tx=(\d+)ms.*total=(\d+)ms")
report = {"edges":{}, "overall":{}}

all_ipfs=[]
all_tx=[]
all_total=[]

for cid, ip in edges:
  cmd = f"ssh -i {SSH_KEY} -o StrictHostKeyChecking=no ubuntu@{ip} \"find /opt/fl-client/logs -maxdepth 1 -type f -name 'fl_fabric_*_r*.out' -mmin -240 2>/dev/null | sort\""
  try:
    files = sh(cmd).strip().splitlines()
  except Exception:
    files = []
  ipfs=[]
  tx=[]
  total=[]
  for f in files:
    try:
      txt = sh(f"ssh -i {SSH_KEY} -o StrictHostKeyChecking=no ubuntu@{ip} \"tail -n 120 {f}\"")
    except Exception:
      continue
    for line in txt.splitlines():
      m = rx.search(line)
      if m:
        ipfs.append(int(m.group(1)))
        tx.append(int(m.group(2)))
        total.append(int(m.group(3)))
  report["edges"][cid] = {
    "n": len(total),
    "ipfs_ms": {"p50": pct(ipfs,50), "p95": pct(ipfs,95), "p99": pct(ipfs,99), "min": min(ipfs) if ipfs else None, "max": max(ipfs) if ipfs else None},
    "tx_ms": {"p50": pct(tx,50), "p95": pct(tx,95), "p99": pct(tx,99), "min": min(tx) if tx else None, "max": max(tx) if tx else None},
    "total_ms": {"p50": pct(total,50), "p95": pct(total,95), "p99": pct(total,99), "min": min(total) if total else None, "max": max(total) if total else None},
  }
  all_ipfs += ipfs
  all_tx += tx
  all_total += total

report["overall"] = {
  "n": len(all_total),
  "ipfs_ms": {"p50": pct(all_ipfs,50), "p95": pct(all_ipfs,95), "p99": pct(all_ipfs,99), "min": min(all_ipfs) if all_ipfs else None, "max": max(all_ipfs) if all_ipfs else None},
  "tx_ms": {"p50": pct(all_tx,50), "p95": pct(all_tx,95), "p99": pct(all_tx,99), "min": min(all_tx) if all_tx else None, "max": max(all_tx) if all_tx else None},
  "total_ms": {"p50": pct(all_total,50), "p95": pct(all_total,95), "p99": pct(all_total,99), "min": min(all_total) if all_total else None, "max": max(all_total) if all_total else None},
}

print(json.dumps(report, indent=2))
PY

echo "SAVED $OUT_JSON"
cat "$OUT_JSON"
