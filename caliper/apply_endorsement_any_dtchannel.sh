#!/usr/bin/env bash
set -euo pipefail

source ~/byz-fed-ids-5g/config/config.env

CHANNEL="dtchannel"
ORDERER_ADDR="orderer1.example.com:7050"
ORDERER_HOST="orderer1.example.com"

WORKDIR="/opt/fabric/verify-channel"
CAFILE="/opt/fabric/crypto-config/ordererOrganizations/example.com/msp/tlscacerts/tlsca.example.com-cert.pem"

ORG1_MSP="/opt/fabric/crypto-config/peerOrganizations/org1.example.com/users/Admin@org1.example.com/msp"
ORG2_MSP="/opt/fabric/crypto-config/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp"

ORG1_TLS="/opt/fabric/crypto-config/peerOrganizations/org1.example.com/peers/peer0.org1.example.com/tls/ca.crt"
ORG2_TLS="/opt/fabric/crypto-config/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${VM9_IP}" bash -s <<REMOTE
set -euo pipefail

CHANNEL="${CHANNEL}"
ORDERER_ADDR="${ORDERER_ADDR}"
ORDERER_HOST="${ORDERER_HOST}"

WORKDIR="${WORKDIR}"
CAFILE="${CAFILE}"

ORG1_MSP="${ORG1_MSP}"
ORG2_MSP="${ORG2_MSP}"

ORG1_TLS="${ORG1_TLS}"
ORG2_TLS="${ORG2_TLS}"

UIDGID="\$(id -u):\$(id -g)"

sudo mkdir -p "\$WORKDIR"
sudo chown -R "\$(id -u):\$(id -g)" "\$WORKDIR"

test -f "\$CAFILE"
test -d "\$ORG1_MSP"
test -d "\$ORG2_MSP"
test -f "\$ORG1_TLS"
test -f "\$ORG2_TLS"

echo "Fetching current config block..."
docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE="\$ORG1_TLS" \
  -e CORE_PEER_MSPCONFIGPATH="\$ORG1_MSP" \
  hyperledger/fabric-tools:2.5 \
  peer channel fetch config "\$WORKDIR/config_block.pb" -c "\$CHANNEL" \
    --orderer "\$ORDERER_ADDR" \
    --ordererTLSHostnameOverride "\$ORDERER_HOST" \
    --tls \
    --cafile "\$CAFILE" >/dev/null

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_decode --input "\$WORKDIR/config_block.pb" --type common.Block \
  > "\$WORKDIR/config_block.json"

python3 - <<'PY'
import json
blk=json.load(open("/opt/fabric/verify-channel/config_block.json"))
cfg=blk["data"]["data"][0]["payload"]["data"]["config"]
json.dump(cfg, open("/opt/fabric/verify-channel/config.json","w"), indent=2)
pol=cfg["channel_group"]["groups"]["Application"]["policies"]["Endorsement"]["policy"]
print("BEFORE Application.Endorsement rule:", pol.get("value",{}).get("rule"))
PY

python3 - <<'PY'
import json
cfg=json.load(open("/opt/fabric/verify-channel/config.json"))
pol=cfg["channel_group"]["groups"]["Application"]["policies"]["Endorsement"]["policy"]
pol.setdefault("value",{})["rule"]="ANY"
json.dump(cfg, open("/opt/fabric/verify-channel/config_any.json","w"), indent=2)
print("Patched Application.Endorsement rule -> ANY")
PY

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_encode --input "\$WORKDIR/config.json" --type common.Config \
  > "\$WORKDIR/config.pb"

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_encode --input "\$WORKDIR/config_any.json" --type common.Config \
  > "\$WORKDIR/config_any.pb"

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator compute_update --channel_id "\$CHANNEL" \
    --original "\$WORKDIR/config.pb" \
    --updated "\$WORKDIR/config_any.pb" \
  > "\$WORKDIR/config_update.pb"

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_decode --input "\$WORKDIR/config_update.pb" --type common.ConfigUpdate \
  > "\$WORKDIR/config_update.json"

python3 - <<PY
import json
upd=json.load(open("/opt/fabric/verify-channel/config_update.json"))
env={"payload":{"header":{"channel_header":{"channel_id":"$CHANNEL","type":2}},"data":{"config_update":upd}}}
json.dump(env, open("/opt/fabric/verify-channel/config_update_envelope.json","w"), indent=2)
print("Envelope JSON ready")
PY

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_encode --input "\$WORKDIR/config_update_envelope.json" --type common.Envelope \
  > "\$WORKDIR/config_update_envelope.pb"

echo "Signing with Org1 admin..."
docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_MSPCONFIGPATH="\$ORG1_MSP" \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE="\$ORG1_TLS" \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  hyperledger/fabric-tools:2.5 \
  peer channel signconfigtx -f "\$WORKDIR/config_update_envelope.pb" >/dev/null

echo "Signing with Org2 admin..."
docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_LOCALMSPID=Org2MSP \
  -e CORE_PEER_MSPCONFIGPATH="\$ORG2_MSP" \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_TLS_ROOTCERT_FILE="\$ORG2_TLS" \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  hyperledger/fabric-tools:2.5 \
  peer channel signconfigtx -f "\$WORKDIR/config_update_envelope.pb" >/dev/null

echo "Submitting channel config update..."
docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE="\$ORG1_TLS" \
  -e CORE_PEER_MSPCONFIGPATH="\$ORG1_MSP" \
  hyperledger/fabric-tools:2.5 \
  peer channel update -f "\$WORKDIR/config_update_envelope.pb" -c "\$CHANNEL" \
    --orderer "\$ORDERER_ADDR" \
    --ordererTLSHostnameOverride "\$ORDERER_HOST" \
    --tls \
    --cafile "\$CAFILE" >/dev/null

echo "Re-fetching config to verify..."
docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  -e CORE_PEER_TLS_ENABLED=true \
  -e CORE_PEER_LOCALMSPID=Org1MSP \
  -e CORE_PEER_ADDRESS=peer0.org1.example.com:7051 \
  -e CORE_PEER_TLS_ROOTCERT_FILE="\$ORG1_TLS" \
  -e CORE_PEER_MSPCONFIGPATH="\$ORG1_MSP" \
  hyperledger/fabric-tools:2.5 \
  peer channel fetch config "\$WORKDIR/config_block_after.pb" -c "\$CHANNEL" \
    --orderer "\$ORDERER_ADDR" \
    --ordererTLSHostnameOverride "\$ORDERER_HOST" \
    --tls \
    --cafile "\$CAFILE" >/dev/null

docker run --rm --network host --user "\$UIDGID" \
  -v /opt/fabric:/opt/fabric \
  hyperledger/fabric-tools:2.5 \
  configtxlator proto_decode --input "\$WORKDIR/config_block_after.pb" --type common.Block \
  > "\$WORKDIR/config_block_after.json"

python3 - <<'PY'
import json
blk=json.load(open("/opt/fabric/verify-channel/config_block_after.json"))
cfg=blk["data"]["data"][0]["payload"]["data"]["config"]
pol=cfg["channel_group"]["groups"]["Application"]["policies"]["Endorsement"]["policy"]
print("AFTER Application.Endorsement rule:", pol.get("value",{}).get("rule"))
PY

echo "DONE"
REMOTE
