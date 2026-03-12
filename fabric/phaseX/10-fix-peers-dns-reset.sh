set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BLOCK_LOCAL=~/byz-fed-ids-5g/fabric/artifacts/dtchannel.block
BLOCK_REMOTE=/opt/fabric/dtchannel.block

for ip in "$VM9_IP" "$VM10_IP"; do
  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$BLOCK_LOCAL" "ubuntu@${ip}:${BLOCK_REMOTE}"
done

run_remote() {
  local ip="$1"
  local self_peer="$2"
  local org_domain="$3"
  local msp="$4"
  local boot_peer="$5"
  local self_ip="$6"
  local boot_ip="$7"
  local o1="$8"
  local o2="$9"
  local o3="${10}"

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "ubuntu@${ip}" bash -s -- \
    "$self_peer" "$org_domain" "$msp" "$boot_peer" "$self_ip" "$boot_ip" "$o1" "$o2" "$o3" "$BLOCK_REMOTE" <<'REMOTE'
set -euo pipefail

self_peer="$1"
org_domain="$2"
msp="$3"
boot_peer="$4"
self_ip="$5"
boot_ip="$6"
o1="$7"
o2="$8"
o3="$9"
block="${10}"

dc() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi
  echo "docker compose / docker-compose introuvable" >&2
  exit 1
}

begin="### BEGIN BYZ-FED-IDS FABRIC HOSTS"
end="### END BYZ-FED-IDS FABRIC HOSTS"

tmp="$(mktemp)"
sudo cat /etc/hosts > "$tmp"

awk -v b="$begin" -v e="$end" '
  $0==b {skip=1; next}
  $0==e {skip=0; next}
  !skip {print}
' "$tmp" > "${tmp}.clean"

{
  cat "${tmp}.clean"
  echo "$begin"
  echo "${self_ip} ${self_peer} ${org_domain}"
  echo "${boot_ip} ${boot_peer}"
  echo "${o1} orderer1.example.com"
  echo "${o2} orderer2.example.com"
  echo "${o3} orderer3.example.com"
  echo "$end"
} > "${tmp}.new"

sudo install -m 0644 "${tmp}.new" /etc/hosts

if command -v resolvectl >/dev/null 2>&1; then
  sudo resolvectl flush-caches || true
fi
if systemctl is-active systemd-resolved >/dev/null 2>&1; then
  sudo systemctl restart systemd-resolved || true
fi

compose_file=""

for root in /opt/fabric "$HOME"; do
  [ -d "$root" ] || continue
  while IFS= read -r f; do
    if dc -f "$f" config --services >/dev/null 2>&1; then
      if dc -f "$f" config --services | grep -qx "$self_peer"; then
        compose_file="$f"
        break
      fi
    fi
  done < <(find "$root" -maxdepth 6 -type f \( -name docker-compose.yml -o -name docker-compose.yaml -o -name compose.yml -o -name compose.yaml \) 2>/dev/null | sort)
  [ -n "$compose_file" ] && break
done

if [ -z "$compose_file" ]; then
  if [ -f /opt/fabric/docker-compose.yml ]; then compose_file=/opt/fabric/docker-compose.yml; fi
  if [ -z "$compose_file" ] && [ -f /opt/fabric/docker-compose.yaml ]; then compose_file=/opt/fabric/docker-compose.yaml; fi
fi

if [ -z "$compose_file" ]; then
  echo "docker-compose.yml introuvable pour ${self_peer}" >&2
  exit 1
fi

cd "$(dirname "$compose_file")"
dc -f "$compose_file" up -d

peer_container="$(docker ps --format '{{.Names}}' | grep -m1 -F "$self_peer" || true)"
if [ -n "$peer_container" ]; then
  docker exec "$peer_container" bash -lc "command -v peer >/dev/null 2>&1 && (peer channel list 2>/dev/null | grep -q '^dtchannel$' || peer channel join -b '$block')" || true
fi

getent hosts orderer1.example.com || true
getent hosts orderer2.example.com || true
getent hosts orderer3.example.com || true
REMOTE
}

run_remote "$VM9_IP"  "peer0.org1.example.com" "org1.example.com" "Org1MSP" "peer0.org2.example.com" "$VM9_IP"  "$VM10_IP" "$VM6_IP" "$VM7_IP" "$VM8_IP"
run_remote "$VM10_IP" "peer0.org2.example.com" "org2.example.com" "Org2MSP" "peer0.org1.example.com" "$VM10_IP" "$VM9_IP"  "$VM6_IP" "$VM7_IP" "$VM8_IP"
