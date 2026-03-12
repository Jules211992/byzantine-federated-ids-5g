#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX maybe_poison call position on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

F=/opt/fl-client/fl_ids_client.py
[ -f "$F" ] || { echo "ERROR: missing $F"; exit 1; }

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text().splitlines(True)

clean = []
for line in lines:
    s = line.strip()
    if re.match(r'^w,\s*b,\s*attack_used\s*=\s*maybe_poison\(w,\s*b\)\s*$', s):
        continue
    if re.match(r'^if\s+attack_used\s*:\s*$', s):
        continue
    if "print(" in s and "attack=" in s:
        continue
    clean.append(line)

lines = clean

idx = None
indent = ""
pat = re.compile(r'^(\s*)w\s*,\s*b\s*=\s*load_model\(\)\s*$')
for i, line in enumerate(lines):
    m = pat.match(line.rstrip("\n"))
    if m:
        idx = i
        indent = m.group(1)
        break

if idx is None:
    raise SystemExit('ERROR: cannot find: w, b = load_model()')

look = "".join(lines[idx+1:idx+12])
if "maybe_poison(" not in look:
    ins = [
        indent + "w, b, attack_used = maybe_poison(w, b)\n",
        indent + "if attack_used:\n",
        indent + "    print('  attack=', attack_used)\n",
    ]
    lines[idx+1:idx+1] = ins

p.write_text("".join(lines))
print("OK_PATCHED")
PY

python3 -m py_compile "$F" && echo OK_compile

echo "--- CHECK lines ---"
grep -n "w, b = load_model" "$F" || true
grep -n "maybe_poison" "$F" || true
REMOTE
done

echo DONE
