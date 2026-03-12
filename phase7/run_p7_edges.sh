#!/bin/bash
set -euo pipefail

MAP_FILE=${MAP_FILE:-/home/ubuntu/byz-fed-ids-5g/config/edges_map.txt}
SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
LOG_DIR=${LOG_DIR:-/home/ubuntu/byz-fed-ids-5g/phase7/logs}
N_ROUNDS=${N_ROUNDS:-10}
START_FABRIC=${START_FABRIC:-1000}

mkdir -p "$LOG_DIR"

if [ ! -f "$MAP_FILE" ]; then
  echo "Missing MAP_FILE: $MAP_FILE"
  exit 1
fi

if [ ! -f "$SSH_KEY" ]; then
  echo "Missing SSH_KEY: $SSH_KEY"
  exit 1
fi

EDGES=()
IPS=()

while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  [ -z "${ip:-}" ] && continue
  EDGES+=("$cid")
  IPS+=("$ip")
done < "$MAP_FILE"

if [ "${#EDGES[@]}" -lt 1 ]; then
  echo "No edges found in $MAP_FILE"
  exit 1
fi

echo "=== Phase 7 baseline edges=${#EDGES[@]} rounds=$N_ROUNDS ==="

for ROUND in $(seq 1 "$N_ROUNDS"); do
  echo ""
  echo "--- Round $ROUND ---"
  FABRIC_ROUND=$((START_FABRIC + ROUND - 1))

  for i in "${!EDGES[@]}"; do
    cid="${EDGES[$i]}"
    ip="${IPS[$i]}"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "ubuntu@$ip" \
      "ROUND=$ROUND START_ROUND=$FABRIC_ROUND bash /opt/fl-client/run_fl_round.sh $cid $ROUND Org1MSP peer0.org1.example.com $FABRIC_ROUND" &
  done
  wait

  ENTRIES=""
  for i in "${!EDGES[@]}"; do
    cid="${EDGES[$i]}"
    ip="${IPS[$i]}"
    LOG_PATH="/opt/fl-client/logs/fl-ids-${cid}-r${ROUND}.json"
    ENTRIES="${ENTRIES}${ip}:${LOG_PATH}:${cid}|"
  done

  SSH_KEY="$SSH_KEY" python3 /home/ubuntu/byz-fed-ids-5g/phase7/multi_krum_aggregator.py \
    "$ROUND" 0 "${ENTRIES%|}" 2>&1 | tee "$LOG_DIR/p7_edges_r${ROUND}.log"

  AGG_LOG=$(ls -t "${LOG_DIR}/p7_round$(printf "%02d" "$ROUND")_"*.json 2>/dev/null | head -1 || true)
  if [ -z "${AGG_LOG:-}" ]; then
    echo "[WARN] Aucun log agregateur trouvé pour round=$ROUND"
    continue
  fi

  echo "AGG_LOG=$AGG_LOG"

  DIST_ARGS=""
  for i in "${!EDGES[@]}"; do
    DIST_ARGS="${DIST_ARGS} ${EDGES[$i]}:${IPS[$i]}"
  done

  python3 /home/ubuntu/byz-fed-ids-5g/scripts/distribute_global.py "$AGG_LOG" "$SSH_KEY" $DIST_ARGS
done

echo "=== Phase 7 terminée ==="
