set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "NTP $ip"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "sudo bash -lc '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq chrony
    systemctl enable --now chrony || systemctl enable --now chronyd
    chronyc tracking || true
    chronyc sources -v | head -20 || true
    timedatectl show -p NTPSynchronized -p NTPService -p TimeUSec || true
  '"
done

echo "OK NTP chrony terminé"
