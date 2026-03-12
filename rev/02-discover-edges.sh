#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

CAND=()
if [ -f ./config/nodes_ip.txt ]; then
  while read -r ip; do
    [ -z "${ip:-}" ] && continue
    CAND+=("$ip")
  done < ./config/nodes_ip.txt
fi

if [ -f ./config/edges_candidates.txt ]; then
  while read -r ip; do
    [ -z "${ip:-}" ] && continue
    CAND+=("$ip")
  done < ./config/edges_candidates.txt
fi

CAND=($(printf "%s\n" "${CAND[@]}" | sort -u))

echo "CANDIDATES=${#CAND[@]}"
echo

FOUND=0
for ip in "${CAND[@]}"; do
  echo "----- $ip -----"
  set +e
  OUT=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@"$ip" "
set -euo pipefail
H=\$(hostname || true)
IP=\$(hostname -I | awk '{print \$1}' || true)
if [ -d /opt/fl-client ] && [ -f /opt/fl-client/run_fl_round.sh ]; then
  echo \"EDGE_OK host=\$H ip=\$IP\"
  ls -la /opt/fl-client | sed -n '1,80p'
else
  echo \"NO_EDGE host=\$H ip=\$IP\"
fi
" 2>/dev/null)
  RC=$?
  set -e

  if [ $RC -ne 0 ]; then
    echo "SSH_FAIL"
    echo
    continue
  fi

  echo "$OUT" | sed -n '1,120p'
  echo

  if echo "$OUT" | grep -q '^EDGE_OK '; then
    FOUND=$((FOUND+1))
  fi
done

echo "FOUND_EDGES=$FOUND"
