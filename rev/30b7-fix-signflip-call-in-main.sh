#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== FIX maybe_poison call placement on $ip ====="
  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
F=/opt/fl-client/fl_ids_client.py
[ -f "$F" ] || { echo "ERROR: missing $F"; exit 1; }

python3 - "$F" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text().splitlines(True)

clean = []
skip_print = 0
for line in lines:
    s = line.strip()
    if re.match(r'^w,\s*b,\s*attack_used\s*=\s*maybe_poison\(w,\s*b\)\s*$', s):
        skip_print = 2
        continue
    if skip_print > 0:
        if re.match(r'^if\s+attack_used\s*:\s*$', s):
            skip_print -= 1
            continue
        if "attack=" in s and "print" in s:
            skip_print -= 1
            continue
    clean.append(line)

txt = "".join(clean)

m = re.search(r'^(?P<ind>\s*)w\s*,\s*b\s*=\s*load_model\(\)\s*$', txt, flags=re.M)
if not m:
    raise SystemExit("ERROR: cannot find 'w, b = load_model()' inside main")

ind = m.group("ind")
start = m.end()

tail = txt[start:]
if re.search(r'^\s*w\s*,\s*b\s*,\s*attack_used\s*=\s*maybe_poison\(w,\s*b\)\s*$', tail, flags=re.M):
    p.write_text(txt)
    print("OK: already has maybe_poison inside main")
    raise SystemExit(0)

insert = (
    f"\n{ind}w, b, attack_used = maybe_poison(w, b)\n"
    f"{ind}if attack_used:\n"
    f"{ind}    print('  attack=', attack_used)\n"
)

txt2 = txt[:start] + insert + txt[start:]
p.write_text(txt2)
print("OK: inserted maybe_poison after load_model()")
PY

python3 -m py_compile "$F" && echo OK_compile
grep -n "load_model" "$F" | head -n 5 || true
grep -n "maybe_poison" "$F" | head -n 20 || true
REMOTE
done

echo DONE
