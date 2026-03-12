#!/bin/bash
# 64-ipfs-storage-retrieval-by-size.sh — version corrigée
# Supprimé : --wait (bloque), 50MB/100MB (trop lent)
# Ajouté   : timeout, progress, output immédiat
set -uo pipefail

cd ~/byz-fed-ids-5g
source config/config.env

SSH_KEY=${SSH_KEY:-$HOME/byz-fed-ids-5g/keys/fl-ids-key.pem}
TS=$(date -u +%Y%m%d_%H%M%S)
OUT_DIR="$HOME/byz-fed-ids-5g/phase7/results"
RAW_CSV="$OUT_DIR/s_ipfs_size_benchmark_raw_${TS}.csv"
AVG_CSV="$OUT_DIR/s_ipfs_size_benchmark_5node_avg_${TS}.csv"
AVG_JSON="$OUT_DIR/s_ipfs_size_benchmark_5node_avg_${TS}.json"
WORK="$HOME/byz-fed-ids-5g/tmp/ipfs_size_bench_${TS}"

mkdir -p "$WORK" "$OUT_DIR"

LOCAL_IP="$(hostname -I | awk '{print $1}')"
echo "[INFO] local_ip=$LOCAL_IP  ts=$TS"

# Collecter les IPs IPFS
NODES=()
if [ -n "${IPFS_NODE_IPS:-}" ]; then
  read -r -a NODES <<< "$IPFS_NODE_IPS"
else
  for v in "${VM1_IP:-}" "${VM2_IP:-}" "${VM3_IP:-}" "${VM9_IP:-}" "${VM10_IP:-}"; do
    [ -n "${v:-}" ] && NODES+=("$v")
  done
fi

[ ${#NODES[@]} -ge 1 ] || { echo "ERROR: aucune IP IPFS trouvée"; exit 1; }
ORIGIN="${NODES[0]}"
echo "[INFO] origin=$ORIGIN  nodes=(${NODES[*]})"

REPS_SMALL="${REPS_SMALL:-5}"
REPS_BIG="${REPS_BIG:-3}"
IPFS_TIMEOUT="${IPFS_TIMEOUT:-30}"   # secondes max par opération

echo "size_label,bytes,cid,op,node,rep,ms,kbps" > "$RAW_CSV"
echo "[INFO] RAW_CSV=$RAW_CSV"

# ── Tailles : sans 50MB/100MB pour éviter blocage ────────────────────────────
SIZES_LABELS=("1KB"  "10KB"  "100KB" "1MB"  "10MB")
SIZES_BYTES=(  1024   10240   102400  1048576 10485760)

SSH_BASE="ssh -n -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

run_remote() {
  local ip="$1"; local cmd="$2"
  $SSH_BASE ubuntu@"$ip" "$cmd"
}

for i in "${!SIZES_LABELS[@]}"; do
  LABEL="${SIZES_LABELS[$i]}"
  NBYTES="${SIZES_BYTES[$i]}"
  REPS=$REPS_SMALL
  [ "$NBYTES" -gt 1048576 ] && REPS=$REPS_BIG

  echo ""
  echo "=== [$LABEL / ${NBYTES}B] génération fichier... ==="

  FPATH="$WORK/file_${LABEL}.bin"
  dd if=/dev/urandom of="$FPATH" bs=1024 count=$(( NBYTES / 1024 )) status=none 2>/dev/null \
    || dd if=/dev/urandom of="$FPATH" bs=1 count="$NBYTES" status=none
  echo "  [STORE] fichier créé ($LABEL)"

  # Copier vers origin si distant
  if [ "$ORIGIN" != "$LOCAL_IP" ]; then
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$FPATH" ubuntu@"$ORIGIN":/tmp/ipfsbench_${LABEL}.bin
    ORIGIN_FILE="/tmp/ipfsbench_${LABEL}.bin"
  else
    ORIGIN_FILE="$FPATH"
  fi

  # ── STORE : ipfs add (sans pin cluster bloquant) ──────────────────────────
  if [ "$ORIGIN" = "$LOCAL_IP" ]; then
    ADD_OUT=$(timeout "$IPFS_TIMEOUT" ipfs add -Q "$ORIGIN_FILE" 2>/dev/null) || {
      echo "  [WARN] ipfs add timeout/erreur pour $LABEL — skip"
      continue
    }
  else
    ADD_OUT=$(run_remote "$ORIGIN" \
      "timeout $IPFS_TIMEOUT ipfs add -Q $ORIGIN_FILE 2>/dev/null") || {
      echo "  [WARN] ipfs add timeout/erreur pour $LABEL sur $ORIGIN — skip"
      continue
    }
  fi
  CID=$(echo "$ADD_OUT" | tr -d '[:space:]')
  echo "  [STORE] CID=$CID"

  # Mesure temps store
  if [ "$ORIGIN" = "$LOCAL_IP" ]; then
    STORE_MS=$(python3 -c "
import subprocess, time, sys
t0=time.perf_counter()
r=subprocess.run(['ipfs','add','-Q','$ORIGIN_FILE'],capture_output=True,text=True)
t1=time.perf_counter()
print(f'{(t1-t0)*1000:.3f}')
" 2>/dev/null)
  else
    STORE_MS=$(run_remote "$ORIGIN" "python3 -c \"
import subprocess,time
t0=time.perf_counter()
subprocess.run(['ipfs','add','-Q','$ORIGIN_FILE'],capture_output=True)
t1=time.perf_counter()
print(f'{(t1-t0)*1000:.3f}')
\"" 2>/dev/null) || STORE_MS=""
  fi

  if [ -n "${STORE_MS:-}" ]; then
    STORE_KBPS=$(python3 -c "print(f'{($NBYTES/1024.0)/($STORE_MS/1000.0):.3f}')" 2>/dev/null || echo "")
    echo "$LABEL,$NBYTES,$CID,store_ms,$ORIGIN,1,$STORE_MS,${STORE_KBPS:-}" >> "$RAW_CSV"
    echo "  [STORE] ${STORE_MS}ms  ${STORE_KBPS:-?}KB/s"
  fi

  # Pin cluster sans --wait (non-bloquant)
  if [ "$ORIGIN" = "$LOCAL_IP" ]; then
    timeout "$IPFS_TIMEOUT" ipfs-cluster-ctl pin add "$CID" >/dev/null 2>&1 || true
  else
    run_remote "$ORIGIN" "timeout $IPFS_TIMEOUT ipfs-cluster-ctl pin add $CID" >/dev/null 2>&1 || true
  fi
  echo "  [PIN] pin add lancé (sans --wait)"

  # ── GET : mesure sur chaque nœud ────────────────────────────────────────
  for NODE_IP in "${NODES[@]}"; do
    echo "  [GET] node=$NODE_IP  reps=$REPS..."

    GET_CODE="
import subprocess,time,sys
vals=[]
for _ in range($REPS):
    t0=time.perf_counter()
    r=subprocess.run(['ipfs','cat','$CID'],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=$IPFS_TIMEOUT)
    t1=time.perf_counter()
    if r.returncode==0:
        vals.append((t1-t0)*1000.0)
for v in vals:
    print(f'{v:.3f}')
"

    if [ "$NODE_IP" = "$LOCAL_IP" ]; then
      GET_OUT=$(python3 - <<< "$GET_CODE" 2>/dev/null) || GET_OUT=""
    else
      GET_OUT=$(run_remote "$NODE_IP" "python3 -c $(printf '%q' "$GET_CODE")" 2>/dev/null) || GET_OUT=""
    fi

    if [ -z "$GET_OUT" ]; then
      echo "    [WARN] aucun résultat get sur $NODE_IP"
      continue
    fi

    REP=1
    while IFS= read -r MS_VAL; do
      [ -z "$MS_VAL" ] && continue
      KBPS=$(python3 -c "print(f'{($NBYTES/1024.0)/($MS_VAL/1000.0):.3f}')" 2>/dev/null || echo "")
      echo "$LABEL,$NBYTES,$CID,get_ms,$NODE_IP,$REP,$MS_VAL,${KBPS:-}" >> "$RAW_CSV"
      REP=$((REP+1))
    done <<< "$GET_OUT"
    echo "    → $((REP-1)) mesures enregistrées"
  done

done

echo ""
echo "=== Calcul moyennes ==="

python3 - "$RAW_CSV" "$AVG_CSV" "$AVG_JSON" <<'PY'
import sys, json
import pandas as pd
import numpy as np

raw, avg_csv, avg_json = sys.argv[1:4]
df = pd.read_csv(raw)
df["ms"] = pd.to_numeric(df["ms"], errors="coerce")

out_rows = []
for (size_label, nbytes), g in df.groupby(["size_label","bytes"], sort=False):
    cid = g["cid"].dropna().astype(str).iloc[0] if len(g["cid"].dropna()) else ""
    store = g[g["op"]=="store_ms"]["ms"].dropna()
    get_ms = g[g["op"]=="get_ms"]["ms"].dropna()

    store_ms   = float(store.mean()) if len(store) else None
    store_kbps = (nbytes/1024.0)/(store_ms/1000.0) if store_ms else None
    get_avg    = float(get_ms.mean()) if len(get_ms) else None
    get_p50    = float(np.percentile(get_ms, 50)) if len(get_ms) else None
    get_p95    = float(np.percentile(get_ms, 95)) if len(get_ms) else None
    get_min    = float(get_ms.min()) if len(get_ms) else None
    get_max    = float(get_ms.max()) if len(get_ms) else None
    get_kbps   = (nbytes/1024.0)/(get_avg/1000.0) if get_avg else None

    row = {
        "size_label":    size_label,
        "bytes":         int(nbytes),
        "cid":           cid,
        "store_ms":      round(store_ms,3)   if store_ms   else None,
        "store_kbps":    round(store_kbps,3) if store_kbps else None,
        "get_avg_ms":    round(get_avg,3)    if get_avg    else None,
        "get_p50_ms":    round(get_p50,3)    if get_p50    else None,
        "get_p95_ms":    round(get_p95,3)    if get_p95    else None,
        "get_min_ms":    round(get_min,3)    if get_min    else None,
        "get_max_ms":    round(get_max,3)    if get_max    else None,
        "get_kbps":      round(get_kbps,3)   if get_kbps   else None,
        "get_n":         int(len(get_ms)),
    }
    out_rows.append(row)
    print(f"  {size_label:8s}  store={store_ms:.1f}ms  get_p50={get_p50:.1f}ms  get_kbps={get_kbps:.1f}" if store_ms and get_p50 and get_kbps else f"  {size_label}: données partielles")

out = pd.DataFrame(out_rows)
out.to_csv(avg_csv, index=False)
with open(avg_json,"w") as f:
    json.dump({"raw_csv":raw,"avg_csv":avg_csv,"rows":out_rows}, f, indent=2)

print(f"\nAVG_CSV={avg_csv}")
print(f"AVG_JSON={avg_json}")
PY

echo ""
echo "RAW_CSV=$RAW_CSV"
echo "AVG_CSV=$AVG_CSV"
echo "AVG_JSON=$AVG_JSON"
echo "[DONE]"
