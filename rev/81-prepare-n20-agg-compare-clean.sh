#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/agg_compare_n20_clean_$TS"
mkdir -p "$OUT"/{label_flip_raw,backdoor_raw,manifests,logs}

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: map introuvable: $MAP"; exit 1; }

cp -f "$MAP" "$OUT/manifests/edges_map_20.txt"

for rd in "$RUN_DIR"/p15_backdoor/round*; do
  [ -d "$rd" ] || continue
  bn=$(basename "$rd")
  mkdir -p "$OUT/backdoor_raw/$bn"
  cp -f "$rd"/client_logs/fl-ids-*.json "$OUT/backdoor_raw/$bn/" 2>/dev/null || true
done

cat <<EOC > "$OUT/README.txt"
DOSSIER PROPRE POUR COMPARAISON N20 DES AGREGATEURS
run_dir=$RUN_DIR
map=$MAP

Etat initial:
- backdoor_raw: copié depuis p15_backdoor existant
- label_flip_raw: vide pour l'instant, sera rempli après rerun label_flip

Ordre obligatoire:
1. lancer rev/25-run-labelflip-n20-batch.sh avec un BASE_FABRIC nouveau
2. lancer immédiatement collect_label_flip_raw.sh
3. seulement après, calculer la comparaison FedAvg / Multi-Krum / TrimmedMean
EOC

cat <<EOC > "$OUT/collect_label_flip_raw.sh"
#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

RUN_DIR="$RUN_DIR"
OUT="$OUT"
MAP="$MAP"

ROUNDS=\${1:-5}

ok=0
fail=0
FAIL_FILE="\$OUT/logs/label_flip_collect_failures.txt"
: > "\$FAIL_FILE"

for r in \$(seq 1 "\$ROUNDS"); do
  r2=\$(printf '%02d' "\$r")
  mkdir -p "\$OUT/label_flip_raw/round\${r2}"
  while read -r cid ip; do
    [ -n "\${cid:-}" ] || continue
    remote="/opt/fl-client/logs/fl-ids-\${cid}-r\${r}.json"
    localf="\$OUT/label_flip_raw/round\${r2}/fl-ids-\${cid}-r\${r}.json"
    if scp -i "\$SSH_KEY" -o StrictHostKeyChecking=no ubuntu@"\$ip":"\$remote" "\$localf" >/dev/null 2>&1; then
      ok=\$((ok+1))
    else
      fail=\$((fail+1))
      echo "MISS round=\$r cid=\$cid ip=\$ip remote=\$remote" >> "\$FAIL_FILE"
    fi
  done < "\$MAP"
done

python3 - <<'PY' "\$OUT" "\$ok" "\$fail" "\$FAIL_FILE"
import json, sys
from pathlib import Path

out = Path(sys.argv[1])
ok = int(sys.argv[2])
fail = int(sys.argv[3])
fail_file = Path(sys.argv[4])

round_counts = {}
for rd in sorted((out / "label_flip_raw").glob("round*")):
    round_counts[rd.name] = len(list(rd.glob("fl-ids-*.json")))

summary = {
    "label_flip_raw_dir": str(out / "label_flip_raw"),
    "ok": ok,
    "fail": fail,
    "round_counts": round_counts,
    "failures_file": str(fail_file),
}
(out / "manifests" / "label_flip_collect_summary.json").write_text(json.dumps(summary, indent=2))
print(json.dumps(summary, indent=2))
PY
EOC

chmod +x "$OUT/collect_label_flip_raw.sh"

python3 - <<'PY' "$OUT"
import json, sys
from pathlib import Path

out = Path(sys.argv[1])

backdoor_counts = {}
for rd in sorted((out / "backdoor_raw").glob("round*")):
    backdoor_counts[rd.name] = len(list(rd.glob("fl-ids-*.json")))

summary = {
    "compare_dir": str(out),
    "backdoor_round_counts": backdoor_counts,
    "label_flip_round_counts": {},
    "status": "prepared"
}
(out / "manifests" / "prepare_summary.json").write_text(json.dumps(summary, indent=2))
print("COMPARE_DIR=", out)
print("SUMMARY_JSON=", out / "manifests" / "prepare_summary.json")
PY

echo "$OUT" > rev/.last_n20_compare_dir
echo "DONE"
