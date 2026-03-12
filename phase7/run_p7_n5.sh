#!/bin/bash
set -euo pipefail

SSH_KEY=~/.ssh/fl-ids-key.pem
LOG_DIR=/home/ubuntu/byz-fed-ids-5g/phase7/logs
mkdir -p $LOG_DIR

declare -A VMS=(
  [edge-client-1]=10.10.0.112
  [edge-client-2]=10.10.0.11
  [edge-client-3]=10.10.0.121
  [edge-client-4]=10.10.0.10
)

N_ROUNDS=${N_ROUNDS:-10}
START_FABRIC=${START_FABRIC:-1000}

echo "=== Phase 7 baseline N=4 rounds=$N_ROUNDS ==="

for ROUND in $(seq 1 $N_ROUNDS); do
  echo ""
  echo "--- Round $ROUND ---"
  FABRIC_ROUND=$((START_FABRIC + ROUND - 1))

  for CLIENT_ID in "${!VMS[@]}"; do
    IP="${VMS[$CLIENT_ID]}"
    ssh -i $SSH_KEY ubuntu@$IP \
      "ROUND=$ROUND START_ROUND=$FABRIC_ROUND bash /opt/fl-client/run_fl_round.sh \
       $CLIENT_ID $ROUND Org1MSP peer0.org1.example.com $FABRIC_ROUND" &
  done
  wait
  echo "  Tous les clients terminés round $ROUND"

  ENTRIES=""
  for CLIENT_ID in "${!VMS[@]}"; do
    IP="${VMS[$CLIENT_ID]}"
    LOG_PATH="/opt/fl-client/logs/fl-ids-${CLIENT_ID}-r${ROUND}.json"
    ENTRIES="${ENTRIES}${IP}:${LOG_PATH}:${CLIENT_ID}|"
  done

  SSH_KEY=$SSH_KEY \
  python3 /home/ubuntu/byz-fed-ids-5g/phase7/multi_krum_aggregator.py \
    $ROUND 0 "${ENTRIES%|}" 2>&1 | tee $LOG_DIR/p7_baseline_r${ROUND}.log

  # Distribuer le modèle global aux clients
  AGG_LOG=$(ls -t $LOG_DIR/p7_round$(printf "%02d" $ROUND)_*.json 2>/dev/null | head -1)
  if [ -n "$AGG_LOG" ]; then
    echo "  Distribution modèle global..."
    DIST_ARGS=""
    for CLIENT_ID in "${!VMS[@]}"; do
      IP="${VMS[$CLIENT_ID]}"
      DIST_ARGS="$DIST_ARGS ${CLIENT_ID}:${IP}"
    done
    python3 /tmp/distribute_global.py "$AGG_LOG" "$SSH_KEY" $DIST_ARGS
  fi

done

echo "=== Phase 7 baseline terminée ==="
