#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== RESET SPLITS+MODELS on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

rm -f /opt/fl-client/models/*.npz 2>/dev/null || true

python3 - <<'PY'
from pathlib import Path
import shutil
spl = Path('/opt/fl-client/splits')
n=0
for p in sorted(spl.glob('*_train_y_orig.npy')):
    dst = spl / p.name.replace('_train_y_orig.npy','_train_y.npy')
    if dst.exists():
        shutil.copy2(p, dst)
        n += 1
print('RESTORED_TRAIN_Y=', n)
PY

ls -la /opt/fl-client/models | head -n 5 || true
"
done

echo DONE
