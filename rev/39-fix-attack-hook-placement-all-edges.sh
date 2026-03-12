#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX maybe_poison placement on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
python3 - <<'PY'
import re
from pathlib import Path

p = Path('/opt/fl-client/fl_ids_client.py')
lines = p.read_text().splitlines(True)

clean=[]
for line in lines:
    s=line.strip()
    if re.match(r'^\s*w,\s*b,\s*attack_used\s*=\s*maybe_poison\(w,\s*b\)\s*$', s):
        continue
    if re.match(r'^\s*if\s+attack_used\s*:\s*$', s):
        continue
    if re.match(r'^\s*print\(\s*[\"\\\']\s*attack=\s*[\"\\\']\s*,\s*attack_used\s*\)\s*$', s):
        continue
    clean.append(line)

insert=None
indent=\"\"
for i,l in enumerate(clean):
    if 'L_inf=' in l and 'test_metrics' in l:
        insert=i+1
        indent=l[:len(l)-len(l.lstrip())]
        break

if insert is None:
    raise SystemExit('ERROR: cannot find insertion point (L_inf line)')

hook = (
    indent + 'w, b, attack_used = maybe_poison(w, b)\\n' +
    indent + 'if attack_used:\\n' +
    indent + '    print(\\'  attack=\\', attack_used)\\n'
)

clean.insert(insert, hook)
p.write_text(''.join(clean))

print('OK_PATCHED', p)
PY

python3 -m py_compile /opt/fl-client/fl_ids_client.py
grep -n 'maybe_poison' /opt/fl-client/fl_ids_client.py | head -n 5
nl -ba /opt/fl-client/fl_ids_client.py | sed -n '140,175p'
"
done

echo DONE
