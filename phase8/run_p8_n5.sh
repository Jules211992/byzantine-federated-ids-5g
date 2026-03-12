#!/bin/bash
set -euo pipefail

SSH_KEY=~/.ssh/fl-ids-key.pem
SPLITS_DIR=/home/ubuntu/byz-fed-ids-5g/phase6/splits
LOG_DIR=/home/ubuntu/byz-fed-ids-5g/phase8/logs
AGG_LOG=/home/ubuntu/byz-fed-ids-5g/phase8/logs
mkdir -p $LOG_DIR /tmp/fl_models_byz

declare -A VMS=(
  [edge-client-1]=10.10.0.112
  [edge-client-2]=10.10.0.11
  [edge-client-3]=10.10.0.121
  [edge-client-4]=10.10.0.10
)

BYZ_TYPE=${BYZ_TYPE:-label_flip}
N_ROUNDS=${N_ROUNDS:-5}
START_FABRIC=${START_FABRIC:-200}

echo "=== Phase 8 N=5 f=1 BYZ_TYPE=$BYZ_TYPE rounds=$N_ROUNDS ==="

for ROUND in $(seq 1 $N_ROUNDS); do
  echo ""
  echo "--- Round $ROUND ---"
  FABRIC_ROUND=$((START_FABRIC + ROUND - 1))

  for CLIENT_ID in "${!VMS[@]}"; do
    IP="${VMS[$CLIENT_ID]}"
    echo "  Lancement $CLIENT_ID sur $IP..."
    ssh -i $SSH_KEY ubuntu@$IP \
      "ROUND=$ROUND START_ROUND=$FABRIC_ROUND bash /opt/fl-client/run_fl_round.sh \
       $CLIENT_ID $ROUND Org1MSP peer0.org1.example.com $FABRIC_ROUND" &
  done

  echo "  Lancement edge-client-5-byz (local)..."
  ROUND=$ROUND \
  BYZ_TYPE=$BYZ_TYPE \
  CLIENT_ID=edge-client-5-byz \
  SPLITS_DIR=$SPLITS_DIR \
  MODEL_DIR=/tmp/fl_models_byz \
  python3 /home/ubuntu/byz-fed-ids-5g/phase8/fl_ids_byzantine_c5.py > \
    $LOG_DIR/mk_${BYZ_TYPE}_c5byz_r${ROUND}.log 2>&1 &

  wait
  echo "  Tous les clients terminés round $ROUND"

  ENTRIES=""
  for CLIENT_ID in "${!VMS[@]}"; do
    IP="${VMS[$CLIENT_ID]}"
    LOG_PATH="/opt/fl-client/logs/fl-ids-${CLIENT_ID}-r${ROUND}.json"
    ENTRIES="${ENTRIES}${IP}:${LOG_PATH}:${CLIENT_ID}|"
  done
  BYZ_LOG="$LOG_DIR/mk_${BYZ_TYPE}_c5byz_r${ROUND}.log"
  BYZ_CID=$(python3 -c "import json; d=json.load(open('${LOG_DIR}/fl-byz-edge-client-5-byz-r${ROUND}.json')); print(d['cid'])")
  BYZ_HASH=$(python3 -c "import json; d=json.load(open('${LOG_DIR}/fl-byz-edge-client-5-byz-r${ROUND}.json')); print(d['hash'])")

  BYZ_LOG_JSON="$LOG_DIR/fl-byz-edge-client-5-byz-r${ROUND}.json"
  ENTRIES="${ENTRIES}local:${BYZ_LOG_JSON}:edge-client-5-byz"

  SSH_KEY=$SSH_KEY \
  python3 /home/ubuntu/byz-fed-ids-5g/phase7/multi_krum_aggregator.py \
    $ROUND 1 "$ENTRIES" 2>&1 | tee $AGG_LOG/mk_${BYZ_TYPE}_agg_r${ROUND}.log

  # Distribuer le modèle global aux clients honnêtes
  AGG_JSON=$(ls -t /home/ubuntu/byz-fed-ids-5g/phase7/logs/p7_round$(printf "%02d" $ROUND)_*.json 2>/dev/null | head -1)
  if [ -n "$AGG_JSON" ]; then
    echo "  Distribution modèle global..."
    DIST_ARGS=""
    for CLIENT_ID in "${!VMS[@]}"; do
      IP="${VMS[$CLIENT_ID]}"
      DIST_ARGS="$DIST_ARGS ${CLIENT_ID}:${IP}"
    done
    python3 /home/ubuntu/byz-fed-ids-5g/scripts/distribute_global.py "$AGG_JSON" "$SSH_KEY" $DIST_ARGS
  fi

done

echo ""
echo "=== Phase 8 terminée ==="
