#!/bin/bash
set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

ATTACK=$1
AGG=$2
ROUNDS=5
F_BYZANTINE=1
FABRIC_START=${3:-51}
OUT_DIR=~/byz-fed-ids-5g/phase8/logs
mkdir -p "$OUT_DIR"

echo ""
echo "=== Expérience: attack=$ATTACK aggregation=$AGG ==="

for ROUND in $(seq 1 $ROUNDS); do
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" \
    "CLIENT_ID=edge-client-1 ROUND=$ROUND EPOCHS=3 python3 /opt/fl-client/fl_ids_client.py > /dev/null 2>&1" &
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM3_IP" \
    "CLIENT_ID=edge-client-2-byz ROUND=$ROUND BYZ_TYPE=$ATTACK python3 /opt/fl-client/fl_ids_byzantine.py > /dev/null 2>&1" &
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM4_IP" \
    "CLIENT_ID=edge-client-3 ROUND=$ROUND EPOCHS=3 python3 /opt/fl-client/fl_ids_client.py > /dev/null 2>&1" &
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM5_IP" \
    "CLIENT_ID=edge-client-4 ROUND=$ROUND EPOCHS=3 python3 /opt/fl-client/fl_ids_client.py > /dev/null 2>&1" &
  wait

  ENTRIES="${VM2_IP}:/opt/fl-client/logs/fl-ids-edge-client-1-r${ROUND}.json:edge-client-1"
  ENTRIES+="|${VM3_IP}:/opt/fl-client/logs/fl-byz-edge-client-2-byz-r${ROUND}.json:edge-client-2-byz"
  ENTRIES+="|${VM4_IP}:/opt/fl-client/logs/fl-ids-edge-client-3-r${ROUND}.json:edge-client-3"
  ENTRIES+="|${VM5_IP}:/opt/fl-client/logs/fl-ids-edge-client-4-r${ROUND}.json:edge-client-4"

  if [ "$AGG" = "multikrum" ]; then
    python3 ~/byz-fed-ids-5g/phase7/multi_krum_aggregator.py \
      "$ROUND" "$F_BYZANTINE" "$ENTRIES" \
      > "$OUT_DIR/${ATTACK}_${AGG}_r${ROUND}.json"
    cat "$OUT_DIR/${ATTACK}_${AGG}_r${ROUND}.json"

  elif [ "$AGG" = "trimmedmean" ]; then
    python3 ~/byz-fed-ids-5g/phase8/trimmed_mean_aggregator.py \
      "$ROUND" "$F_BYZANTINE" "$ENTRIES" \
      > "$OUT_DIR/${ATTACK}_${AGG}_r${ROUND}.json"
    cat "$OUT_DIR/${ATTACK}_${AGG}_r${ROUND}.json"

  else
    python3 ~/byz-fed-ids-5g/phase8/fedavg_aggregator.py \
      "$ROUND" "$ENTRIES"
  fi
done
