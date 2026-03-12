set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "AUDIT $ip"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "sudo bash -lc '
    timedatectl show -p NTPSynchronized -p TimeUSec
    chronyc tracking | egrep \"Reference ID|Stratum|System time|Last offset|Leap status\"
    chronyc sources -v | egrep \"^\\^\\*|^\\^\\+\" | head -5 || true
  '"
done
