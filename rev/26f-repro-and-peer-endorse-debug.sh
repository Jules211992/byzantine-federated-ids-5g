#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }
mkdir -p "$RUN_DIR/manifest"

PEER_IP="${VM9_IP:-10.10.0.126}"

ROUND="${ROUND:-1}"
FAB_BASE="${FAB_BASE:-73000}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/manifest/peer_endorse_debug_${TS}.txt"
exec > >(tee "$OUT") 2>&1

echo "UTC=$TS"
echo "RUN_DIR=$RUN_DIR"
echo "PEER_IP=$PEER_IP"
echo "ROUND=$ROUND"
echo "FAB_BASE=$FAB_BASE"
echo

echo "=== 1) REPRO: run 2 tx (edge-client-1 on VM2, edge-client-6 on VM3) ==="
echo

run_tx() {
  local ip="$1"
  local cid="$2"
  local fab="$3"
  echo "----- $cid @ $ip FABRIC_ROUND=$fab -----"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
grep -E 'CERT_PATH|ID_CERT_PATH|ID_KEY_PATH' /opt/fl-client/config.env || true
set +e
/opt/fl-client/run_fl_round.sh $cid $ROUND Org1MSP peer0.org1.example.com $fab
rc=\$?
set -e
echo RC=\$rc
exit \$rc
" || true
  echo
}

run_tx "$VM2_IP" "edge-client-1" "$FAB_BASE"
run_tx "$VM3_IP" "edge-client-6" "$((FAB_BASE+1))"

echo
echo "=== 2) PEER: docker inspect + docker logs (NO stderr hiding) ==="
echo

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$PEER_IP" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
C=\$(sudo docker ps --format '{{.Names}}' | grep -E '^peer0\.org1(\.|$)' | head -n 1 || true)
echo PEER_CONTAINER=\$C
[ -n \"\$C\" ] || { echo 'ERROR: peer container not found'; exit 1; }

echo
echo LOG_DRIVER:
sudo docker inspect --format '{{.HostConfig.LogConfig.Type}}' \"\$C\" || true

echo
echo '--- docker logs since 10m (raw) ---'
sudo docker logs --since 10m \"\$C\" | tail -n 220 || true

echo
echo '--- grep (endorse/VSCC/ACL/MSP/signature/policy/MVCC/error/failed) since 10m ---'
sudo docker logs --since 10m \"\$C\" | grep -E 'endorse|VSCC|ACL|creator|MSP|signature|policy|MVCC|validation|access|denied|error|failed' | tail -n 260 || true
"

echo
echo "SAVED=$OUT"
