set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "FORCE-SYNC $ip"
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$SSH_USER@$ip" "sudo bash -lc '
    systemctl restart chrony || systemctl restart chronyd
    chronyc -a burst 4/4 || true
    chronyc -a makestep || true
    chronyc -a waitsync 15 0.2 || true
    echo TRACKING
    chronyc tracking || true
    echo SOURCES
    chronyc sources -v | head -15 || true
    echo TIMEDATECTL
    timedatectl show -p NTPSynchronized -p NTPService -p TimeUSec || true
  '"
done
