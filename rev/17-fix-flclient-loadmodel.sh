#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY=${SSH_KEY:-/home/ubuntu/byz-fed-ids-5g/keys/fl-ids-key.pem}
EDGE_IPS=("$VM2_IP" "$VM3_IP" "$VM4_IP" "$VM5_IP")

for ip in "${EDGE_IPS[@]}"; do
  echo
  echo "===== PATCH fl_ids_client.py on $ip ====="

  ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@"$ip" 'bash -s' <<'REMOTE'
set -euo pipefail
F=/opt/fl-client/fl_ids_client.py
[ -f "$F" ] || { echo "ERROR: missing $F"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
cp -f "$F" "${F}.bak_${TS}"

python3 - "$F" <<'PY'
import re, sys, pathlib
p = sys.argv[1]
s = pathlib.Path(p).read_text(encoding="utf-8")

pat = r'(^[ \t]*)return[ \t]+np\.zeros\(info\["n_features"\],[ \t]*dtype=np\.float32\),[ \t]*0\.0[ \t]*$'
m = re.search(pat, s, flags=re.M)
if not m:
    print("ERROR: target return line not found")
    sys.exit(2)

indent = m.group(1)
replacement = (
f"{indent}n = None\n"
f"{indent}try:\n"
f"{indent}    if isinstance(info, dict) and \"n_features\" in info:\n"
f"{indent}        n = int(info[\"n_features\"])\n"
f"{indent}    elif isinstance(info, list):\n"
f"{indent}        n = len(info)\n"
f"{indent}except Exception:\n"
f"{indent}    n = None\n"
f"{indent}if n is None:\n"
f"{indent}    try:\n"
f"{indent}        n = int(np.load(f\"{{SPLITS_DIR}}/feat_min.npy\").shape[0])\n"
f"{indent}    except Exception:\n"
f"{indent}        n = 0\n"
f"{indent}return np.zeros(n, dtype=np.float32), 0.0"
)

s2 = re.sub(pat, replacement, s, flags=re.M)
pathlib.Path(p).write_text(s2, encoding="utf-8")
print("OK: patched")
PY

echo
echo "--- verify (show the patched block vicinity) ---"
nl -ba "$F" | sed -n '55,105p' | sed -n '1,220p'
REMOTE
done

echo
echo "DONE"
