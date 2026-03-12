set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BASE="$HOME/byz-fed-ids-5g/fabric"
CFG="$BASE/config"
ART="$BASE/artifacts"

rm -rf "$BASE/crypto-config" "$ART"
mkdir -p "$CFG" "$ART"

cat > "$CFG/crypto-config.yaml" << 'EOC'
OrdererOrgs:
  - Name: Orderer
    Domain: example.com
    EnableNodeOUs: true
    Specs:
      - Hostname: orderer1
      - Hostname: orderer2
      - Hostname: orderer3
PeerOrgs:
  - Name: Org1
    Domain: org1.example.com
    EnableNodeOUs: true
    Template:
      Count: 1
    Users:
      Count: 1
  - Name: Org2
    Domain: org2.example.com
    EnableNodeOUs: true
    Template:
      Count: 1
    Users:
      Count: 1
EOC

cat > "$CFG/configtx.yaml" << 'EOT'
Organizations:
  - &OrdererOrg
    Name: OrdererOrg
    ID: OrdererMSP
    MSPDir: crypto-config/ordererOrganizations/example.com/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"
      Writers:
        Type: Signature
        Rule: "OR('OrdererMSP.member')"
      Admins:
        Type: Signature
        Rule: "OR('OrdererMSP.admin')"

  - &Org1
    Name: Org1MSP
    ID: Org1MSP
    MSPDir: crypto-config/peerOrganizations/org1.example.com/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('Org1MSP.admin','Org1MSP.peer','Org1MSP.client')"
      Writers:
        Type: Signature
        Rule: "OR('Org1MSP.admin','Org1MSP.client')"
      Admins:
        Type: Signature
        Rule: "OR('Org1MSP.admin')"
      Endorsement:
        Type: Signature
        Rule: "OR('Org1MSP.peer')"
    AnchorPeers:
      - Host: peer0.org1.example.com
        Port: 7051

  - &Org2
    Name: Org2MSP
    ID: Org2MSP
    MSPDir: crypto-config/peerOrganizations/org2.example.com/msp
    Policies:
      Readers:
        Type: Signature
        Rule: "OR('Org2MSP.admin','Org2MSP.peer','Org2MSP.client')"
      Writers:
        Type: Signature
        Rule: "OR('Org2MSP.admin','Org2MSP.client')"
      Admins:
        Type: Signature
        Rule: "OR('Org2MSP.admin')"
      Endorsement:
        Type: Signature
        Rule: "OR('Org2MSP.peer')"
    AnchorPeers:
      - Host: peer0.org2.example.com
        Port: 7051

Capabilities:
  Channel: &ChannelCapabilities
    V2_0: true
  Orderer: &OrdererCapabilities
    V2_0: true
  Application: &ApplicationCapabilities
    V2_0: true

Application:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    LifecycleEndorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"
    Endorsement:
      Type: ImplicitMeta
      Rule: "MAJORITY Endorsement"
  Capabilities: *ApplicationCapabilities

Orderer:
  OrdererType: etcdraft
  Addresses:
    - orderer1.example.com:7050
    - orderer2.example.com:7050
    - orderer3.example.com:7050
  BatchTimeout: 1s
  BatchSize:
    MaxMessageCount: 200
    AbsoluteMaxBytes: 99 MB
    PreferredMaxBytes: 512 KB
  EtcdRaft:
    Consenters:
      - Host: orderer1.example.com
        Port: 7050
        ClientTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer1.example.com/tls/server.crt
        ServerTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer1.example.com/tls/server.crt
      - Host: orderer2.example.com
        Port: 7050
        ClientTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer2.example.com/tls/server.crt
        ServerTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer2.example.com/tls/server.crt
      - Host: orderer3.example.com
        Port: 7050
        ClientTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer3.example.com/tls/server.crt
        ServerTLSCert: crypto-config/ordererOrganizations/example.com/orderers/orderer3.example.com/tls/server.crt
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
    BlockValidation:
      Type: ImplicitMeta
      Rule: "ANY Writers"
  Capabilities: *OrdererCapabilities

Channel:
  Policies:
    Readers:
      Type: ImplicitMeta
      Rule: "ANY Readers"
    Writers:
      Type: ImplicitMeta
      Rule: "ANY Writers"
    Admins:
      Type: ImplicitMeta
      Rule: "MAJORITY Admins"
  Capabilities: *ChannelCapabilities

Profiles:
  DTChannel:
    Capabilities: *ChannelCapabilities
    Orderer:
      <<: *Orderer
      Organizations:
        - *OrdererOrg
    Application:
      <<: *Application
      Organizations:
        - *Org1
        - *Org2
EOT

docker run --rm \
  --network host \
  -v /etc/hosts:/etc/hosts:ro \
  -v "$BASE:/work" \
  -w /work \
  hyperledger/fabric-tools:2.5 \
  bash -lc '
set -e
export FABRIC_CFG_PATH=/work/config
cryptogen generate --config=/work/config/crypto-config.yaml --output=/work/crypto-config
configtxgen -profile DTChannel -channelID dtchannel -outputBlock /work/artifacts/dtchannel.block
configtxgen -profile DTChannel -channelID dtchannel -outputAnchorPeersUpdate /work/artifacts/Org1MSPanchors.tx -asOrg Org1MSP
configtxgen -profile DTChannel -channelID dtchannel -outputAnchorPeersUpdate /work/artifacts/Org2MSPanchors.tx -asOrg Org2MSP
'

test -s "$ART/dtchannel.block"
test -s "$ART/Org1MSPanchors.tx"
test -s "$ART/Org2MSPanchors.tx"

ls -lh "$ART/dtchannel.block" "$ART/Org1MSPanchors.tx" "$ART/Org2MSPanchors.tx"
echo OK_P3_GEN
