#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

OUT_DIR="$RUN_DIR/p7_baseline/round01/client_logs"
FAILS="$RUN_DIR/p7_baseline/round01/edge_logs/failures.txt"

echo "RUN_DIR=$RUN_DIR"
echo "OUT_DIR=$OUT_DIR"
echo "FAILS=$FAILS"

echo
echo "===== FAILURES ====="
cat "$FAILS" 2>/dev/null || true

echo
echo "===== LOCAL COPIED LOGS ====="
ls -lt "$OUT_DIR" | head -30 || true

echo
echo "===== edge-client-1.runfl.out ====="
sed -n '1,220p' "$OUT_DIR/edge-client-1.runfl.out" 2>/dev/null || echo "ABSENT"

echo
echo "===== edge-client-1.fl_client.out ====="
sed -n '1,220p' "$OUT_DIR/edge-client-1.fl_client.out" 2>/dev/null || echo "ABSENT"

echo
echo "===== edge-client-1.fl_fabric.out ====="
sed -n '1,220p' "$OUT_DIR/edge-client-1.fl_fabric.out" 2>/dev/null || echo "ABSENT"

echo
echo "===== REMOTE run_fl_round.sh ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set -e
  sed -n "1,260p" /opt/fl-client/run_fl_round.sh
'

echo
echo "===== REMOTE DIRECT CLIENT SMOKE ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set +e
  rm -f /opt/fl-client/logs/*edge-client-1*r901*
  CLIENT_ID=edge-client-1 ROUND=901 EPOCHS=1 python3 /opt/fl-client/fl_ids_client.py > /tmp/edge1_client_smoke.out 2>&1
  rc=$?
  set -e
  echo RC=$rc
  sed -n "1,220p" /tmp/edge1_client_smoke.out
  echo
  echo "--- logs dir ---"
  ls -lt /opt/fl-client/logs | head -20 || true
'

echo
echo "===== REMOTE FULL run_fl_round SMOKE ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set +e
  bash /opt/fl-client/run_fl_round.sh edge-client-1 1 Org1MSP peer0.org1.example.com 95100 > /tmp/edge1_runfl_smoke.out 2>&1
  rc=$?
  set -e
  echo RC=$rc
  sed -n "1,260p" /tmp/edge1_runfl_smoke.out
  echo
  echo "--- logs dir ---"
  ls -lt /opt/fl-client/logs | head -30 || true
'
