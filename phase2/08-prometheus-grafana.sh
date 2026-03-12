set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env
BASE=~/byz-fed-ids-5g/monitoring
mkdir -p "$BASE/prometheus" "$BASE/grafana/provisioning/datasources"

printf 'global:\n  scrape_interval: 5s\n  evaluation_interval: 5s\nscrape_configs:\n  - job_name: node-exporter\n    static_configs:\n      - targets:\n' > "$BASE/prometheus/prometheus.yml"
for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  printf '          - "%s:9100"\n' "$ip" >> "$BASE/prometheus/prometheus.yml"
done
printf '  - job_name: cadvisor\n    static_configs:\n      - targets:\n' >> "$BASE/prometheus/prometheus.yml"
for ip in $(cat ~/byz-fed-ids-5g/config/nodes_ip.txt); do
  printf '          - "%s:8080"\n' "$ip" >> "$BASE/prometheus/prometheus.yml"
done

printf 'apiVersion: 1\ndatasources:\n  - name: Prometheus\n    type: prometheus\n    access: proxy\n    url: http://prometheus:9090\n    isDefault: true\n    editable: true\n' > "$BASE/grafana/provisioning/datasources/datasource.yml"

printf 'services:\n  prometheus:\n    image: prom/prometheus:v2.51.2\n    container_name: prometheus\n    restart: unless-stopped\n    volumes:\n      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro\n      - prom_data:/prometheus\n    command:\n      - --config.file=/etc/prometheus/prometheus.yml\n      - --storage.tsdb.path=/prometheus\n      - --storage.tsdb.retention.time=7d\n    ports:\n      - "9090:9090"\n  grafana:\n    image: grafana/grafana:10.4.2\n    container_name: grafana\n    restart: unless-stopped\n    environment:\n      - GF_SECURITY_ADMIN_USER=admin\n      - GF_SECURITY_ADMIN_PASSWORD=admin\n      - GF_USERS_ALLOW_SIGN_UP=false\n    volumes:\n      - grafana_data:/var/lib/grafana\n      - ./grafana/provisioning:/etc/grafana/provisioning:ro\n    ports:\n      - "3000:3000"\n    depends_on:\n      - prometheus\nvolumes:\n  prom_data:\n  grafana_data:\n' > "$BASE/docker-compose.yml"

cd "$BASE"
docker compose pull
docker compose up -d

for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:9090/-/ready >/dev/null && break || true
  sleep 1
done

curl -fsS http://127.0.0.1:9090/-/ready >/dev/null && echo OK_PROMETHEUS || echo FAIL_PROMETHEUS
curl -fsS http://127.0.0.1:3000/api/health >/dev/null && echo OK_GRAFANA || echo FAIL_GRAFANA
