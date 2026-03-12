#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

cat <<'RUNFL' > /tmp/run_fl_round.sh
#!/bin/bash
set -euo pipefail

CLIENT_ID=${1:?}
ROUND=${2:?}
MSP=${3:?}
PEER=${4:?}
FABRIC_ROUND=${5:?}

if [ -f /opt/fl-client/config.env ]; then
  set -a
  . /opt/fl-client/config.env
  set +a
fi

export IPFS_PATH=/home/ubuntu/.ipfs
export CLIENT_ID ROUND

ATTACK_MODE=${ATTACK_MODE:-}
BYZ_CLIENTS=${BYZ_CLIENTS:-}

mkdir -p /opt/fl-client/logs

IS_BYZ=0
for c in $BYZ_CLIENTS; do
  if [ "$c" = "$CLIENT_ID" ]; then
    IS_BYZ=1
    break
  fi
done

set +e
if [ "$IS_BYZ" -eq 1 ] && [ -n "$ATTACK_MODE" ]; then
  BYZ_TYPE="$ATTACK_MODE" python3 /opt/fl-client/fl_ids_byzantine.py > /opt/fl-client/logs/fl_client_${CLIENT_ID}_r${ROUND}.out 2>&1
  RC_CLIENT=$?
  RESULT_FILE="/opt/fl-client/logs/fl-byz-${CLIENT_ID}-r${ROUND}.json"
else
  python3 /opt/fl-client/fl_ids_client.py > /opt/fl-client/logs/fl_client_${CLIENT_ID}_r${ROUND}.out 2>&1
  RC_CLIENT=$?
  RESULT_FILE="/opt/fl-client/logs/fl-ids-${CLIENT_ID}-r${ROUND}.json"
fi
set -e

[ $RC_CLIENT -ne 0 ] && { echo "[ERROR] fl client python failed"; exit 1; }
[ -f "$RESULT_FILE" ] || { echo "[ERROR] result file missing: $RESULT_FILE"; exit 1; }

CID=$(python3 - "$RESULT_FILE" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
print(j.get("cid",""))
PY
)

F1=$(python3 - "$RESULT_FILE" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
print(j.get("test_metrics",{}).get("f1",""))
PY
)

FPR=$(python3 - "$RESULT_FILE" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]))
print(j.get("test_metrics",{}).get("fpr",""))
PY
)

CERT_DIR=${ID_CERT_PATH:-/opt/fl-client/crypto/identity/cert}
KEY_DIR=${ID_KEY_PATH:-/opt/fl-client/crypto/identity/key}

set +e
OUT=$(
  CLIENT_ID=$CLIENT_ID \
  ORG_MSP=$MSP \
  PEER_ADDR=${PEER}:7051 \
  CHANNEL=dtchannel \
  CHAINCODE=governance \
  START_ROUND=$FABRIC_ROUND \
  ROUNDS=1 \
  CERT_PATH=$CERT_DIR \
  KEY_PATH=$KEY_DIR \
  /opt/fl-client/fl-client-p5 2>&1
)
RC_FABRIC=$?
set -e

printf "%s\n" "$OUT" | tee /opt/fl-client/logs/fl_fabric_${CLIENT_ID}_r${ROUND}.out >/dev/null

echo "$OUT" | grep -q '\[ERROR\]' && exit 1
echo "$OUT" | grep -q 'done: 0/' && exit 1
[ $RC_FABRIC -ne 0 ] && exit $RC_FABRIC

echo "[${CLIENT_ID}] round=${ROUND} fabric_round=${FABRIC_ROUND} CID=${CID:0:16}... F1=${F1} FPR=${FPR} OK"
RUNFL

for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  echo
  echo "================ PATCH run_fl_round on $ip ================"
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/run_fl_round.sh ubuntu@"$ip":/tmp/run_fl_round.sh >/dev/null
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    cp /opt/fl-client/run_fl_round.sh /opt/fl-client/run_fl_round.sh.bak_$(date -u +%Y%m%d_%H%M%S)
    mv /tmp/run_fl_round.sh /opt/fl-client/run_fl_round.sh
    chmod +x /opt/fl-client/run_fl_round.sh
    sed -n "1,220p" /opt/fl-client/run_fl_round.sh
  '
done
