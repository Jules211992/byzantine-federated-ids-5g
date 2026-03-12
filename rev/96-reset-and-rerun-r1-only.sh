#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

OUT="$RUN_DIR/r1_probe_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

IPS="10.10.0.112 10.10.0.11 10.10.0.121 10.10.0.10"

echo "===== RESET MODELS AND LOGS ====="
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
    echo reset_done
  '
done

echo
echo "===== RUN BASELINE ROUND 1 ONLY ====="
START_ROUND=1 END_ROUND=1 \
BASELINE_BASE_FABRIC=9400000 \
LABEL_FLIP_BASE_FABRIC=9500000 \
BACKDOOR_BASE_FABRIC=9600000 \
BYZ_CLIENTS="edge-client-1 edge-client-6 edge-client-11 edge-client-16" \
SCENARIOS="baseline" \
bash rev/92-run-live-agg-benchmark-n20.sh | tee "$OUT/baseline_r1.log"

LIVE_BASE=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* | head -n 1)
cp -f "$LIVE_BASE/tables_input/agg_compare_summary_live.csv" "$OUT/baseline_summary_live.csv"
cp -f "$LIVE_BASE/figures_input/agg_compare_round_metrics_live.csv" "$OUT/baseline_round_metrics_live.csv"
cp -f "$LIVE_BASE/fedavg/raw/baseline_fedavg_r01.json" "$OUT/baseline_fedavg_r01.json"
cp -f "$LIVE_BASE/multikrum/raw/baseline_multikrum_r01.json" "$OUT/baseline_multikrum_r01.json"
cp -f "$LIVE_BASE/trimmedmean/raw/baseline_trimmedmean_r01.json" "$OUT/baseline_trimmedmean_r01.json"

echo
echo "===== RUN LABEL_FLIP ROUND 1 ONLY ====="
START_ROUND=1 END_ROUND=1 \
BASELINE_BASE_FABRIC=9400000 \
LABEL_FLIP_BASE_FABRIC=9500000 \
BACKDOOR_BASE_FABRIC=9600000 \
BYZ_CLIENTS="edge-client-1 edge-client-6 edge-client-11 edge-client-16" \
SCENARIOS="label_flip" \
bash rev/92-run-live-agg-benchmark-n20.sh | tee "$OUT/label_flip_r1.log"

LIVE_LF=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* | head -n 1)
cp -f "$LIVE_LF/tables_input/agg_compare_summary_live.csv" "$OUT/label_flip_summary_live.csv"
cp -f "$LIVE_LF/figures_input/agg_compare_round_metrics_live.csv" "$OUT/label_flip_round_metrics_live.csv"
cp -f "$LIVE_LF/fedavg/raw/label_flip_fedavg_r01.json" "$OUT/label_flip_fedavg_r01.json"
cp -f "$LIVE_LF/multikrum/raw/label_flip_multikrum_r01.json" "$OUT/label_flip_multikrum_r01.json"
cp -f "$LIVE_LF/trimmedmean/raw/label_flip_trimmedmean_r01.json" "$OUT/label_flip_trimmedmean_r01.json"

echo
echo "===== RUN BACKDOOR ROUND 1 ONLY ====="
START_ROUND=1 END_ROUND=1 \
BASELINE_BASE_FABRIC=9400000 \
LABEL_FLIP_BASE_FABRIC=9500000 \
BACKDOOR_BASE_FABRIC=9600000 \
BYZ_CLIENTS="edge-client-1 edge-client-6 edge-client-11 edge-client-16" \
SCENARIOS="backdoor" \
bash rev/92-run-live-agg-benchmark-n20.sh | tee "$OUT/backdoor_r1.log"

LIVE_BD=$(ls -dt "$RUN_DIR"/agg_compare_n20_live_* | head -n 1)
cp -f "$LIVE_BD/tables_input/agg_compare_summary_live.csv" "$OUT/backdoor_summary_live.csv"
cp -f "$LIVE_BD/figures_input/agg_compare_round_metrics_live.csv" "$OUT/backdoor_round_metrics_live.csv"
cp -f "$LIVE_BD/fedavg/raw/backdoor_fedavg_r01.json" "$OUT/backdoor_fedavg_r01.json"
cp -f "$LIVE_BD/multikrum/raw/backdoor_multikrum_r01.json" "$OUT/backdoor_multikrum_r01.json"
cp -f "$LIVE_BD/trimmedmean/raw/backdoor_trimmedmean_r01.json" "$OUT/backdoor_trimmedmean_r01.json"

echo
echo "===== QUICK VIEW ====="
echo "--- baseline ---"
cat "$OUT/baseline_summary_live.csv"
echo
echo "--- label_flip ---"
cat "$OUT/label_flip_summary_live.csv"
echo
echo "--- backdoor ---"
cat "$OUT/backdoor_summary_live.csv"
echo
echo "OUT=$OUT"
