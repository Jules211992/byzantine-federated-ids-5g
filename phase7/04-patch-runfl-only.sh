#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== PATCH $ip ====="

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail

sudo mkdir -p /opt/fl-client/crypto/tls/ca
sudo chown -R ubuntu:ubuntu /opt/fl-client/crypto

CFG=/opt/fl-client/config.env
touch \"\$CFG\"
grep -q '^CERT_PATH=' \"\$CFG\" \
  && sed -i 's|^CERT_PATH=.*|CERT_PATH=/opt/fl-client/crypto/tls/ca|' \"\$CFG\" \
  || echo 'CERT_PATH=/opt/fl-client/crypto/tls/ca' >> \"\$CFG\"

cat > /opt/fl-client/run_fl_round.sh <<'EOS'
#!/bin/bash
set -euo pipefail

CLIENT_ID=\${1:?}
ROUND=\${2:?}
MSP=\${3:?}
PEER=\${4:?}
FABRIC_ROUND=\${5:?}

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
[ $RC_CLIENT -ne 0 ] && { echo '[ERROR] fl_ids_client.py failed'; exit 1; }

RESULT_FILE=/opt/fl-client/logs/fl-ids-\${CLIENT_ID}-r\${ROUND}.json
CID=\$(python3 -c \"import json; d=json.load(open('$RESULT_FILE')); print(d.get('cid',''))\")
F1=\$(python3 -c \"import json; d=json.load(open('$RESULT_FILE')); print(d.get('test_metrics',{}).get('f1',''))\")
FPR=\$(python3 -c \"import json; d=json.load(open('$RESULT_FILE')); print(d.get('test_metrics',{}).get('fpr',''))\")

set +e
OUT=\$(
  CLIENT_ID=\$CLIENT_ID \
  ORG_MSP=\$MSP \
  PEER_ADDR=\${PEER}:7051 \
  CHANNEL=dtchannel \
  CHAINCODE=governance \
  START_ROUND=\$FABRIC_ROUND \
  ROUNDS=1 \
  CERT_PATH=\${CERT_PATH:-/opt/fl-client/crypto/tls/ca} \
  /opt/fl-client/fl-client-p5 2>&1
)
RC_FABRIC=$?
set -e

echo \"\$OUT\" | tee /opt/fl-client/logs/fl_fabric_${CLIENT_ID}_r${ROUND}.out >/dev/null

echo \"\$OUT\" | grep -q '\\[ERROR\\]' && exit 1
echo \"\$OUT\" | grep -q 'done: 0/' && exit 1
[ $RC_FABRIC -ne 0 ] && exit $RC_FABRIC

echo \"[\${CLIENT_ID}] round=\${ROUND} fabric_round=\${FABRIC_ROUND} CID=\${CID:0:16}... F1=\${F1} FPR=\${FPR} OK\"
EOS

chmod +x /opt/fl-client/run_fl_round.sh

echo
echo '--- run_fl_round.sh (first 40 lines) ---'
sed -n '1,40p' /opt/fl-client/run_fl_round.sh
echo
echo '--- config.env (CERT_PATH line) ---'
grep -E '^(CERT_PATH=)' /opt/fl-client/config.env | tail -n 5
"
done
