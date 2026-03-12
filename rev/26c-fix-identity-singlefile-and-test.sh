#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}

fix_one() {
  local ip="$1"
  echo
  echo "=============================="
  echo "FIX identity single-file on $ip"
  echo "------------------------------"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail

echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
echo

CERT_DIR=/opt/fl-client/crypto/identity/cert
KEY_DIR=/opt/fl-client/crypto/identity/key

ls -la \"\$CERT_DIR\" || true
ls -la \"\$KEY_DIR\" || true
echo

CERT_FILE=\$(ls -1 \"\$CERT_DIR\"/*.pem 2>/dev/null | grep -i 'User1@org1' | head -n 1 || true)
[ -z \"\$CERT_FILE\" ] && CERT_FILE=\$(ls -1 \"\$CERT_DIR\"/*.pem 2>/dev/null | head -n 1 || true)

KEY_FILE=\$(ls -1 \"\$KEY_DIR\"/* 2>/dev/null | grep -E 'priv_sk$|_sk$' | head -n 1 || true)
[ -z \"\$KEY_FILE\" ] && KEY_FILE=\$(ls -1 \"\$KEY_DIR\"/* 2>/dev/null | head -n 1 || true)

echo CERT_FILE=\$CERT_FILE
echo KEY_FILE=\$KEY_FILE
[ -n \"\$CERT_FILE\" ] || { echo 'ERROR: no cert file found'; exit 2; }
[ -n \"\$KEY_FILE\" ]  || { echo 'ERROR: no key file found'; exit 2; }

CERT_ONE=/opt/fl-client/crypto/identity/cert_one
KEY_ONE=/opt/fl-client/crypto/identity/key_one
mkdir -p \"\$CERT_ONE\" \"\$KEY_ONE\"
rm -f \"\$CERT_ONE\"/* \"\$KEY_ONE\"/*

cp -f \"\$CERT_FILE\" \"\$CERT_ONE/cert.pem\"
cp -f \"\$KEY_FILE\"  \"\$KEY_ONE/key.pem\"
chmod 644 \"\$CERT_ONE/cert.pem\"
chmod 600 \"\$KEY_ONE/key.pem\"

sed -i 's|^ID_CERT_PATH=.*|ID_CERT_PATH=/opt/fl-client/crypto/identity/cert_one|' /opt/fl-client/config.env || true
sed -i 's|^ID_KEY_PATH=.*|ID_KEY_PATH=/opt/fl-client/crypto/identity/key_one|'  /opt/fl-client/config.env || true

echo
echo '--- config.env (identity) ---'
grep -E 'ID_CERT_PATH|ID_KEY_PATH' /opt/fl-client/config.env || true

echo
echo '--- cert_one/key_one listing ---'
ls -la \"\$CERT_ONE\"
ls -la \"\$KEY_ONE\"

echo
echo '--- openssl subject ---'
openssl x509 -noout -subject -in \"\$CERT_ONE/cert.pem\" || true
"
}

test_one() {
  local ip="$1"
  local cid="$2"
  local fab="$3"

  echo
  echo "=============================="
  echo "TEST $cid @ $ip FABRIC_ROUND=$fab"
  echo "------------------------------"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')
grep -E 'CERT_PATH|ID_CERT_PATH|ID_KEY_PATH' /opt/fl-client/config.env || true
echo

set +e
timeout 180 /opt/fl-client/run_fl_round.sh $cid 1 Org1MSP peer0.org1.example.com $fab
RC=\$?
set -e
echo RC=\$RC
echo

F=/opt/fl-client/logs/fl_fabric_${cid}_r1.out
if [ -f \"\$F\" ]; then
  ls -lh \"\$F\"
  tail -n 140 \"\$F\"
else
  echo 'MISSING fl_fabric log: '\$F
fi

exit \$RC
"
}

fix_one "$VM2_IP"
fix_one "$VM3_IP"

test_one "$VM2_IP" "edge-client-1" "72100" || true
test_one "$VM2_IP" "edge-client-2" "72101" || true
test_one "$VM3_IP" "edge-client-6" "72102" || true
test_one "$VM3_IP" "edge-client-7" "72103" || true

echo
echo "DONE"
