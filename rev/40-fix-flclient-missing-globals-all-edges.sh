#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX globals (CLIENT_ID/ROUND/LR/EPOCHS) on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/opt/fl-client/fl_ids_client.py")
lines = p.read_text().splitlines(True)

has_client_id = any(re.match(r'^\s*CLIENT_ID\s*=', l) for l in lines)
has_round     = any(re.match(r'^\s*ROUND\s*=', l) for l in lines)
has_lr        = any(re.match(r'^\s*LR\s*=', l) for l in lines)
has_epochs    = any(re.match(r'^\s*EPOCHS\s*=', l) for l in lines)

if has_client_id and has_round and has_lr and has_epochs:
    print("OK_ALREADY_HAS_GLOBALS")
    raise SystemExit(0)

first_def = None
for i,l in enumerate(lines):
    if l.startswith("def "):
        first_def = i
        break
if first_def is None:
    raise SystemExit("ERROR: cannot find first def")

imports_end = 0
for i,l in enumerate(lines[:first_def]):
    if l.startswith("import ") or l.startswith("from ") or l.strip()=="" or l.startswith("#!") or l.startswith("# -*-"):
        imports_end = i+1
    else:
        break

need_import_os = not any(re.match(r'^\s*import\s+os(\s|$|,)', l) for l in lines[:first_def]) and not any(re.match(r'^\s*from\s+os\s+import\s+', l) for l in lines[:first_def])

prefix = lines[:imports_end]
rest   = lines[imports_end:]

if need_import_os:
    prefix.append("import os\n")

block = [
    "\n",
    "CLIENT_ID = os.environ.get(\"CLIENT_ID\", \"unknown\")\n",
    "ROUND = int(os.environ.get(\"ROUND\", \"0\"))\n",
    "LR = float(os.environ.get(\"LR\", \"0.005\"))\n",
    "EPOCHS = int(os.environ.get(\"EPOCHS\", \"1\"))\n",
    "MODEL_DIR = os.environ.get(\"MODEL_DIR\", \"/opt/fl-client/models\")\n",
    "SPLITS_DIR = os.environ.get(\"SPLITS_DIR\", \"/opt/fl-client/splits\")\n",
    "\n",
]

p.write_text("".join(prefix + block + rest))
print("OK_PATCHED_GLOBALS", p)
PY

python3 -m py_compile /opt/fl-client/fl_ids_client.py

echo HOST:$(hostname) IP:$(hostname -I | awk '{print $1}')
echo "--- globals lines ---"
grep -n -E '^CLIENT_ID\s*=|^ROUND\s*=|^LR\s*=|^EPOCHS\s*=|^MODEL_DIR\s*=|^SPLITS_DIR\s*=' /opt/fl-client/fl_ids_client.py | head -n 20 || true
REMOTE
done

echo DONE
