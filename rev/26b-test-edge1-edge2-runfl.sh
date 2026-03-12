#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

run_one() {
  local ip="$1"
  local cid="$2"
  local fab="$3"

  echo
  echo "=============================="
  echo "TEST $cid @ $ip FABRIC_ROUND=$fab"
  echo "------------------------------"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo PATHS:
grep -E 'CERT_PATH|ID_CERT_PATH|ID_KEY_PATH' /opt/fl-client/config.env || true
echo

set +e
timeout 180 /opt/fl-client/run_fl_round.sh $cid 1 Org1MSP peer0.org1.example.com $fab
RC=\$?
set -e
echo RC=\$RC
echo

echo '--- latest fl_fabric log ---'
F=\$(ls -1t /opt/fl-client/logs/fl_fabric_${cid}_r1.out 2>/dev/null | head -n 1 || true)
if [ -n \"\$F\" ]; then
  ls -lh \"\$F\"
  tail -n 140 \"\$F\"
else
  echo 'MISSING fl_fabric log'
fi

exit \$RC
"
}

run_one "$VM2_IP" "edge-client-1" "72000" || true
run_one "$VM3_IP" "edge-client-6" "72001" || true

echo
echo "DONE"
