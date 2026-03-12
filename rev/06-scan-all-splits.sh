#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

echo "=== ORCH local scan ==="
for d in "$HOME/byz-fed-ids-5g/phase6/splits" "$HOME/byz-fed-ids-5g/splits"; do
  if [ -d "$d" ]; then
    echo
    echo "DIR=$d"
    ls -1 "$d"/*_train_X.npy 2>/dev/null | sed 's#.*/##' | sed 's/_train_X\.npy$//' | sort -V | uniq | sed -n '1,120p'
    echo "COUNT=$(ls -1 "$d"/*_train_X.npy 2>/dev/null | wc -l || true)"
  fi
done

echo
echo "=== EDGES scan (/opt/fl-client/splits) ==="
for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "----- EDGE $ip -----"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "
set -euo pipefail
d=/opt/fl-client/splits
if [ ! -d \$d ]; then
  echo NO_SPLITS_DIR
  exit 0
fi
echo HOST:\$(hostname)
ids=\$(ls -1 \$d/*_train_X.npy 2>/dev/null | sed 's#.*/##' | sed 's/_train_X\.npy$//' | sort -V | uniq)
echo \"COUNT=\$(echo \"\$ids\" | sed '/^$/d' | wc -l)\"
echo \"IDS:\"
echo \"\$ids\" | sed -n '1,120p'
"
done
