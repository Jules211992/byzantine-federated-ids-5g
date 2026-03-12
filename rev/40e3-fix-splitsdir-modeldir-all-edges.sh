#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX SPLITS_DIR/MODEL_DIR on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

python3 - <<'PY'
import re
from pathlib import Path
import py_compile

p = Path("/opt/fl-client/fl_ids_client.py")
txt = p.read_text()

has_splits = re.search(r'^\s*SPLITS_DIR\s*=', txt, flags=re.M) is not None
has_model  = re.search(r'^\s*MODEL_DIR\s*=',  txt, flags=re.M) is not None

if has_splits and has_model:
    print("OK_ALREADY_HAS_SPLITS_MODEL")
    raise SystemExit(0)

lines = txt.splitlines(True)

insert_idx = 0
seen_import = False
for i, line in enumerate(lines):
    if re.match(r'^(import|from)\s+', line):
        insert_idx = i + 1
        seen_import = True
    else:
        if seen_import:
            break

block = [
    "\n",
    "SPLITS_DIR = os.environ.get('SPLITS_DIR', '/opt/fl-client/splits')\n",
    "MODEL_DIR  = os.environ.get('MODEL_DIR',  '/opt/fl-client/models')\n",
    "\n",
]

new_txt = "".join(lines[:insert_idx] + block + lines[insert_idx:])
p.write_text(new_txt)

py_compile.compile(str(p), doraise=True)

print("OK_INSERTED_AT_LINE", insert_idx + 1)
print("HEAD_25")
for j, l in enumerate(p.read_text().splitlines(), start=1):
    if j > 25:
        break
    print(f"{j:>3} {l}")
PY
REMOTE
done

echo DONE
