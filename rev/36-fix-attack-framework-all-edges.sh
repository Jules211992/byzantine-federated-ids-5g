#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== PATCH fl_ids_client.py (attack framework) on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
F=/opt/fl-client/fl_ids_client.py
[ -f \"\$F\" ] || { echo \"ERROR: missing \$F\"; exit 1; }

python3 - \"\$F\" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text().splitlines(True)

def replace_maybe_poison(lines):
    start=None
    for i,l in enumerate(lines):
        if re.match(r'^def\\s+maybe_poison\\s*\\(', l):
            start=i
            break
    if start is None:
        return lines, False

    end=None
    for j in range(start+1, len(lines)):
        if re.match(r'^def\\s+\\w+\\s*\\(', lines[j]):
            end=j
            break
    if end is None:
        end=len(lines)

    block = []
    block.append(\"def maybe_poison(w, b):\\n\")
    block.append(\"    mode = (os.environ.get('ATTACK_MODE','') or '').strip().lower()\\n\")
    block.append(\"    byz  = set((os.environ.get('BYZ_CLIENTS','') or '').split())\\n\")
    block.append(\"    cid  = (os.environ.get('CLIENT_ID','') or '').strip()\\n\")
    block.append(\"    if (not mode) or (cid not in byz):\\n\")
    block.append(\"        return w, b, ''\\n\")
    block.append(\"    import numpy as np\\n\")
    block.append(\"    if mode in ('signflip','sign_flip','flip'):\\n\")
    block.append(\"        scale = float(os.environ.get('ATTACK_SCALE','-5'))\\n\")
    block.append(\"        w2 = (w * scale).astype(np.float32)\\n\")
    block.append(\"        b2 = float(b * scale)\\n\")
    block.append(\"        return w2, b2, f'signflip(scale={scale})'\\n\")
    block.append(\"    if mode in ('scaling','scale'):\\n\")
    block.append(\"        scale = float(os.environ.get('ATTACK_SCALE','5'))\\n\")
    block.append(\"        w2 = (w * scale).astype(np.float32)\\n\")
    block.append(\"        b2 = float(b * scale)\\n\")
    block.append(\"        return w2, b2, f'scaling(scale={scale})'\\n\")
    block.append(\"    if mode in ('gaussian','gauss','noise'):\\n\")
    block.append(\"        sigma = float(os.environ.get('ATTACK_SIGMA','0.5'))\\n\")
    block.append(\"        seed = os.environ.get('ATTACK_SEED','')\\n\")
    block.append(\"        rng = np.random.default_rng(int(seed) if seed.strip() else None)\\n\")
    block.append(\"        w2 = (w + rng.normal(0.0, sigma, size=w.shape)).astype(np.float32)\\n\")
    block.append(\"        b2 = float(b + float(rng.normal(0.0, sigma)))\\n\")
    block.append(\"        return w2, b2, f'gaussian(sigma={sigma})'\\n\")
    block.append(\"    if mode in ('random','random_update','rand'):\\n\")
    block.append(\"        seed = os.environ.get('ATTACK_SEED','')\\n\")
    block.append(\"        rng = np.random.default_rng(int(seed) if seed.strip() else None)\\n\")
    block.append(\"        w2 = rng.normal(0.0, 1.0, size=w.shape).astype(np.float32)\\n\")
    block.append(\"        b2 = float(rng.normal(0.0, 1.0))\\n\")
    block.append(\"        return w2, b2, 'random()'\\n\")
    block.append(\"    if mode in ('backdoor',):\\n\")
    block.append(\"        delta = float(os.environ.get('ATTACK_DELTA','10'))\\n\")
    block.append(\"        w2 = w.copy()\\n\")
    block.append(\"        if getattr(w2,'size',0):\\n\")
    block.append(\"            w2[-1] = w2[-1] + delta\\n\")
    block.append(\"        return w2.astype(np.float32), float(b), f'backdoor(delta={delta})'\\n\")
    block.append(\"    return w, b, ''\\n\\n\")

    new = lines[:start] + block + lines[end:]
    return new, True

def fix_call_placement(lines):
    out=[]
    for l in lines:
        s=l.strip()
        if re.match(r'^w,\\s*b,\\s*attack_used\\s*=\\s*maybe_poison\\(w,\\s*b\\)\\s*$', s):
            continue
        if re.match(r'^if\\s+attack_used\\s*:\\s*$', s):
            continue
        if \"print('  attack='\" in s or 'print(\"  attack=\"' in s or 'attack_used' in s and 'attack=' in s:
            continue
        out.append(l)

    ins=None
    for i,l in enumerate(out):
        if 'print(f\"  L_inf=' in l or \"print(f'  L_inf=\" in l:
            ins=i+1
            break
    if ins is None:
        return out, False

    indent = re.match(r'^(\\s*)', out[ins-1]).group(1)
    block = [
        f\"{indent}w, b, attack_used = maybe_poison(w, b)\\n\",
        f\"{indent}if attack_used:\\n\",
        f\"{indent}    print('  attack=', attack_used)\\n\",
    ]
    out = out[:ins] + block + out[ins:]
    return out, True

lines, ok1 = replace_maybe_poison(lines)
lines, ok2 = fix_call_placement(lines)
Path(sys.argv[1]).write_text(''.join(lines))
print('OK_PATCH maybe_poison=', ok1, 'call_placement=', ok2)
PY

python3 -m py_compile /opt/fl-client/fl_ids_client.py && echo OK_COMPILE

echo '--- maybe_poison lines ---'
grep -n 'def maybe_poison' /opt/fl-client/fl_ids_client.py | head -n 2 || true
grep -n 'maybe_poison(w, b)' /opt/fl-client/fl_ids_client.py | head -n 4 || true
"
done

echo DONE
