#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

IP="$VM2_IP"
SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$IP" "
set -euo pipefail
F=/opt/fl-client/fl_ids_client.py
python3 - <<'PY'
import re
from pathlib import Path

p = Path('/opt/fl-client/fl_ids_client.py')
lines = p.read_text().splitlines(True)

clean=[]
for line in lines:
    s=line.strip()
    if re.match(r'^w,\s*b,\s*attack_used\s*=\s*maybe_poison\(w,\s*b\)\s*$', s):
        continue
    if re.match(r'^if\s+attack_used\s*:\s*$', s):
        continue
    if re.search(r\"print\\(.*attack=\", s) and 'attack_used' in s:
        continue
    clean.append(line)

idx=None
for i,l in enumerate(clean):
    if 'print(f\"  L_inf=' in l or \"print(f'  L_inf=\" in l:
        idx=i

if idx is None:
    raise SystemExit('ERROR: cannot find L_inf print line')

indent=re.match(r'^(\\s*)', clean[idx]).group(1)
block=[
    f\"{indent}w, b, attack_used = maybe_poison(w, b)\\n\",
    f\"{indent}if attack_used:\\n\",
    f\"{indent}    print('  attack=', attack_used)\\n\",
]

out = clean[:idx+1] + block + clean[idx+1:]
p.write_text(''.join(out))

print('OK_PATCHED')
PY

echo
echo '--- check maybe_poison lines ---'
grep -n 'maybe_poison' /opt/fl-client/fl_ids_client.py | head -n 20

echo
echo '--- show around L_inf (145-175) ---'
nl -ba /opt/fl-client/fl_ids_client.py | sed -n '145,175p'
"
