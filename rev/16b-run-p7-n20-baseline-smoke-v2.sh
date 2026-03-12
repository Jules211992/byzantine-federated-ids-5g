#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP=${MAP:-"$RUN_DIR/config/edges_map_20.txt"}
[ -f "$MAP" ] || { echo "ERROR: MAP introuvable: $MAP"; exit 1; }

ROUND=${ROUND:-1}
START_FABRIC=${START_FABRIC:-20000}
PEER_HOST=${PEER_HOST:-peer0.org1.example.com}
MSP=${MSP:-Org1MSP}

OUT_DIR="$RUN_DIR/p7_baseline/round$(printf "%02d" "$ROUND")"
mkdir -p "$OUT_DIR"/{client_logs,edge_logs}

echo "RUN_DIR=$RUN_DIR"
echo "MAP=$MAP"
echo "ROUND=$ROUND"
echo "START_FABRIC=$START_FABRIC"
echo "PEER_HOST=$PEER_HOST"
echo "MSP=$MSP"
echo

CIDS=()
IPS=()
while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  [ -z "${ip:-}" ] && continue
  CIDS+=("$cid")
  IPS+=("$ip")
done < "$MAP"

N=${#CIDS[@]}
[ "$N" -gt 0 ] || { echo "ERROR: MAP vide"; exit 1; }

echo "N_CLIENTS=$N"
echo

FAIL=0
OK=0

for ((i=0;i<N;i++)); do
  CID="${CIDS[$i]}"
  IP="${IPS[$i]}"
  FABRIC_ROUND=$((START_FABRIC + i))

  echo "===== $CID @ $IP FABRIC_ROUND=$FABRIC_ROUND ====="

  set +e
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$IP" "
set -euo pipefail
rm -f /opt/fl-client/models/${CID}_model.npz || true
/opt/fl-client/run_fl_round.sh ${CID} ${ROUND} ${MSP} ${PEER_HOST} ${FABRIC_ROUND} > /opt/fl-client/logs/runfl_${CID}_r${ROUND}.out 2>&1
" 
  RC=$?
  set -e

  echo "RC=$RC"

  set +e
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$IP":/opt/fl-client/logs/runfl_${CID}_r${ROUND}.out \
    "$OUT_DIR/client_logs/${CID}.runfl.out" >/dev/null 2>&1
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$IP":/opt/fl-client/logs/fl_client_${CID}_r${ROUND}.out \
    "$OUT_DIR/client_logs/${CID}.fl_client.out" >/dev/null 2>&1
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$IP":/opt/fl-client/logs/fl-ids-${CID}-r${ROUND}.json \
    "$OUT_DIR/client_logs/${CID}.json" >/dev/null 2>&1
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$IP":/opt/fl-client/logs/fl_fabric_${CID}_r${ROUND}.out \
    "$OUT_DIR/client_logs/${CID}.fl_fabric.out" >/dev/null 2>&1
  set -e

  if [ "$RC" -ne 0 ]; then
    FAIL=$((FAIL+1))
    echo "EDGE_FAIL $CID $IP" >> "$OUT_DIR/edge_logs/failures.txt"
  else
    OK=$((OK+1))
  fi

  echo
done

echo "SUMMARY OK=$OK FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && echo "OK: baseline smoke N=$N round=$ROUND" || { echo "ERROR: failures saved to $OUT_DIR/edge_logs/failures.txt"; exit 1; }
