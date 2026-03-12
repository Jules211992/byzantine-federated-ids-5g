#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
IP="$VM2_IP"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$IP" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo

echo '--- py_compile ---'
python3 -m py_compile /opt/fl-client/fl_ids_client.py && echo OK_compile || echo FAIL_compile
echo

echo '--- maybe_poison occurrences ---'
grep -n 'maybe_poison' /opt/fl-client/fl_ids_client.py || true
echo

echo '--- latest fl_client logs r1 ---'
ls -1t /opt/fl-client/logs/fl_client_*_r1.out 2>/dev/null | head -n 10 || true
echo

for f in /opt/fl-client/logs/fl_client_edge-client-1_r1.out /opt/fl-client/logs/fl_client_edge-client-2_r1.out; do
  echo '===== '\"\$f\"' ====='
  if [ -f \"\$f\" ]; then
    tail -n 160 \"\$f\"
  else
    echo MISSING
  fi
  echo
done
"
