#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

echo "=== phase6 presence ==="
ls -la phase6 2>/dev/null || true
echo

echo "=== candidate scripts (phase6 / split / dataset / 5g) ==="
find . -maxdepth 5 -type f \( -name '*.py' -o -name '*.sh' \) \
| grep -E 'phase6|split|dataset|preprocess|prepare|5g' \
| sort | sed -n '1,260p'
echo

echo "=== grep keywords (split/dataset/client) ==="
grep -R --line-number --no-messages -E 'split|SPLITS_DIR|train_X|test_X|edge-client-|5g|N_CLIENTS|n_clients|partition|non-iid|iid' \
phase6 scripts config 2>/dev/null | sed -n '1,320p' || true
echo

echo "=== raw dataset candidates (csv/parquet/npz/pkl) ==="
find . -maxdepth 6 -type f \
\( -iname '*5g*' -o -iname '*dataset*' -o -iname '*.csv' -o -iname '*.parquet' -o -iname '*.npz' -o -iname '*.pkl' \) \
| sort | sed -n '1,260p'
echo

echo "=== split_stats.json (phase6/splits) ==="
if [ -f phase6/splits/split_stats.json ]; then
  sed -n '1,260p' phase6/splits/split_stats.json
else
  echo "NO split_stats.json in phase6/splits"
fi
