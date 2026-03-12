set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "PIN-SOURCES $ip"

  set +e
  timeout 60s ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$ip" "sudo bash -lc '
set -e
mkdir -p /var/log/chrony
TS=\$(date +%s)

if [ -f /etc/chrony/chrony.conf ]; then
  cp -a /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak.\$TS || true
fi

cat > /etc/chrony/chrony.conf << \"EOC\"
driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
leapsectz right/UTC
logdir /var/log/chrony

server time.cloudflare.com iburst
server ntp1.torix.ca iburst
server ntp2.torix.ca iburst
server alphyn.canonical.com iburst

minsources 2
maxdistance 16.0
EOC

systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true

chronyc -a burst 4/4 || true
chronyc -a makestep || true
chronyc -a waitsync 15 0.2 || true

timedatectl show -p NTPSynchronized -p TimeUSec
chronyc tracking | egrep \"Reference ID|Stratum|System time|Last offset|Leap status\" || true
chronyc sources -v | egrep \"^\\^\\*|^\\^\\+|^\\^\\-\" | head -10 || true
'"
  rc=$?
  echo "RC_$ip=$rc"
  set -e
done
