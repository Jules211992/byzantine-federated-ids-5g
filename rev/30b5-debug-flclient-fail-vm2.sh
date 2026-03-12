#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
IP="$VM2_IP"

ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$IP" 'bash -s' <<'REMOTE'
set -euo pipefail
echo HOST:$(hostname) IP:$(hostname -I | awk "{print \$1}")
echo

python3 -m py_compile /opt/fl-client/fl_ids_client.py && echo OK_compile || echo FAIL_compile
echo

echo "--- TOP of file (1..40) ---"
nl -ba /opt/fl-client/fl_ids_client.py | sed -n '1,40p'
echo

echo "--- maybe_poison occurrences ---"
grep -n "maybe_poison" /opt/fl-client/fl_ids_client.py || true
echo

echo "--- last logs (r1) ---"
ls -1t /opt/fl-client/logs/fl_client_*_r1.out 2>/dev/null | head -n 6 || true
echo

for f in /opt/fl-client/logs/fl_client_edge-client-1_r1.out /opt/fl-client/logs/fl_client_edge-client-2_r1.out; do
  echo "===== $f ====="
  [ -f "$f" ] && tail -n 120 "$f" || echo MISSING
  echo
done
REMOTE
