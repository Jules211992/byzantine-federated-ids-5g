#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
RUN_DIR=$(ls -dt ~/byz-fed-ids-5g/rev/runs/rev_*_5g 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

OUT="$RUN_DIR/s5_trace_$(date -u +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"

echo "RUN_DIR=$RUN_DIR"
echo "OUT=$OUT"

echo
echo "===== 1) FIND fichiers S5/security/fault ====="
find "$RUN_DIR" rev phase7 phase8 phase9 phase10 -type f \
  \( \
    -iname "*security*" -o \
    -iname "*fault*" -o \
    -iname "*recovery*" -o \
    -iname "*raft*" -o \
    -iname "*ipfs*" -o \
    -iname "*sybil*" -o \
    -iname "*rollback*" -o \
    -iname "*replay*" -o \
    -iname "*s5*" \
  \) 2>/dev/null | sort | tee "$OUT/find_s5_files.txt"

echo
echo "===== 2) GREP contenu utile ====="
grep -RIn \
  -E 'S5|security|fault|recovery|raft|orderer3|ipfs|replay|rollback|sybil|REJECTED|CONTINUED|16\.6|108' \
  "$RUN_DIR" rev phase7 phase8 phase9 phase10 2>/dev/null | tee "$OUT/grep_s5_trace.txt"

echo
echo "===== 3) TABLES/CSV/JSON les plus probables ====="
for f in \
  $(find "$RUN_DIR" -type f \( -iname "*.csv" -o -iname "*.json" -o -iname "*.txt" -o -iname "*.md" \) 2>/dev/null | sort); do
  if grep -qiE 'replay|rollback|sybil|orderer3|raft|recovery|ipfs latency|CONTINUED|REJECTED' "$f" 2>/dev/null; then
    echo "----- $f -----"
    sed -n '1,220p' "$f"
    echo
  fi
done | tee "$OUT/s5_candidate_contents.txt"

echo
echo "===== 4) HEAD du grep trace ====="
sed -n '1,240p' "$OUT/grep_s5_trace.txt"

echo
echo "===== 5) HEAD des fichiers trouvés ====="
sed -n '1,240p' "$OUT/find_s5_files.txt"

echo
echo "DONE"
echo "TRACE_DIR=$OUT"
