#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

echo
echo "===== VM2 run_fl_round.sh ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set -e
  sed -n "1,260p" /opt/fl-client/run_fl_round.sh
'

echo
echo "===== VM2 fl_fabric log (latest edge-client-1 r1) ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set -e
  echo "--- file info ---"
  ls -l /opt/fl-client/logs/fl_fabric_edge-client-1_r1.out || true
  echo
  echo "--- content ---"
  sed -n "1,220p" /opt/fl-client/logs/fl_fabric_edge-client-1_r1.out || true
'

echo
echo "===== VM2 fl_client log (latest edge-client-1 r1) ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set -e
  echo "--- file info ---"
  ls -l /opt/fl-client/logs/fl_client_edge-client-1_r1.out || true
  echo
  echo "--- tail ---"
  tail -n 80 /opt/fl-client/logs/fl_client_edge-client-1_r1.out || true
'

echo
echo "===== VM2 rerun exact full chain ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" '
  set +e
  rm -f /opt/fl-client/logs/fl_client_edge-client-1_r1.out
  rm -f /opt/fl-client/logs/fl_fabric_edge-client-1_r1.out
  rm -f /opt/fl-client/logs/fl-ids-edge-client-1-r1.json
  bash /opt/fl-client/run_fl_round.sh edge-client-1 1 Org1MSP peer0.org1.example.com 95123 > /tmp/runfl_edge1_full.out 2>&1
  rc=$?
  set -e
  echo "RC=$rc"
  echo
  echo "--- /tmp/runfl_edge1_full.out ---"
  sed -n "1,220p" /tmp/runfl_edge1_full.out || true
  echo
  echo "--- fl_fabric_edge-client-1_r1.out ---"
  sed -n "1,220p" /opt/fl-client/logs/fl_fabric_edge-client-1_r1.out || true
  echo
  echo "--- fl_client_edge-client-1_r1.out tail ---"
  tail -n 80 /opt/fl-client/logs/fl_client_edge-client-1_r1.out || true
  echo
  echo "--- logs dir ---"
  ls -lt /opt/fl-client/logs | head -20
'

echo
echo "===== PEER0 ORG1 docker status ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" '
  set -e
  docker ps --format "table {{.Names}}\t{{.Status}}" | sed -n "1,40p"
'

echo
echo "===== PEER0 ORG1 logs (last 5 min) ====="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" '
  set -e
  docker logs peer0.org1.example.com --since 5m 2>&1 | tail -n 260 || true
'
