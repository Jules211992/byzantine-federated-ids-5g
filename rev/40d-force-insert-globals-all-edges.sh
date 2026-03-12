#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== INSERT GLOBALS on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/fl-client/fl_ids_client.py")
lines = p.read_text().splitlines(True)

has = lambda name: any(re.match(rf'^\s*{re.escape(name)}\s*=', l) for l in lines)

if has("CLIENT_ID") and has("ROUND") and has("LR") and has("EPOCHS"):
    print("OK_ALREADY_HAS_GLOBALS")
    raise SystemExit(0)

first_def = None
for i,l in enumerate(lines):
    if l.startswith("def "):
        first_def = i
        break
if first_def is None:
    raise SystemExit("ERROR: no def found")

pre = lines[:first_def]
post = lines[first_def:]

block = [
    "\n",
    "CLIENT_ID = os.environ.get('CLIENT_ID', 'unknown')\n",
    "ROUND = int(os.environ.get('ROUND', '0'))\n",
    "LR = float(os.environ.get('LR', '0.005'))\n",
    "EPOCHS = int(os.environ.get('EPOCHS', '1'))\n",
    "MODEL_DIR = os.environ.get('MODEL_DIR', '/opt/fl-client/models')\n",
    "SPLITS_DIR = os.environ.get('SPLITS_DIR', '/opt/fl-client/splits')\n",
    "\n",
]

p.write_text("".join(pre + block + post))
print("OK_PATCHED_GLOBALS")
PY

python3 -m py_compile /opt/fl-client/fl_ids_client.py

echo HOST:$(hostname) IP:$(hostname -I | awk "{print \$1}")
echo "--- GLOBALS ---"
grep -n -E '^CLIENT_ID\s*=|^ROUND\s*=|^LR\s*=|^EPOCHS\s*=|^MODEL_DIR\s*=|^SPLITS_DIR\s*=' /opt/fl-client/fl_ids_client.py || true
REMOTE
done

echo DONE
