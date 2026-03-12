#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FORCE GLOBALS on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

python3 - <<'PY'
import re
from pathlib import Path

p = Path("/opt/fl-client/fl_ids_client.py")
txt = p.read_text()

if "__FL_GLOBALS__" in txt:
    print("OK_ALREADY_HAS_GLOBALS_MARKER")
else:
    lines = txt.splitlines(True)
    ins_idx = None

    for i, line in enumerate(lines):
        if re.match(r'^(def|class)\s+', line):
            ins_idx = i
            break

    if ins_idx is None:
        ins_idx = len(lines)

    block = [
        "\n",
        "__FL_GLOBALS__ = True\n",
        "CLIENT_ID = os.environ.get('CLIENT_ID', 'unknown')\n",
        "ROUND = int(os.environ.get('ROUND', '0'))\n",
        "LR = float(os.environ.get('LR', '0.005'))\n",
        "EPOCHS = int(os.environ.get('EPOCHS', '1'))\n",
        "MODEL_DIR = os.environ.get('MODEL_DIR', '/opt/fl-client/models')\n",
        "SPLITS_DIR = os.environ.get('SPLITS_DIR', '/opt/fl-client/splits')\n",
        "\n",
    ]

    new_lines = lines[:ins_idx] + block + lines[ins_idx:]
    p.write_text("".join(new_lines))
    print("OK_INSERTED_GLOBALS_BEFORE_DEF_AT_LINE", ins_idx+1)

import py_compile
py_compile.compile(str(p), doraise=True)
print("OK_COMPILE")

print("TOP_25")
for i, l in enumerate(p.read_text().splitlines(), start=1):
    if i > 25:
        break
    print(f"{i:>3} {l}")
PY
REMOTE
done

echo DONE
