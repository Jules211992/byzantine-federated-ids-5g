#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: RUN_DIR introuvable dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/manifest/edge_subips_audit_${TS}.txt"
mkdir -p "$RUN_DIR/manifest"

exec > >(tee "$OUT") 2>&1

echo "UTC=$TS"
echo "RUN_DIR=$RUN_DIR"
echo

CAND=()
while read -r ip; do
  [ -z "${ip:-}" ] && continue
  CAND+=("$ip")
done < ./config/nodes_ip.txt
CAND=($(printf "%s\n" "${CAND[@]}" | sort -u))

echo "CANDIDATES=${#CAND[@]}"
echo

for ip in "${CAND[@]}"; do
  echo "=============================="
  echo "VM=$ip"
  echo "------------------------------"
  set +e
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 ubuntu@"$ip" "
set -euo pipefail
H=\$(hostname 2>/dev/null || true)
IP1=\$(hostname -I 2>/dev/null | awk '{print \$1}' || true)

echo \"HOST=\$H\"
echo \"PRIMARY_IP=\$IP1\"
echo

echo 'IP_BRIEF:'
ip -br -4 addr || true
echo

echo 'HOSTNAME_I:'
hostname -I || true
echo

EDGE=0
if [ -d /opt/fl-client ] && [ -f /opt/fl-client/run_fl_round.sh ]; then
  EDGE=1
fi
echo \"IS_EDGE=\$EDGE\"
echo

if [ \"\$EDGE\" = \"1\" ]; then
  echo 'OPT_FL_CLIENT:'
  ls -la /opt/fl-client | sed -n '1,80p' || true
  echo
  echo 'CONFIG_ENV (if any):'
  ls -la /opt/fl-client/config.env 2>/dev/null || true
  sed -n '1,120p' /opt/fl-client/config.env 2>/dev/null || true
fi
" 2>/dev/null
  RC=$?
  set -e

  if [ $RC -ne 0 ]; then
    echo "SSH_FAIL"
  fi
  echo
done

echo "SAVED=$OUT"
