#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME"/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

BUNDLE=$(ls -dt "$RUN_DIR"/publication_bundle_* 2>/dev/null | head -n 1 || true)
[ -n "${BUNDLE:-}" ] || { echo "ERROR: publication_bundle introuvable"; exit 1; }

mkdir -p \
  "$BUNDLE/ipfs/selected" \
  "$BUNDLE/caliper/selected" \
  "$BUNDLE/manifest"

IPFS_FILES=(
  "$HOME/byz-fed-ids-5g/phase7/results/s_ipfs_size_benchmark_5node_avg_20260308_034738.csv"
  "$HOME/byz-fed-ids-5g/phase7/results/s_ipfs_size_benchmark_5node_avg_20260308_034738.json"
  "$HOME/byz-fed-ids-5g/phase4/results/s_ipfs_benchmark.csv"
  "$HOME/byz-fed-ids-5g/phase4/results/s_ipfs_filesize_benchmark.csv"
  "$HOME/byz-fed-ids-5g/phase5/results/s_ipfs_fabric_integration.csv"
)

CALIPER_FILES=(
  "$HOME/byz-fed-ids-5g/caliper/results/caliper-report-BEST-500ms-5w.html"
  "$HOME/byz-fed-ids-5g/caliper/results/caliper-report-baseline-10w-200ms.html"
  "$HOME/byz-fed-ids-5g/caliper/results/caliper-report-400ms-10k-50MB.html"
  "$HOME/byz-fed-ids-5g/caliper/results/report-20260226T060917Z.html"
  "$HOME/byz-fed-ids-5g/caliper/report.html"
)

IPFS_OK=()
CALIPER_OK=()

for f in "${IPFS_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "$BUNDLE/ipfs/selected/"
    IPFS_OK+=("$BUNDLE/ipfs/selected/$(basename "$f")")
  fi
done

for f in "${CALIPER_FILES[@]}"; do
  if [ -f "$f" ]; then
    cp -f "$f" "$BUNDLE/caliper/selected/"
    CALIPER_OK+=("$BUNDLE/caliper/selected/$(basename "$f")")
  fi
done

python3 - <<'PY' "$BUNDLE" "${IPFS_OK[@]}" ::: "${CALIPER_OK[@]}"
import json, sys
from pathlib import Path

bundle = Path(sys.argv[1])
args = sys.argv[2:]

sep = args.index(":::")
ipfs = args[:sep]
caliper = args[sep+1:]

summary = {
    "bundle": str(bundle),
    "ipfs_selected_count": len(ipfs),
    "caliper_selected_count": len(caliper),
    "ipfs_selected": ipfs,
    "caliper_selected": caliper
}

(bundle / "manifest" / "STAGED_IPFS_CALIPER.json").write_text(json.dumps(summary, indent=2))
print("BUNDLE=", bundle)
print("REPORT=", bundle / "manifest" / "STAGED_IPFS_CALIPER.json")
PY
