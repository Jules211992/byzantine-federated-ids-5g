#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

BYZ_CLIENTS="${BYZ_CLIENTS:-edge-client-1 edge-client-6 edge-client-11 edge-client-16}"
ATTACK_MODE="${ATTACK_MODE:-signflip}"
ATTACK_SCALE="${ATTACK_SCALE:--5}"

PATCH=/tmp/signflip_patch.py

cat <<'PY' > "$PATCH"
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text()

if "def maybe_poison(" not in txt:
    m = re.search(r"(^import[^\n]*\n)+", txt, flags=re.M)
    if not m:
        m = re.search(r"(^from[^\n]*\n)+", txt, flags=re.M)
    if not m:
        raise SystemExit("ERROR: cannot find imports block")
    ins = """
def maybe_poison(w, b):
    mode = (os.environ.get("ATTACK_MODE","") or "").strip().lower()
    byz  = set((os.environ.get("BYZ_CLIENTS","") or "").split())
    if not mode:
        return w, b, ""
    if byz and (CLIENT_ID not in byz):
        return w, b, ""
    if mode == "signflip":
        try:
            s = float(os.environ.get("ATTACK_SCALE","-1"))
        except Exception:
            s = -1.0
        w = (w * s).astype(np.float32, copy=False)
        b = float(b) * s
        return w, b, f"signflip(s={s})"
    return w, b, mode
"""
    txt = txt[:m.end()] + ins + txt[m.end():]

lines = txt.splitlines(True)

idxs = [i for i,l in enumerate(lines) if "ipfs_add(" in l]
if not idxs:
    raise SystemExit("ERROR: cannot find ipfs_add() call site")
idx = idxs[-1]

inject = "w, b, attack_used = maybe_poison(w, b)\nif attack_used:\n    print('  attack=', attack_used)\n"
if "attack_used" not in "".join(lines[max(0,idx-5):idx+5]):
    lines.insert(idx, inject)

p.write_text("".join(lines))
print("OK_PATCHED", p)
PY

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== SIGNFLIP SETUP on $ip ====="

  scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$PATCH" ubuntu@"$ip":/tmp/signflip_patch.py >/dev/null

  ssh -n -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" "
set -euo pipefail
echo HOST:\$(hostname) IP:\$(hostname -I | awk '{print \$1}')

CFG=/opt/fl-client/config.env
touch \"\$CFG\"

grep -q '^BYZ_CLIENTS=' \"\$CFG\" && sed -i \"s|^BYZ_CLIENTS=.*|BYZ_CLIENTS=$BYZ_CLIENTS|\" \"\$CFG\" || echo \"BYZ_CLIENTS=$BYZ_CLIENTS\" >> \"\$CFG\"
grep -q '^ATTACK_MODE=' \"\$CFG\" && sed -i \"s|^ATTACK_MODE=.*|ATTACK_MODE=$ATTACK_MODE|\" \"\$CFG\" || echo \"ATTACK_MODE=$ATTACK_MODE\" >> \"\$CFG\"
grep -q '^ATTACK_SCALE=' \"\$CFG\" && sed -i \"s|^ATTACK_SCALE=.*|ATTACK_SCALE=$ATTACK_SCALE|\" \"\$CFG\" || echo \"ATTACK_SCALE=$ATTACK_SCALE\" >> \"\$CFG\"

echo
echo '--- config.env (attack lines) ---'
grep -E '^BYZ_CLIENTS=|^ATTACK_MODE=|^ATTACK_SCALE=' \"\$CFG\" || true

F=/opt/fl-client/fl_ids_client.py
[ -f \"\$F\" ] || { echo \"ERROR: missing \$F\"; exit 1; }

[ -f /opt/fl-client/fl_ids_client.py.bak_signflip ] || cp -f \"\$F\" /opt/fl-client/fl_ids_client.py.bak_signflip

python3 /tmp/signflip_patch.py \"\$F\"
python3 -m py_compile \"\$F\"

echo
echo '--- show ipfs_add call vicinity ---'
nl -ba \"\$F\" | grep -n 'ipfs_add' -n | head -n 3 || true
grep -n 'attack_used' -n \"\$F\" | head -n 3 || true
echo OK
"
done

echo DONE
