set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "RUNTIME $ip"

  set +e
  timeout 900s ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=20 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$ip" "sudo bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl jq gnupg lsb-release
apt-get install -y docker.io docker-compose-plugin

systemctl enable docker
systemctl restart docker

docker version
docker compose version
'"

  rc=$?
  echo "RC_$ip=$rc"
  set -e
done
