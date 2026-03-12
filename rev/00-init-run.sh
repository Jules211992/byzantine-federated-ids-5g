#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

TS=$(date -u +%Y%m%d_%H%M%S)
RUN_DIR="$HOME/byz-fed-ids-5g/rev/runs/rev_${TS}_5g"
mkdir -p "$RUN_DIR"/{manifest,config,scripts_snapshot,p7_baseline,p8_attacks,collect,summary}

cp -f "$HOME/byz-fed-ids-5g/config/config.env" "$RUN_DIR/config/" 2>/dev/null || true
cp -f "$HOME/byz-fed-ids-5g/config/edges_map.txt" "$RUN_DIR/config/" 2>/dev/null || true
cp -f "$HOME/byz-fed-ids-5g/config/fabric_nodes.env" "$RUN_DIR/config/" 2>/dev/null || true
cp -f "$HOME/byz-fed-ids-5g/config/nodes_ip.txt" "$RUN_DIR/config/" 2>/dev/null || true

tar -czf "$RUN_DIR/scripts_snapshot/phase7_phase8_${TS}.tgz" phase7 phase8 scripts config >/dev/null 2>&1 || true

{
  echo "UTC=$TS"
  echo "HOST=$(hostname)"
  echo "RUN_DIR=$RUN_DIR"
  echo "DATASET=5G"
  echo "NOTE=Revision suite (clean collection for tables/figures)"
} > "$RUN_DIR/manifest/run.info"

echo "$RUN_DIR" > "$HOME/byz-fed-ids-5g/rev/LAST_RUN_DIR"

echo "RUN_DIR=$RUN_DIR"
