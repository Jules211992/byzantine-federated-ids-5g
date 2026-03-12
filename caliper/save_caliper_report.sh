#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
TS=$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p results
cp -f report.html "results/report-${TS}.html"
cp -f caliper.log "results/caliper-${TS}.log" 2>/dev/null || true
cp -f benchmarks/benchmark.yaml "results/benchmark-${TS}.yaml" 2>/dev/null || true
cp -f networks/fabric-network.yaml "results/network-${TS}.yaml" 2>/dev/null || true
cp -f networks/org1-connection.yaml "results/connection-${TS}.yaml" 2>/dev/null || true
echo "saved results/report-${TS}.html"
