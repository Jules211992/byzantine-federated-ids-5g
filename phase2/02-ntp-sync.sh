set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env
for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "NTP $ip"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 "$SSH_USER@$ip" "sudo bash -lc '
    systemctl enable --now chrony
    chronyc makestep
    chronyc tracking | grep -E \"Reference|offset\"
  '"
done
echo "OK NTP synchronisé"
