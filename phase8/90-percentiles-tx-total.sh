#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

OUT=~/byz-fed-ids-5g/phase8/logs/p8_percentiles_$(date -u +%Y%m%d_%H%M%S).json

python3 - <<'PY' > "$OUT"
import re, json, math, subprocess

edges = {
  "edge-client-1": "10.10.0.112",
  "edge-client-2": "10.10.0.11",
  "edge-client-3": "10.10.0.121",
  "edge-client-4": "10.10.0.10",
}

def sh(cmd):
  return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.STDOUT)

def pct(vals, p):
  if not vals:
    return None
  vals = sorted(vals)
  k = (len(vals)-1) * (p/100.0)
  f = math.floor(k)
  c = math.ceil(k)
  if f == c:
    return vals[int(k)]
  return vals[f] + (vals[c]-vals[f])*(k-f)

rx = re.compile(r"tx=(\d+)ms.*total=(\d+)ms")
data = {}

for cid, ip in edges.items():
  cmd = f"ssh -i ~/byz-fed-ids-5g/keys/fl-ids-key.pem -o StrictHostKeyChecking=no ubuntu@{ip} \"ls -1 /opt/fl-client/logs/fl_fabric_* 2>/dev/null | tail -n 200\""
  try:
    files = sh(cmd).strip().splitlines()
  except Exception:
    files = []
  tx = []
  total = []
  for f in files:
    try:
      txt = sh(f"ssh -i ~/byz-fed-ids-5g/keys/fl-ids-key.pem -o StrictHostKeyChecking=no ubuntu@{ip} \"tail -n 80 {f}\"")
    except Exception:
      continue
    for line in txt.splitlines():
      m = rx.search(line)
      if m:
        tx.append(int(m.group(1)))
        total.append(int(m.group(2)))
  data[cid] = {
    "n": len(tx),
    "tx_ms": {"p50": pct(tx,50), "p95": pct(tx,95), "p99": pct(tx,99)},
    "total_ms": {"p50": pct(total,50), "p95": pct(total,95), "p99": pct(total,99)},
  }

all_tx = []
all_total = []
for v in data.values():
  if v["n"]:
    all_tx += [v["tx_ms"]["p50"]] * 0
for cid, ip in edges.items():
  pass

print(json.dumps(data, indent=2))
PY

echo "SAVED $OUT"
cat "$OUT"
