#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

OUT="$RUN_DIR/clean_baseline_probe_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

IPS="10.10.0.112 10.10.0.11 10.10.0.121 10.10.0.10"

echo "===== SNAPSHOT CURRENT LIVE CLIENT CODE ====="
for ip in $IPS; do
  echo
  echo "========== $ip =========="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    echo "--- config.env ---"
    [ -f /opt/fl-client/config.env ] && sed -n "1,220p" /opt/fl-client/config.env || true
    echo
    echo "--- md5 files ---"
    md5sum /opt/fl-client/fl_ids_client.py /opt/fl-client/fl_ids_byzantine.py /opt/fl-client/run_fl_round.sh 2>/dev/null || true
    echo
    echo "--- model dir before reset ---"
    ls -lah /opt/fl-client/models 2>/dev/null || true
    echo
    echo "--- logs dir before reset ---"
    ls -lah /opt/fl-client/logs 2>/dev/null | tail -n 20 || true
  ' | tee "$OUT/${ip}_before.txt"
done

echo
echo "===== RESET PERSISTED MODELS AND LOGS ON ACTIVE VMS ====="
for ip in $IPS; do
  echo
  echo "========== RESET $ip =========="
  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"$ip" '
    set -e
    mkdir -p /opt/fl-client/models /opt/fl-client/logs
    rm -f /opt/fl-client/models/*.npz
    rm -f /opt/fl-client/logs/fl-ids-*.json
    rm -f /opt/fl-client/logs/fl-byz-*.json
    rm -f /opt/fl-client/logs/fl_client_*.out
    rm -f /opt/fl-client/logs/fl_fabric_*.out
    echo "reset_done"
    ls -lah /opt/fl-client/models
    ls -lah /opt/fl-client/logs
  ' | tee "$OUT/${ip}_reset.txt"
done

echo
echo "===== RERUN LIVE BENCHMARK BASELINE ONLY ====="
START_ROUND=1 END_ROUND=5 \
BASELINE_BASE_FABRIC=9400000 \
LABEL_FLIP_BASE_FABRIC=9500000 \
BACKDOOR_BASE_FABRIC=9600000 \
BYZ_CLIENTS="edge-client-1 edge-client-6 edge-client-11 edge-client-16" \
SCENARIOS="baseline" \
bash rev/92-run-live-agg-benchmark-n20.sh | tee "$OUT/rerun_baseline_live.log"

LIVE=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* | head -n 1)

echo
echo "===== BASELINE SUMMARY AFTER CLEAN RESET ====="
cat "$LIVE/tables_input/agg_compare_summary_live.csv" | tee "$OUT/baseline_summary_live.csv"

echo
echo "===== BASELINE PER ROUND AFTER CLEAN RESET ====="
cat "$LIVE/figures_input/agg_compare_round_metrics_live.csv" | tee "$OUT/baseline_round_metrics_live.csv"

echo
echo "===== SAMPLE FEDAVG RAW R01 ====="
cat "$LIVE/fedavg/raw/baseline_fedavg_r01.json" | tee "$OUT/baseline_fedavg_r01.json"

echo
echo "===== SAMPLE FEDAVG RAW R05 ====="
cat "$LIVE/fedavg/raw/baseline_fedavg_r05.json" | tee "$OUT/baseline_fedavg_r05.json"

echo
echo "OUT=$OUT"
echo "LIVE=$LIVE"
