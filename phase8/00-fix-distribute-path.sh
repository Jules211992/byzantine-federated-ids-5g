#!/bin/bash
set -euo pipefail

FILE=~/byz-fed-ids-5g/phase8/run_p8_n5.sh

if [ ! -f "$FILE" ]; then
  echo "MISSING $FILE"
  exit 1
fi

DS=/home/ubuntu/byz-fed-ids-5g/scripts/distribute_global.py
if [ ! -f "$DS" ]; then
  DS=$(find /home/ubuntu/byz-fed-ids-5g -type f -name distribute_global.py | head -n 1 || true)
fi

if [ -z "${DS:-}" ] || [ ! -f "$DS" ]; then
  echo "NOT_FOUND distribute_global.py"
  exit 1
fi

cp -f "$FILE" "${FILE}.bak_$(date -u +%Y%m%d_%H%M%S)"

sed -i "s|python3 /tmp/distribute_global.py|python3 $DS|g" "$FILE"

echo "PATCHED: $FILE"
echo "USING:   $DS"
grep -n "distribute_global" "$FILE" | tail -n 20
