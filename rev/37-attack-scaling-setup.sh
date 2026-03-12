#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
ATTACK_MODE="${ATTACK_MODE:-scaling}"
ATTACK_SCALE="${ATTACK_SCALE:-5}"

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== SETUP SCALING on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
CFG=/opt/fl-client/config.env
[ -f \"\$CFG\" ] || touch \"\$CFG\"

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/fl-client/config.env')
lines=p.read_text().splitlines()
kv={}
for l in lines:
    if '=' in l and not l.lstrip().startswith('#'):
        k,v=l.split('=',1)
        kv[k.strip()]=v.strip()
kv['BYZ_CLIENTS'] = '\"' + \"${BYZ_CLIENTS}\" + '\"'
kv['ATTACK_MODE'] = \"${ATTACK_MODE}\"
kv['ATTACK_SCALE'] = \"${ATTACK_SCALE}\"
keep=[]
seen=set()
for l in lines:
    if '=' in l and not l.lstrip().startswith('#'):
        k=l.split('=',1)[0].strip()
        if k in ('BYZ_CLIENTS','ATTACK_MODE','ATTACK_SCALE'):
            if k not in seen:
                keep.append(f\"{k}={kv[k]}\")
                seen.add(k)
            continue
    keep.append(l)
for k in ('BYZ_CLIENTS','ATTACK_MODE','ATTACK_SCALE'):
    if k not in seen:
        keep.append(f\"{k}={kv[k]}\")
p.write_text('\\n'.join([x for x in keep if x is not None]).rstrip()+'\\n')
print('OK_SET')
PY

rm -f /opt/fl-client/models/*.npz 2>/dev/null || true

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
grep -E '^(BYZ_CLIENTS|ATTACK_MODE|ATTACK_SCALE)=' /opt/fl-client/config.env
ls -la /opt/fl-client/models | head -n 10 || true
"
done

echo DONE
