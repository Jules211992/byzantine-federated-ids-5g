#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

CERT_SRC=$(ls -1 "$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/signcerts/"*.pem | head -n 1)
KEY_SRC=$(ls -1 "$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/users/User1@org1.example.com/msp/keystore/"* | head -n 1)

TARGETS=("$VM4_IP" "$VM5_IP")

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
EOS

for ip in "${TARGETS[@]}"; do
  echo
  echo "===== FIX IDENTITY on $ip ====="

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mkdir -p /opt/fl-client/crypto/identity/cert /opt/fl-client/crypto/identity/key
sudo chown -R ubuntu:ubuntu /opt/fl-client/crypto

CFG=/opt/fl-client/config.env
touch \"\$CFG\"
sed -i '/^CERT_PATH=/d; /^KEY_PATH=/d; /^ID_CERT_PATH=/d; /^ID_KEY_PATH=/d' \"\$CFG\"
echo 'ID_CERT_PATH=/opt/fl-client/crypto/identity/cert' >> \"\$CFG\"
echo 'ID_KEY_PATH=/opt/fl-client/crypto/identity/key' >> \"\$CFG\"

echo
echo '--- config.env (identity lines) ---'
grep -E '^(ID_CERT_PATH|ID_KEY_PATH)=' \"\$CFG\" | tail -n 20
"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$CERT_SRC" ubuntu@"$ip":/opt/fl-client/crypto/identity/cert/user1_org1.pem
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$KEY_SRC"  ubuntu@"$ip":/opt/fl-client/crypto/identity/key/user1_org1_sk

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no /tmp/run_fl_round.sh ubuntu@"$ip":/tmp/run_fl_round.sh
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mv /tmp/run_fl_round.sh /opt/fl-client/run_fl_round.sh
sudo chmod +x /opt/fl-client/run_fl_round.sh

echo
echo '--- identity cert subject ---'
openssl x509 -in /opt/fl-client/crypto/identity/cert/user1_org1.pem -noout -subject -issuer

echo
echo '--- run_fl_round.sh head ---'
sed -n '1,35p' /opt/fl-client/run_fl_round.sh
"
done

echo
echo "=== SMOKE TX from both edges (anti-rollback) ==="
BASE=9000

i=0
for ip in "${TARGETS[@]}"; do
  i=$((i+1))
  FAB=$((BASE+i))
  CLIENT_ID="edge-client-${i}"
  if [ "$ip" = "$VM4_IP" ]; then CLIENT_ID="edge-client-3"; fi
  if [ "$ip" = "$VM5_IP" ]; then CLIENT_ID="edge-client-4"; fi

  echo
  echo "----- TX $CLIENT_ID on $ip FABRIC_ROUND=$FAB -----"
  set +e
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" \
    "bash /opt/fl-client/run_fl_round.sh $CLIENT_ID 1 Org1MSP $PEER1_HOST $FAB | tail -n 80"
  RC=$?
  set -e
  echo "RC=$RC"
done

echo
echo "=== peer0.org1 logs (last 4 minutes) ==="
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$PEER1_IP" "
set -euo pipefail
docker logs peer0.org1.example.com --since 4m 2>&1 | tail -n 260 || true
" || true
