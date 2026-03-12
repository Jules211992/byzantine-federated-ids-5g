#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

echo "=== Search candidates for edges maps ==="
find . -maxdepth 5 -type f \( -name '*edge*map*' -o -name '*edges*' -o -name '*clients*' -o -name '*nodes*' \) \
  | grep -E 'map|edge|client' \
  | sort \
  | sed -n '1,220p'

echo
echo "=== Search for edge-client-[0-9] patterns (to locate 10/20 mappings) ==="
grep -R --line-number --no-messages -E 'edge-client-([5-9]|1[0-9]|20)\b' . \
  | sed -n '1,220p' || true

echo
echo "=== Search for IP patterns repeated in maps ==="
grep -R --line-number --no-messages -E '10\.10\.0\.[0-9]+' ./config ./phase7 ./phase8 2>/dev/null \
  | sed -n '1,220p' || true
