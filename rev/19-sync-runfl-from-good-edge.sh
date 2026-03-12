#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

SRC_IP="$VM5_IP"
TARGETS=("$VM2_IP" "$VM3_IP")
TMP=/tmp/run_fl_round.sh

scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$SRC_IP":/opt/fl-client/run_fl_round.sh "$TMP"

echo "SRC_SHA256:"
sha256sum "$TMP"

for ip in "${TARGETS[@]}"; do
  echo
  echo "===== SYNC to $ip ====="
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$TMP" ubuntu@"$ip":/tmp/run_fl_round.sh >/dev/null
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
set -euo pipefail
cp -f /tmp/run_fl_round.sh /opt/fl-client/run_fl_round.sh
chmod 755 /opt/fl-client/run_fl_round.sh
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo DST_SHA256:
sha256sum /opt/fl-client/run_fl_round.sh
head -n 18 /opt/fl-client/run_fl_round.sh
"
done

echo OK
