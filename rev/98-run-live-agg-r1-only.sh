#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

IPS="10.10.0.112 10.10.0.11 10.10.0.121 10.10.0.10"

for ip in $IPS; do
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    mkdir -p /opt/fl-client/models /opt/fl-client/logs
    rm -f /opt/fl-client/models/*.npz
    rm -f /opt/fl-client/logs/fl-ids-*.json
    rm -f /opt/fl-client/logs/fl-byz-*.json
    rm -f /opt/fl-client/logs/fl_client_*.out
    rm -f /opt/fl-client/logs/fl_fabric_*.out
  '
done

START_ROUND=1 \
END_ROUND=1 \
SCENARIOS="baseline label_flip backdoor" \
BASELINE_BASE_FABRIC=9500000 \
LABEL_FLIP_BASE_FABRIC=9600000 \
BACKDOOR_BASE_FABRIC=9700000 \
BYZ_CLIENTS="edge-client-1 edge-client-6 edge-client-11 edge-client-16" \
bash rev/92-run-live-agg-benchmark-n20.sh

LIVE=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* | head -n 1)

echo
echo "===== README ====="
cat "$LIVE/README.txt"

echo
echo "===== SUMMARY CSV ====="
cat "$LIVE/tables_input/agg_compare_summary_live.csv"

echo
echo "===== PAPER CSV ====="
cat "$LIVE/tables_input/agg_compare_paper_table_live.csv"

echo
echo "===== PER ROUND CSV ====="
cat "$LIVE/figures_input/agg_compare_round_metrics_live.csv"

echo
echo "===== BASELINE FEDAVG R1 ====="
cat "$LIVE/fedavg/raw/baseline_fedavg_r01.json"

echo
echo "===== LABEL_FLIP MULTIKRUM R1 ====="
cat "$LIVE/multikrum/raw/label_flip_multikrum_r01.json"

echo
echo "===== BACKDOOR MULTIKRUM R1 ====="
cat "$LIVE/multikrum/raw/backdoor_multikrum_r01.json"

echo
echo "LIVE_DIR=$LIVE"
