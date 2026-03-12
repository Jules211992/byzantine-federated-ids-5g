set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BASE=~/byz-fed-ids-5g/monitoring
PROV="$BASE/grafana/provisioning"
mkdir -p "$PROV/dashboards" "$PROV/dashboards-json"

cat > "$PROV/dashboards/dashboards.yml" << 'EOD'
apiVersion: 1
providers:
  - name: 'Provisioned'
    orgId: 1
    folder: 'Provisioned'
    type: file
    disableDeletion: true
    editable: true
    options:
      path: /etc/grafana/provisioning/dashboards-json
EOD

cat > "$PROV/dashboards-json/nodes.json" << 'EON'
{
  "uid": "nodes",
  "title": "Nodes (node-exporter)",
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "tags": ["node-exporter"],
  "templating": {
    "list": [
      {
        "name": "instance",
        "type": "query",
        "datasource": {"type": "prometheus", "uid": "Prometheus"},
        "query": "label_values(node_uname_info, instance)",
        "refresh": 1,
        "multi": true,
        "includeAll": true,
        "allValue": ".*",
        "current": {"text": "All", "value": ".*"}
      }
    ]
  },
  "panels": [
    {
      "type": "timeseries",
      "title": "CPU usage (%)",
      "gridPos": {"x": 0, "y": 0, "w": 12, "h": 8},
      "targets": [
        {
          "expr": "100*(1-avg by(instance)(rate(node_cpu_seconds_total{mode=\"idle\",instance=~\"$instance\"}[1m])))",
          "legendFormat": "{{instance}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Memory usage (%)",
      "gridPos": {"x": 12, "y": 0, "w": 12, "h": 8},
      "targets": [
        {
          "expr": "100*(1-(node_memory_MemAvailable_bytes{instance=~\"$instance\"}/node_memory_MemTotal_bytes{instance=~\"$instance\"}))",
          "legendFormat": "{{instance}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Load (1m / 5m)",
      "gridPos": {"x": 0, "y": 8, "w": 12, "h": 8},
      "targets": [
        {"expr": "node_load1{instance=~\"$instance\"}", "legendFormat": "{{instance}} load1"},
        {"expr": "node_load5{instance=~\"$instance\"}", "legendFormat": "{{instance}} load5"}
      ]
    },
    {
      "type": "timeseries",
      "title": "Disk used (%) mount=/",
      "gridPos": {"x": 12, "y": 8, "w": 12, "h": 8},
      "targets": [
        {
          "expr": "100*(1-node_filesystem_avail_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\",instance=~\"$instance\"}/node_filesystem_size_bytes{mountpoint=\"/\",fstype!~\"tmpfs|overlay\",instance=~\"$instance\"})",
          "legendFormat": "{{instance}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Network RX (bytes/s) sum",
      "gridPos": {"x": 0, "y": 16, "w": 12, "h": 8},
      "targets": [
        {
          "expr": "sum by(instance)(rate(node_network_receive_bytes_total{device!~\"lo\",instance=~\"$instance\"}[1m]))",
          "legendFormat": "{{instance}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Network TX (bytes/s) sum",
      "gridPos": {"x": 12, "y": 16, "w": 12, "h": 8},
      "targets": [
        {
          "expr": "sum by(instance)(rate(node_network_transmit_bytes_total{device!~\"lo\",instance=~\"$instance\"}[1m]))",
          "legendFormat": "{{instance}}"
        }
      ]
    }
  ]
}
EON

cat > "$PROV/dashboards-json/containers.json" << 'EOC'
{
  "uid": "containers",
  "title": "Containers (cAdvisor)",
  "timezone": "browser",
  "schemaVersion": 39,
  "version": 1,
  "refresh": "10s",
  "tags": ["cadvisor"],
  "templating": {
    "list": [
      {
        "name": "instance",
        "type": "query",
        "datasource": {"type": "prometheus", "uid": "Prometheus"},
        "query": "label_values(container_cpu_usage_seconds_total, instance)",
        "refresh": 1,
        "multi": true,
        "includeAll": true,
        "allValue": ".*",
        "current": {"text": "All", "value": ".*"}
      }
    ]
  },
  "panels": [
    {
      "type": "timeseries",
      "title": "Top 10 container CPU (cores/s)",
      "gridPos": {"x": 0, "y": 0, "w": 24, "h": 9},
      "targets": [
        {
          "expr": "topk(10, rate(container_cpu_usage_seconds_total{instance=~\"$instance\", image!=\"\"}[1m]))",
          "legendFormat": "{{name}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Top 10 container Memory (bytes)",
      "gridPos": {"x": 0, "y": 9, "w": 24, "h": 9},
      "targets": [
        {
          "expr": "topk(10, container_memory_working_set_bytes{instance=~\"$instance\", image!=\"\"})",
          "legendFormat": "{{name}}"
        }
      ]
    },
    {
      "type": "timeseries",
      "title": "Top 10 container Network RX (bytes/s)",
      "gridPos": {"x": 0, "y": 18, "w": 24, "h": 9},
      "targets": [
        {
          "expr": "topk(10, rate(container_network_receive_bytes_total{instance=~\"$instance\"}[1m]))",
          "legendFormat": "{{name}}"
        }
      ]
    }
  ]
}
EOC

docker restart grafana >/dev/null

for i in $(seq 1 60); do
  curl -fsS http://127.0.0.1:3000/api/health >/dev/null && break || true
  sleep 1
done

curl -fsS http://127.0.0.1:3000/api/health >/dev/null && echo OK_GRAFANA || echo FAIL_GRAFANA
docker logs --tail 120 grafana | egrep -i "provision|dashboard" || true
