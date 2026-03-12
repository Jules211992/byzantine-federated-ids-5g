#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

cat <<'EOS' > /tmp/run_fl_round.sh
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

mkdir -p /opt/fl-client/logs

set +e
python3 /opt/fl-client/fl_ids_client.py > /opt/fl-client/logs/fl_client_${CLIENT_ID}_r${ROUND}.out 2>&1
RC_CLIENT=$?
set -e
[ $RC_CLIENT -ne 0 ] && { echo "[ERROR] fl_ids_client.py failed"; exit 1; }

RESULT_FILE="/opt/fl-client/logs/fl-ids-${CLIENT_ID}-r${ROUND}.json"

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

set +e
OUT=$(
  CLIENT_ID=$CLIENT_ID \
  ORG_MSP=$MSP \
  PEER_ADDR=${PEER}:7051 \
  CHANNEL=dtchannel \
  CHAINCODE=governance \
  START_ROUND=$FABRIC_ROUND \
  ROUNDS=1 \
  CERT_PATH=${CERT_PATH:-/opt/fl-client/crypto/tls/ca} \
  /opt/fl-client/fl-client-p5 2>&1
)
RC_FABRIC=$?
set -e

printf "%s\n" "$OUT" | tee /opt/fl-client/logs/fl_fabric_${CLIENT_ID}_r${ROUND}.out >/dev/null

echo "$OUT" | grep -q '\[ERROR\]' && exit 1
echo "$OUT" | grep -q 'done: 0/' && exit 1
[ $RC_FABRIC -ne 0 ] && exit $RC_FABRIC

echo "[${CLIENT_ID}] round=${ROUND} fabric_round=${FABRIC_ROUND} CID=${CID:0:16}... F1=${F1} FPR=${FPR} OK"
EOS

echo
echo "=== Patch run_fl_round.sh on edges ==="
for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "----- EDGE $ip -----"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mkdir -p /opt/fl-client/crypto/tls/ca
sudo chown -R ubuntu:ubuntu /opt/fl-client/crypto
touch /opt/fl-client/config.env
grep -q '^CERT_PATH=' /opt/fl-client/config.env \
  && sed -i 's|^CERT_PATH=.*|CERT_PATH=/opt/fl-client/crypto/tls/ca|' /opt/fl-client/config.env \
  || echo 'CERT_PATH=/opt/fl-client/crypto/tls/ca' >> /opt/fl-client/config.env
"
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/run_fl_round.sh ubuntu@"$ip":/tmp/run_fl_round.sh
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mv /tmp/run_fl_round.sh /opt/fl-client/run_fl_round.sh
sudo chmod +x /opt/fl-client/run_fl_round.sh
sed -n '1,25p' /opt/fl-client/run_fl_round.sh
"
done

echo
echo "=== Smoke test (round must be > last_round=3440) ==="
ROUND=1
FABRIC_ROUND=${FABRIC_ROUND:-5000}

set +e
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$VM2_IP" \
  "bash /opt/fl-client/run_fl_round.sh edge-client-1 $ROUND Org1MSP $PEER1_HOST $FABRIC_ROUND | tail -n 60"
RC=$?
set -e
echo "EDGE_RC=$RC"

echo
echo "=== peer0.org1 logs (last 3 min) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" "
set -euo pipefail
docker logs peer0.org1.example.com --since 3m 2>&1 | tail -n 220 || true
" || true
