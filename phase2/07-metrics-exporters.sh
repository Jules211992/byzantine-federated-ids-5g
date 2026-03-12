set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  echo "EXPORTERS $ip"

  set +e
  timeout 300s ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=no \
    -o ConnectTimeout=15 \
    -o ServerAliveInterval=5 \
    -o ServerAliveCountMax=3 \
    "$SSH_USER@$ip" "sudo bash -lc '
set -e

docker version >/dev/null

docker rm -f node-exporter cadvisor >/dev/null || true

docker pull -q prom/node-exporter:v1.8.1 >/dev/null

IMG=gcr.io/cadvisor/cadvisor:v0.49.1
set +e
docker pull -q \$IMG >/dev/null
PULL_OK=\$?
set -e
if [ \"\$PULL_OK\" -ne 0 ]; then
  IMG=registry.k8s.io/cadvisor/cadvisor:v0.49.1
  docker pull -q \$IMG >/dev/null
fi

docker run -d --restart unless-stopped --name node-exporter --net host --pid host -v /:/host:ro,rslave prom/node-exporter:v1.8.1 --path.rootfs=/host >/dev/null

docker run -d --restart unless-stopped --name cadvisor --net host --pid host -v /:/rootfs:ro -v /var/run:/var/run:ro -v /sys:/sys:ro -v /var/lib/docker:/var/lib/docker:ro -v /dev/disk:/dev/disk:ro --privileged \$IMG >/dev/null

for i in \$(seq 1 60); do
  curl -fsS http://127.0.0.1:9100/metrics >/dev/null 2>&1 && curl -fsS http://127.0.0.1:8080/metrics >/dev/null 2>&1 && break
  sleep 1
done

curl -fsS http://127.0.0.1:9100/metrics >/dev/null && echo OK_NODE
curl -fsS http://127.0.0.1:8080/metrics >/dev/null && echo OK_CADVISOR
'"

  RC=$?
  echo "RC_${ip}=${RC}"
  set -e
done
