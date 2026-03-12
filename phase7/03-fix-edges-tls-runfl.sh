#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env
source ~/byz-fed-ids-5g/config/fabric_nodes.env

ORG1_PEER0_CA="$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_PEER0_CA="$HOME/byz-fed-ids-5g/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  echo
  echo "===== EDGE $ip ====="

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
sudo mkdir -p /opt/fl-client/crypto/tls/ca
sudo chown -R ubuntu:ubuntu /opt/fl-client/crypto

cat > /opt/fl-client/config.env <<'EOC'
CERT_PATH=/opt/fl-client/crypto/tls/ca
EOC
"

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$ORG1_PEER0_CA" ubuntu@"$ip":/opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$ORG2_PEER0_CA" ubuntu@"$ip":/opt/fl-client/crypto/tls/ca/org2_peer0_ca.crt

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
cp -f /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt /opt/fl-client/crypto/tls/ca/ca.crt
cat /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt /opt/fl-client/crypto/tls/ca/org2_peer0_ca.crt > /opt/fl-client/crypto/tls/ca/bundle.crt
ls -la /opt/fl-client/crypto/tls/ca | sed -n '1,120p'

echo
echo 'TLS smoke (openssl to peer0.org1 using org1_peer0_ca.crt)'
set +e
echo | openssl s_client -connect $PEER1_HOST:7051 -servername $PEER1_HOST -CAfile /opt/fl-client/crypto/tls/ca/org1_peer0_ca.crt >/dev/null 2>&1
rc=\$?
set -e
echo RC=\$rc
"
done

for ip in "$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP"; do
  echo
  echo "===== PATCH run_fl_round.sh on $ip ====="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
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

python3 /opt/fl-client/fl_ids_client.py

RESULT_FILE="/opt/fl-client/logs/fl-ids-\${CLIENT_ID}-r\${ROUND}.json"
CID=\$(python3 -c "import json; d=json.load(open('$RESULT_FILE')); print(d.get('cid',''))")
F1=\$(python3 -c "import json; d=json.load(open('$RESULT_FILE')); print(d.get('test_metrics',{}).get('f1',''))")
FPR=\$(python3 -c "import json; d=json.load(open('$RESULT_FILE')); print(d.get('test_metrics',{}).get('fpr',''))")

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
RC=\$?
set -e

echo "\$OUT"

echo "\$OUT" | grep -q '\[ERROR\]' && exit 1
[ \$RC -ne 0 ] && exit \$RC

echo "[\${CLIENT_ID}] round=\${ROUND} fabric_round=\${FABRIC_ROUND} CID=\${CID:0:16}... F1=\${F1} FPR=\${FPR} OK"
EOS

chmod +x /opt/fl-client/run_fl_round.sh
sed -n '1,60p' /opt/fl-client/run_fl_round.sh
"
done
