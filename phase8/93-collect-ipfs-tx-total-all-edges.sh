#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

MAP=/home/ubuntu/byz-fed-ids-5g/config/edges_map.txt
SSH_KEY=/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem

while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  [ -z "${ip:-}" ] && continue
  echo
  echo "===== $cid @ $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" "
set -euo pipefail
echo 'Recent fl_fabric files:'
find /opt/fl-client/logs -maxdepth 1 -type f -name 'fl_fabric_*' -mmin -600 2>/dev/null | sort | tail -n 30 || true
echo
echo 'Last ipfs/tx/total lines:'
find /opt/fl-client/logs -maxdepth 1 -type f -mmin -600 2>/dev/null | sort | tail -n 200 | while read -r f; do
  grep -hE 'ipfs=[0-9]+ms.*tx=[0-9]+ms.*total=[0-9]+ms' \"\$f\" 2>/dev/null || true
done | tail -n 30
" || true
done < "$MAP"
