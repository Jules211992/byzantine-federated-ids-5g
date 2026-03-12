import os, json, hashlib, subprocess, time, sys
import numpy as np

IPFS_PATH = os.getenv("IPFS_PATH", "/home/ubuntu/.ipfs")
OUT_DIR   = os.path.expanduser("~/byz-fed-ids-5g/phase7/models")
LOG_DIR   = os.path.expanduser("~/byz-fed-ids-5g/phase7/logs")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

def fetch_update_ssh(ip, log_path, ssh_key):
    if ip == "local":
        with open(log_path) as f:
            return json.load(f)
    r = subprocess.run(
        ["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no",
         f"ubuntu@{ip}", f"cat {log_path}"],
        capture_output=True, timeout=30)
    if r.returncode != 0:
        raise RuntimeError(f"ssh fetch failed {ip}:{log_path}: {r.stderr.decode()}")
    return json.loads(r.stdout.decode())

def multi_krum(updates, f):
    n       = len(updates)
    k       = n - f
    weights = np.array([u["weights"] for u in updates], dtype=np.float32)
    scores  = np.zeros(n)
    for i in range(n):
        dists = sorted(
            float(np.sum((weights[i] - weights[j])**2))
            for j in range(n) if j != i
        )
        neighbors = max(n - f - 2, 1)
        scores[i] = sum(dists[:neighbors])
    ranked   = np.argsort(scores)
    selected = ranked[:k].tolist()
    rejected = ranked[k:].tolist()
    return selected, rejected, scores.tolist()

def fedavg(updates, selected_idx):
    w_avg = np.mean(
        [np.array(updates[i]["weights"], dtype=np.float32) for i in selected_idx],
        axis=0)
    b_avg = float(np.mean([updates[i]["bias"] for i in selected_idx]))
    return w_avg, b_avg

def evaluate_global(w, b, splits_dir):
    X  = np.load(f"{splits_dir}/global_test_X.npy")
    y  = np.load(f"{splits_dir}/global_test_y.npy")
    t0 = time.time()
    z  = X @ w + b
    p  = (1.0 / (1.0 + np.exp(-np.clip(z,-20,20))) >= 0.5).astype(int)
    tp = int(np.sum((p==1)&(y==1))); fp = int(np.sum((p==1)&(y==0)))
    fn = int(np.sum((p==0)&(y==1))); tn = int(np.sum((p==0)&(y==0)))
    acc  = (tp+tn)/max(len(y),1)
    prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9)
    fpr  = fp/max(fp+tn,1)
    return {"accuracy":round(acc,4),"f1":round(f1,4),"precision":round(prec,4),
            "recall":round(rec,4),"fpr":round(fpr,4),
            "eval_ms":round((time.time()-t0)*1000,2)}

def ipfs_add_global(data_bytes):
    tmp = "/tmp/global-model-p7.json"
    with open(tmp,"wb") as f:
        f.write(data_bytes)
    h   = hashlib.sha256(data_bytes).hexdigest()
    env = {**os.environ,"IPFS_PATH":IPFS_PATH,
           "HOME":os.path.expanduser("~"),"PATH":"/usr/local/bin:/usr/bin:/bin"}
    r   = subprocess.run(["ipfs","add","-q",tmp],capture_output=True,env=env)
    cid = r.stdout.decode().strip()
    subprocess.run(["ipfs-cluster-ctl","pin","add",
                    "--replication-min","3","--replication-max","5",cid],
                   capture_output=True,env=env)
    return cid, h

def main():
    if len(sys.argv) < 4:
        print("Usage: python3 multi_krum_aggregator.py <round> <f> <ip:logpath:client_id,...>")
        sys.exit(1)

    round_num  = int(sys.argv[1])
    f          = int(sys.argv[2])
    entries    = sys.argv[3].split("|")
    ssh_key    = os.path.expanduser(os.getenv("SSH_KEY","~/.ssh/id_rsa"))
    splits_dir = os.path.expanduser("~/byz-fed-ids-5g/phase6/splits")

    print(f"\n=== Multi-Krum — round={round_num} n={len(entries)} f={f} ===")

    updates = []
    for entry in entries:
        ip, log_path, client_id = entry.split(":")
        print(f"  Fetch {client_id} depuis {ip}...")
        u = fetch_update_ssh(ip, log_path, ssh_key)
        u["_source_ip"] = ip
        updates.append(u)
        print(f"    F1={u['test_metrics']['f1']} fpr={u['test_metrics']['fpr']} "
              f"byzantine={u.get('byzantine',False)}")

    t0 = time.time()
    selected, rejected, scores = multi_krum(updates, f)
    t_krum = round((time.time()-t0)*1000,2)

    print(f"\n  Scores Multi-Krum :")
    for i,u in enumerate(updates):
        tag = "SELECTED ✓" if i in selected else "REJECTED  ✗ (byzantin suspect)"
        print(f"    [{i}] {u['client_id']:<28} score={scores[i]:.2f}  {tag}")

    selected_clients = [updates[i]["client_id"] for i in selected]
    rejected_clients = [updates[i]["client_id"] for i in rejected]

    w_global, b_global = fedavg(updates, selected)
    global_metrics     = evaluate_global(w_global, b_global, splits_dir)

    print(f"\n  Modèle global (FedAvg {len(selected)} clients) :")
    print(f"    F1={global_metrics['f1']}  acc={global_metrics['accuracy']}  "
          f"fpr={global_metrics['fpr']}  eval={global_metrics['eval_ms']}ms")

    payload    = json.dumps({
        "round":round_num,"algorithm":"Multi-Krum","f_byzantine":f,
        "selected":selected_clients,"rejected":rejected_clients,
        "krum_scores":{updates[i]["client_id"]:round(scores[i],2) for i in range(len(updates))},
        "global_metrics":global_metrics,"weights":w_global.tolist(),"bias":float(b_global),
        "timestamp":int(time.time()*1e9),"krum_time_ms":t_krum,
    }).encode()
    cid_global, hash_global = ipfs_add_global(payload)

    log = {
        "phase":"P7","round":round_num,
        "cid_global":cid_global,"hash_global":hash_global,
        "selected":selected_clients,"rejected":rejected_clients,
        "krum_scores":{updates[i]["client_id"]:round(scores[i],2) for i in range(len(updates))},
        "global_metrics":global_metrics,"krum_time_ms":t_krum,
        "byzantine_detected":len(rejected_clients)>0,
    }
    log_path = f"{LOG_DIR}/p7_round{round_num:02d}_{time.strftime('%Y%m%d_%H%M%S')}.json"
    with open(log_path,"w") as f_log:
        json.dump(log,f_log,indent=2)
    print(f"  CID_global={cid_global[:20]}...  Log={log_path}")
    print(f"  Byzantin détecté : {'✓ OUI' if log['byzantine_detected'] else '✗ NON'}")
    print(json.dumps(log,indent=2))

if __name__ == "__main__":
    main()
