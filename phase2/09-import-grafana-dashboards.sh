set -euo pipefail
source ~/byz-fed-ids-5g/config/config.env

BASE=~/byz-fed-ids-5g/monitoring
mkdir -p "$BASE/grafana/provisioning"/{dashboards,dashboards-json,plugins,notifiers,alerting,datasources}

GRAFANA_URL="http://127.0.0.1:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

for i in $(seq 1 90); do
  curl -fsS "$GRAFANA_URL/api/health" >/dev/null && break || true
  sleep 1
done
curl -fsS "$GRAFANA_URL/api/health" >/dev/null

PY="$(command -v python3 || true)"
if [ -z "$PY" ]; then
  PY="$(command -v python || true)"
fi
if [ -z "$PY" ]; then
  echo "NO_PYTHON"
  exit 1
fi

import_gnet() {
  local ID="$1"
  local TMP
  TMP="$(mktemp -d)"

  curl -fsSL "https://grafana.com/api/dashboards/${ID}/revisions/latest/download" > "$TMP/d.json"

  "$PY" - "$TMP/d.json" > "$TMP/payload.json" << 'PY'
import json,sys
dash=json.load(open(sys.argv[1]))
inputs=[]
for inp in dash.get("__inputs",[]):
    if inp.get("type")=="datasource":
        inputs.append({
            "name": inp.get("name"),
            "type": "datasource",
            "pluginId": inp.get("pluginId","prometheus"),
            "value": "Prometheus"
        })
payload={"dashboard":dash,"folderId":0,"overwrite":True,"inputs":inputs}
json.dump(payload,sys.stdout)
PY

  curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" \
    -H "Content-Type: application/json" \
    -X POST "$GRAFANA_URL/api/dashboards/import" \
    --data-binary @"$TMP/payload.json" >/dev/null

  rm -rf "$TMP"
  echo "IMPORTED_${ID}"
}

import_gnet 1860
import_gnet 14282

curl -fsS -u "$GRAFANA_USER:$GRAFANA_PASS" \
  "$GRAFANA_URL/api/search?type=dash-db&query=" | "$PY" - <<'PY'
import sys,json
items=json.load(sys.stdin)
print("DASHBOARDS_COUNT=%d" % len(items))
for it in items[:20]:
    print("DASH:", it.get("title",""), "|", it.get("url",""))
PY
