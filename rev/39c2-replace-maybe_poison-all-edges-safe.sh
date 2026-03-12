#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== REPLACE maybe_poison on $ip ====="

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

p = Path('/opt/fl-client/fl_ids_client.py')
lines = p.read_text().splitlines(True)

start = None
for i,l in enumerate(lines):
    if l.startswith('def maybe_poison('):
        start = i
        break
if start is None:
    raise SystemExit('ERROR: def maybe_poison not found')

end = start + 1
while end < len(lines):
    l = lines[end]
    if end > start and l.strip() != '' and (not l.startswith((' ', '\t'))):
        break
    end += 1

new_func = """def maybe_poison(w, b):
    import os
    import numpy as np

    mode = (os.environ.get("ATTACK_MODE","") or "").strip().lower()
    byz  = set((os.environ.get("BYZ_CLIENTS","") or "").split())

    cid = (os.environ.get("CLIENT_ID","") or "").strip()
    if not cid:
        try:
            cid = str(globals().get("CLIENT_ID","")).strip()
        except Exception:
            cid = ""

    if (not mode) or (cid not in byz):
        return w, b, None

    try:
        scale = float(os.environ.get("ATTACK_SCALE","1") or "1")
    except Exception:
        scale = 1.0

    if mode in ("scaling","scale"):
        w2 = (w * scale).astype(np.float32)
        b2 = float(b * scale)
        return w2, b2, f"scaling({scale})"

    if mode in ("signflip","flip","negate"):
        factor = -abs(scale) if scale != 0 else -1.0
        w2 = (w * factor).astype(np.float32)
        b2 = float(b * factor)
        return w2, b2, f"signflip({factor})"

    return w, b, None
"""

lines = lines[:start] + [new_func + "\n"] + lines[end:]
p.write_text(''.join(lines))

print("OK_REPLACED", str(p), "start_line", start+1, "end_line", end+1)
PY

python3 -m py_compile /opt/fl-client/fl_ids_client.py

echo "--- maybe_poison lines ---"
grep -n '^def maybe_poison\|maybe_poison(w, b)' /opt/fl-client/fl_ids_client.py | head -n 10
REMOTE
done

echo DONE
