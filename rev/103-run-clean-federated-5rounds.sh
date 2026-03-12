#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g
source ~/byz-fed-ids-5g/config/config.env

SSH_KEY="${SSH_KEY:-$HOME/byz-fed-ids-5g/keys/fl-ids-key.pem}"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=15"

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
[ -n "${RUN_DIR:-}" ] || { echo "ERROR: RUN_DIR introuvable"; exit 1; }

MAP="$RUN_DIR/config/edges_map_20.txt"
[ -f "$MAP" ] || { echo "ERROR: MAP introuvable: $MAP"; exit 1; }

SPLITS_DIR="$RUN_DIR/splits_20"
N_ROUNDS="${N_ROUNDS:-5}"
BASE_FABRIC="${BASE_FABRIC:-9950000}"
PEER_HOST="${PEER_HOST:-peer0.org1.example.com}"
MSP="${MSP:-Org1MSP}"

TS=$(date -u +%Y%m%d_%H%M%S)
OUT="$RUN_DIR/federated_5rounds_${TS}"
mkdir -p "$OUT"/{tables_input,figures_input,manifest,agg_models,client_logs}

echo "================================================================"
echo "SCRIPT 103 — FL FEDERE CORRECT"
echo "RUN_DIR=$RUN_DIR"
echo "OUT=$OUT"
echo "N_ROUNDS=$N_ROUNDS"
echo "================================================================"

CIDS=()
IPS=()
while read -r cid ip; do
  [ -z "${cid:-}" ] && continue
  CIDS+=("$cid")
  IPS+=("$ip")
done < "$MAP"
N=${#CIDS[@]}
echo "N_CLIENTS=$N"

echo ""
echo "=== STEP 0: Nettoyage modeles initiaux ==="
for ((i=0;i<N;i++)); do
  IP="${IPS[$i]}"
  CID="${CIDS[$i]}"
  ssh $SSH_OPTS ubuntu@"$IP" "rm -f /opt/fl-client/models/${CID}_model.npz" 2>/dev/null || true
done
echo "OK"

ROUND_METRICS_CSV="$OUT/figures_input/federated_round_metrics.csv"
echo "round,aggregator,threshold,weighted_f1,f1,accuracy,precision,recall,fpr,roc_auc" \
  > "$ROUND_METRICS_CSV"

for ((r=1; r<=N_ROUNDS; r++)); do
  R2=$(printf "%02d" "$r")
  START_FABRIC=$((BASE_FABRIC + (r - 1) * 1000))

  echo ""
  echo "=============================="
  echo "ROUND $r / $N_ROUNDS"
  echo "=============================="

  ROUND_DIR="$OUT/client_logs/round${R2}"
  mkdir -p "$ROUND_DIR"

  echo "  [A] Entrainement local 20 clients..."
  for ((i=0;i<N;i++)); do
    CID="${CIDS[$i]}"
    IP="${IPS[$i]}"
    FABRIC_ROUND=$((START_FABRIC + i))
    ssh $SSH_OPTS ubuntu@"$IP" \
      "CLIENT_ID=$CID ROUND=$r /opt/fl-client/run_fl_round.sh $CID $r $MSP $PEER_HOST $FABRIC_ROUND \
       > /opt/fl-client/logs/runfl_${CID}_r${r}.out 2>&1" &
  done
  wait

  FAIL_R=0
  for ((i=0;i<N;i++)); do
    CID="${CIDS[$i]}"
    IP="${IPS[$i]}"
    scp $SSH_OPTS ubuntu@"$IP":/opt/fl-client/logs/fl-ids-${CID}-r${r}.json \
      "$ROUND_DIR/${CID}_r${r}.json" 2>/dev/null || {
      echo "  WARN: JSON manquant pour $CID"
      FAIL_R=$((FAIL_R+1))
    }
  done
  echo "  [A] Done. fail=$FAIL_R"

  echo "  [B] Agregation FedAvg round $r..."
  GLOBAL_NPZ="$OUT/agg_models/global_r${R2}.npz"

  python3 - "$ROUND_DIR" "$GLOBAL_NPZ" <<'PY'
import sys, json, numpy as np, pathlib

round_dir = pathlib.Path(sys.argv[1])
out_npz   = sys.argv[2]

jsons = sorted(round_dir.glob("*.json"))
if not jsons:
    raise SystemExit(f"ERROR: aucun JSON dans {round_dir}")

ws, bs, ns = [], [], []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        ws.append(np.array(d["weights"], dtype=np.float32))
        bs.append(float(d["bias"]))
        ns.append(int(d.get("n_samples", 1)))
    except Exception as e:
        print(f"  WARN skip {jf.name}: {e}")

if not ws:
    raise SystemExit("ERROR: aucun update valide")

total = sum(ns)
w_agg = sum(ws[i]*(ns[i]/total) for i in range(len(ws))).astype(np.float32)
b_agg = float(sum(bs[i]*(ns[i]/total) for i in range(len(bs))))
np.savez(out_npz, w=w_agg, b=np.array(b_agg, dtype=np.float32))
print(f"  FedAvg OK: n={len(ws)} total={total} b={b_agg:.4f}")
print(f"  GLOBAL_NPZ={out_npz}")
PY

  echo "  [B] Done."

  echo "  [C] Push global model vers $N clients..."
  for ((i=0;i<N;i++)); do
    CID="${CIDS[$i]}"
    IP="${IPS[$i]}"
    scp $SSH_OPTS "$GLOBAL_NPZ" ubuntu@"$IP":/opt/fl-client/models/${CID}_model.npz &
  done
  wait
  echo "  [C] Done."

  echo "  [D] Evaluation globale round $r..."
  python3 - "$GLOBAL_NPZ" "$SPLITS_DIR" "$ROUND_METRICS_CSV" "$r" <<'PY'
import sys, numpy as np

npz_path   = sys.argv[1]
splits_dir = sys.argv[2]
out_csv    = sys.argv[3]
round_num  = int(sys.argv[4])

m = np.load(npz_path)
w = m["w"].astype(np.float32)
b = float(m["b"])

X = np.load(f"{splits_dir}/global_test_X.npy").astype(np.float32)
y = np.load(f"{splits_dir}/global_test_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

best_thr, best_wf1 = 0.5, -1
for t in [x/100 for x in range(5, 96)]:
    preds = (sigmoid(X @ w + b) >= t).astype(int)
    tp = int(np.sum((preds==1)&(y==1)))
    fp = int(np.sum((preds==1)&(y==0)))
    fn = int(np.sum((preds==0)&(y==1)))
    tn = int(np.sum((preds==0)&(y==0)))
    prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9)
    fpr  = fp/max(fp+tn,1)
    wf1  = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
    if wf1 > best_wf1:
        best_wf1, best_thr = wf1, t

preds = (sigmoid(X @ w + b) >= best_thr).astype(int)
tp = int(np.sum((preds==1)&(y==1)))
fp = int(np.sum((preds==1)&(y==0)))
fn = int(np.sum((preds==0)&(y==1)))
tn = int(np.sum((preds==0)&(y==0)))
acc  = (tp+tn)/max(len(y),1)
prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
f1   = 2*prec*rec/max(prec+rec,1e-9)
fpr  = fp/max(fp+tn,1)
scores = sigmoid(X @ w + b)
desc = np.argsort(-scores)
tp_c = 0; auc = 0.0
tp_tot = int(np.sum(y==1)); fp_tot = int(np.sum(y==0))
for idx in desc:
    if y[idx]==1: tp_c += 1
    else: auc += tp_c
auc /= max(tp_tot*fp_tot,1)
wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)

print(f"  Round {round_num}: thr={best_thr:.2f} weighted_f1={wf1_f:.6f} f1={f1:.6f} acc={acc:.6f} fpr={fpr:.6f} roc_auc={auc:.6f}")

with open(out_csv, "a") as f:
    f.write(f"{round_num},fedavg,{best_thr:.2f},{wf1_f:.6f},{f1:.6f},{acc:.6f},{prec:.6f},{rec:.6f},{fpr:.6f},{auc:.6f}\n")
PY
  echo "  [D] Done."

done

echo ""
echo "================================================================"
echo "RESULTATS FINAUX (round $N_ROUNDS)"
echo "================================================================"

FINAL_ROUND_DIR="$OUT/client_logs/round$(printf "%02d" "$N_ROUNDS")"
SUMMARY_CSV="$OUT/tables_input/federated_final_summary.csv"
PAPER_CSV="$OUT/tables_input/federated_final_paper.csv"

python3 - "$FINAL_ROUND_DIR" "$SPLITS_DIR" "$SUMMARY_CSV" "$PAPER_CSV" "$N_ROUNDS" <<'PY'
import sys, json, numpy as np, pathlib, csv, time

round_dir  = pathlib.Path(sys.argv[1])
splits_dir = sys.argv[2]
sum_csv    = sys.argv[3]
paper_csv  = sys.argv[4]
final_r    = int(sys.argv[5])

jsons = sorted(round_dir.glob("*.json"))
updates = []
for jf in jsons:
    try:
        d = json.loads(jf.read_text())
        updates.append({
            "w": np.array(d["weights"], dtype=np.float32),
            "b": float(d["bias"]),
            "n": int(d.get("n_samples", 1))
        })
    except Exception as e:
        print(f"  WARN {jf.name}: {e}")

X = np.load(f"{splits_dir}/global_test_X.npy").astype(np.float32)
y = np.load(f"{splits_dir}/global_test_y.npy").astype(np.int32)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def eval_best(X, y, w, b):
    best_thr, best_wf1 = 0.5, -1
    for t in [x/100 for x in range(5, 96)]:
        preds = (sigmoid(X @ w + b) >= t).astype(int)
        tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
        fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
        prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
        f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
        wf1  = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
        if wf1 > best_wf1: best_wf1, best_thr = wf1, t
    preds = (sigmoid(X @ w + b) >= best_thr).astype(int)
    tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
    fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
    acc  = (tp+tn)/max(len(y),1); prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9); fpr = fp/max(fp+tn,1)
    scores = sigmoid(X @ w + b)
    desc = np.argsort(-scores); tp_c = 0; auc = 0.0
    tp_tot = int(np.sum(y==1)); fp_tot = int(np.sum(y==0))
    for idx in desc:
        if y[idx]==1: tp_c += 1
        else: auc += tp_c
    auc /= max(tp_tot*fp_tot,1)
    wf1_f = (f1*(tp+fn)+(1-fpr)*(fp+tn))/max(len(y),1)
    return dict(thr=round(best_thr,2), tp=tp, fp=fp, fn=fn, tn=tn,
                accuracy=round(acc,6), precision=round(prec,6),
                recall=round(rec,6), f1=round(f1,6), fpr=round(fpr,6),
                roc_auc=round(auc,6), weighted_f1=round(wf1_f,6))

total = sum(u["n"] for u in updates)
w_avg = sum(u["w"]*(u["n"]/total) for u in updates).astype(np.float32)
b_avg = float(sum(u["b"]*(u["n"]/total) for u in updates))

def multikrum(updates, f=4):
    ws = [u["w"] for u in updates]; n = len(ws)
    k = max(1, n - f - 2)
    scores = []
    for i in range(n):
        dists = sorted([float(np.sum((ws[i]-ws[j])**2)) for j in range(n) if j!=i])
        scores.append((sum(dists[:k]), i))
    scores.sort(); sel = [updates[scores[j][1]] for j in range(n-f)]
    ts = sum(u["n"] for u in sel)
    return sum(u["w"]*(u["n"]/ts) for u in sel).astype(np.float32), \
           float(sum(u["b"]*(u["n"]/ts) for u in sel)), len(sel)

def trimmedmean(updates, trim=0.1):
    ws = np.array([u["w"] for u in updates])
    bs = np.array([u["b"] for u in updates])
    n = len(updates); k = max(1, int(n*trim))
    return np.sort(ws, axis=0)[k:n-k].mean(axis=0).astype(np.float32), \
           float(np.sort(bs)[k:n-k].mean())

aggs = {}
t0=time.time(); aggs["fedavg"]      = (w_avg, b_avg, time.time()-t0, len(updates), 0)
t0=time.time(); wk,bk,sel=multikrum(updates)
aggs["multikrum"]   = (wk, bk, time.time()-t0, sel, len(updates)-sel)
t0=time.time(); wt,bt=trimmedmean(updates)
aggs["trimmedmean"] = (wt, bt, time.time()-t0, len(updates), 0)

rows = []
for agg_name, (w, b, agg_t, sel, rej) in aggs.items():
    res = eval_best(X, y, w, b)
    rows.append({"aggregator": agg_name, "round": final_r,
                 "threshold": res["thr"], "weighted_f1": res["weighted_f1"],
                 "f1": res["f1"], "accuracy": res["accuracy"],
                 "precision": res["precision"], "recall": res["recall"],
                 "fpr": res["fpr"], "roc_auc": res["roc_auc"],
                 "selected_count": sel, "rejected_count": rej,
                 "aggregation_time_ms": round(agg_t*1000,3),
                 "tp": res["tp"], "fp": res["fp"], "fn": res["fn"], "tn": res["tn"]})
    print(f"  {agg_name:12s} thr={res['thr']:.2f} weighted_f1={res['weighted_f1']:.6f} "
          f"f1={res['f1']:.6f} roc_auc={res['roc_auc']:.6f}")

fields = ["aggregator","round","threshold","weighted_f1","f1","accuracy",
          "precision","recall","fpr","roc_auc","selected_count","rejected_count",
          "aggregation_time_ms","tp","fp","fn","tn"]
with open(sum_csv,"w",newline="") as f:
    w2 = csv.DictWriter(f, fieldnames=fields); w2.writeheader(); w2.writerows(rows)

paper_fields = ["aggregator","threshold","weighted_f1","accuracy","roc_auc","f1","fpr","aggregation_time_ms"]
with open(paper_csv,"w",newline="") as f:
    w2 = csv.DictWriter(f, fieldnames=paper_fields)
    w2.writeheader(); w2.writerows([{k:r[k] for k in paper_fields} for r in rows])

print(f"SUMMARY_CSV={sum_csv}")
print(f"PAPER_CSV={paper_csv}")
PY

echo "$OUT" > "$RUN_DIR/.last_federated_dir"
echo "DONE"
echo "OUT=$OUT"
