#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

IPS="127.0.0.1 $VM2_IP $VM3_IP $VM9_IP $VM10_IP"

echo "===== STEP 1: FIND FABRIC HOST ====="
for ip in $IPS; do
  echo
  echo "========== HOST $ip =========="
  if [ "$ip" = "127.0.0.1" ]; then
    bash -lc '
      echo "--- docker ps ---"
      docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" || true
      echo
      echo "--- fabric match ---"
      docker ps --format "{{.Names}} {{.Image}}" | grep -Ei "peer|orderer|cli|governance|dev-peer|ccaas" || true
    '
  else
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
      echo "--- docker ps ---"
      docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" || true
      echo
      echo "--- fabric match ---"
      docker ps --format "{{.Names}} {{.Image}}" | grep -Ei "peer|orderer|cli|governance|dev-peer|ccaas" || true
    '
  fi
done

echo
echo "===== STEP 2: TRY COMMON FABRIC DIRECTORIES ON REMOTE HOSTS ====="
for ip in $VM2_IP $VM3_IP $VM9_IP $VM10_IP; do
  echo
  echo "========== SEARCH ON $ip =========="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set +e
    find ~ -maxdepth 3 \( -iname "*fabric*" -o -iname "*network*" -o -iname "*distributed*" \) -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null | sort | sed -n "1,80p"
  '
done

echo
echo "===== STEP 3: AUTO-RESTART FABRIC WHERE peer/orderer compose IS FOUND ====="
for ip in $VM2_IP $VM3_IP $VM9_IP $VM10_IP; do
  echo
  echo "========== RESTART ATTEMPT ON $ip =========="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set +e
    CANDIDATE=$(find ~ -maxdepth 4 -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" -o -name "compose.yml" -o -name "compose.yaml" \) 2>/dev/null | while read f; do
      grep -Eiq "peer|orderer" "$f" && echo "$f"
    done | head -n 1)

    if [ -z "$CANDIDATE" ]; then
      echo "NO_FABRIC_COMPOSE_FOUND"
      exit 0
    fi

    DIR=$(dirname "$CANDIDATE")
    echo "FABRIC_COMPOSE=$CANDIDATE"
    cd "$DIR"

    if command -v docker-compose >/dev/null 2>&1; then
      sudo docker-compose up -d
    else
      sudo docker compose up -d
    fi

    echo
    echo "--- AFTER RESTART ---"
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" | grep -Ei "peer|orderer|cli|governance|dev-peer|ccaas" || true
  '
done

echo
echo "===== STEP 4: TEST PORT 7051 FROM ORCHESTRATOR ====="
for ip in $VM2_IP $VM3_IP $VM9_IP $VM10_IP; do
  echo "--- $ip ---"
  timeout 3 bash -lc "cat < /dev/null > /dev/tcp/$ip/7051" && echo "PORT_7051_OPEN" || echo "PORT_7051_CLOSED"
done
