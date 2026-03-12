#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX BYZ_CLIENTS quoting on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
CFG=/opt/fl-client/config.env
[ -f \"\$CFG\" ] || { echo \"ERROR: missing \$CFG\"; exit 1; }

python3 - <<'PY'
from pathlib import Path
p=Path('/opt/fl-client/config.env')
lines=p.read_text().splitlines()
out=[]
for line in lines:
    if line.startswith('BYZ_CLIENTS='):
        val=line.split('=',1)[1].strip()
        if val and not (val.startswith('\"') and val.endswith('\"')):
            val=val.strip('\"').strip(\"'\")
            line='BYZ_CLIENTS=\"'+val+'\"'
    out.append(line)
p.write_text('\\n'.join(out)+'\\n')
print('OK:', [l for l in out if l.startswith('BYZ_CLIENTS=')][0])
PY

echo '--- attack lines ---'
grep -E '^BYZ_CLIENTS=|^ATTACK_MODE=|^ATTACK_SCALE=' \"\$CFG\" || true
"
done

echo DONE
