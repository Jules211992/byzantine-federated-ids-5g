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
OUT="$RUN_DIR/manifest/edge_splits_audit_${TS}.txt"
mkdir -p "$RUN_DIR/manifest"
exec > >(tee "$OUT") 2>&1

EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

echo "UTC=$TS"
echo "RUN_DIR=$RUN_DIR"
echo "EDGES=${EDGE_IPS[*]}"
echo

for ip in "${EDGE_IPS[@]}"; do
  echo "=============================="
  echo "EDGE=$ip"
  echo "------------------------------"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=8 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname)
echo IP:\$(hostname -I | awk '{print \$1}')
echo

echo '--- /opt/fl-client/config.env (first 80) ---'
sed -n '1,80p' /opt/fl-client/config.env 2>/dev/null || true
echo

echo '--- SPLITS DIR listing ---'
if [ -d /opt/fl-client/splits ]; then
  echo 'COUNT=' \$(find /opt/fl-client/splits -maxdepth 1 -type f | wc -l)
  ls -la /opt/fl-client/splits | sed -n '1,200p'
else
  echo 'NO_SPLITS_DIR'
fi
echo

echo '--- fl_ids_client.py: how splits are selected ---'
if [ -f /opt/fl-client/fl_ids_client.py ]; then
  grep -nE 'SPLIT|splits|SPLITS_DIR|CLIENT_ID|edge-client|dataset|DATASET' /opt/fl-client/fl_ids_client.py 2>/dev/null | sed -n '1,220p' || true
else
  echo 'MISSING: /opt/fl-client/fl_ids_client.py'
fi
"
  echo
done

echo "SAVED=$OUT"
