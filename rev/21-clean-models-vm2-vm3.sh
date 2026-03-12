#!/bin/bash
set -euo pipefail
cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

for ip in "$VM2_IP" "$VM3_IP"; do
  echo
  echo "===== CLEAN models on $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

rm -f /opt/fl-client/models/edge-client-*_model.npz || true
echo 'MODELS_LEFT='
ls -1 /opt/fl-client/models 2>/dev/null | wc -l || true
"
done
echo OK
