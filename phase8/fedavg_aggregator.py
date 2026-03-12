import os, json, hashlib, subprocess, time, sys
import numpy as np

IPFS_PATH  = os.getenv("IPFS_PATH", "/home/ubuntu/.ipfs")
LOG_DIR    = os.path.expanduser("~/byz-fed-ids-5g/phase8/logs")
SPLITS_DIR = os.path.expanduser("~/byz-fed-ids-5g/phase6/splits")
SSH_KEY    = os.path.expanduser(os.getenv("SSH_KEY", "~/.ssh/id_rsa"))
os.makedirs(LOG_DIR, exist_ok=True)

def fetch(ip, path):
    r = subprocess.run(
        ["ssh","-i",SSH_KEY,"-o","StrictHostKeyChecking=no",
         f"ubuntu@{ip}", f"cat {path}"],
        capture_output=True, timeout=30)
    return json.loads(r.stdout.decode())

def evaluate(w, b):
    X = np.load(f"{SPLITS_DIR}/global_test_X.npy")
    y = np.load(f"{SPLITS_DIR}/global_test_y.npy")
    p = (1/(1+np.exp(-np.clip(X@w+b,-20,20))) >= 0.5).astype(int)
    tp=int(np.sum((p==1)&(y==1))); fp=int(np.sum((p==1)&(y==0)))
    fn=int(np.sum((p==0)&(y==1))); tn=int(np.sum((p==0)&(y==0)))
    acc=(tp+tn)/max(len(y),1)
    prec=tp/max(tp+fp,1); rec=tp/max(tp+fn,1)
    f1=2*prec*rec/max(prec+rec,1e-9)
    return {"accuracy":round(acc,4),"f1":round(f1,4),
            "fpr":round(fp/max(fp+tn,1),4),"recall":round(rec,4)}

def main():
    round_num = int(sys.argv[1])
    entries   = sys.argv[2].split("|")
    updates   = []
    for e in entries:
        ip, path, cid = e.split(":")
        u = fetch(ip, path)
        updates.append(u)
        print(f"  [FedAvg] {u['client_id']:<28} F1={u['test_metrics']['f1']} byz={u.get('byzantine',False)}")

    w_avg = np.mean([np.array(u["weights"],dtype=np.float32) for u in updates],axis=0)
    b_avg = float(np.mean([u["bias"] for u in updates]))
    metrics = evaluate(w_avg, b_avg)
    print(f"  [FedAvg] global F1={metrics['f1']} fpr={metrics['fpr']}")

    log = {"phase":"P8","round":round_num,"algorithm":"FedAvg",
           "n_clients":len(updates),"global_metrics":metrics,
           "byzantine_detected":False,"rejected":[],
           "timestamp":int(time.time()*1e9)}
    lp = f"{LOG_DIR}/fedavg_r{round_num:02d}.json"
    with open(lp,"w") as f: json.dump(log,f,indent=2)
    print(json.dumps(log,indent=2))

if __name__ == "__main__":
    main()
