set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env
for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "BOOTSTRAP $ip"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$SSH_USER@$ip" "sudo bash -lc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin jq net-tools unzip chrony
    systemctl enable --now docker
    usermod -aG docker ubuntu || true
  '"
done
echo "OK bootstrap terminé"
