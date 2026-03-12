import os, json, hashlib, subprocess, time
import numpy as np

CLIENT_ID  = os.getenv("CLIENT_ID",  "edge-client-5-byz")
ROUND      = int(os.getenv("ROUND",  "1"))
SPLITS_DIR = os.getenv("SPLITS_DIR", "/home/ubuntu/byz-fed-ids-5g/phase6/splits")
MODEL_DIR  = os.getenv("MODEL_DIR",  "/tmp/fl_models_byz")
IPFS_PATH  = os.getenv("IPFS_PATH",  "/home/ubuntu/.ipfs")
LR         = float(os.getenv("LR",   "0.005"))
EPOCHS     = int(os.getenv("EPOCHS", "3"))
BYZ_TYPE   = os.getenv("BYZ_TYPE",  "label_flip")
BYZ_SCALE  = float(os.getenv("BYZ_SCALE", "10.0"))

os.makedirs(MODEL_DIR, exist_ok=True)

def sigmoid(z):
    return 1.0 / (1.0 + np.exp(-np.clip(z, -20, 20)))

def load_splits():
    X  = np.load(f"{SPLITS_DIR}/edge-client-5_train_X.npy")
    y  = np.load(f"{SPLITS_DIR}/edge-client-5_train_y.npy")
    Xt = np.load(f"{SPLITS_DIR}/edge-client-5_test_X.npy")
    yt = np.load(f"{SPLITS_DIR}/edge-client-5_test_y.npy")
    return X, y, Xt, yt

def train_honest(X, y, w, b):
    t0 = time.time()
    for _ in range(EPOCHS):
        for i in np.random.permutation(len(X)):
            p   = sigmoid(np.dot(X[i], w) + b)
            err = p - y[i]
            w  -= LR * err * X[i]
            b  -= LR * err
    return w, b, time.time() - t0

def evaluate(X, y, w, b):
    t0    = time.time()
    preds = (sigmoid(X @ w + b) >= 0.5).astype(int)
    tp = int(np.sum((preds==1)&(y==1))); fp = int(np.sum((preds==1)&(y==0)))
    fn = int(np.sum((preds==0)&(y==1))); tn = int(np.sum((preds==0)&(y==0)))
    acc  = (tp+tn)/max(len(y),1)
    prec = tp/max(tp+fp,1); rec = tp/max(tp+fn,1)
    f1   = 2*prec*rec/max(prec+rec,1e-9)
    return {"accuracy":round(acc,4),"f1":round(f1,4),
            "precision":round(prec,4),"recall":round(rec,4),
            "fpr":round(fp/max(fp+tn,1),4),
            "tp":tp,"fp":fp,"fn":fn,"tn":tn,"n_samples":len(y),
            "inf_latency_ms":round((time.time()-t0)*1000,2)}

def ipfs_add(data_bytes):
    tmp = f"/tmp/fl-byz-{CLIENT_ID}-r{ROUND}.json"
    with open(tmp,"wb") as f: f.write(data_bytes)
    h   = hashlib.sha256(data_bytes).hexdigest()
    env = {**os.environ,"IPFS_PATH":IPFS_PATH,
           "HOME":"/home/ubuntu","PATH":"/usr/local/bin:/usr/bin:/bin"}
    t0  = time.time()
    r   = subprocess.run(["ipfs","add","-q",tmp],capture_output=True,env=env)
    ms  = round((time.time()-t0)*1000,2)
    os.remove(tmp)
    cid = r.stdout.decode().strip()
    if not cid: raise RuntimeError(f"ipfs add failed: {r.stderr.decode()}")
    subprocess.run(["ipfs-cluster-ctl","pin","add",
                    "--replication-min","3","--replication-max","5",cid],
                   capture_output=True,env=env)
    return cid, h, ms

def main():
    t_total = time.time()
    X, y, Xt, yt = load_splits()
    np.random.seed(ROUND * 42)

    with open(f"{SPLITS_DIR}/feature_names.json") as f:
        info = json.load(f)
    n_feat = info["n_features"]

    if BYZ_TYPE == "label_flip":
        y_train = 1 - y
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y_train, w, b)

    elif BYZ_TYPE == "noise":
        w = np.random.randn(n_feat).astype(np.float32) * BYZ_SCALE
        b = float(np.random.randn() * BYZ_SCALE)
        t_train = 0.0

    elif BYZ_TYPE == "model_poison":
        w, b = np.zeros(n_feat, dtype=np.float32), 0.0
        w, b, t_train = train_honest(X, y, w, b)
        w = -w * BYZ_SCALE
        b = -b * BYZ_SCALE

    else:
        raise ValueError(f"Unknown BYZ_TYPE: {BYZ_TYPE}")

    train_m = evaluate(X, y, w, b)
    test_m  = evaluate(Xt, yt, w, b)
    print(f"[{CLIENT_ID}] round={ROUND} attack={BYZ_TYPE} "
          f"F1={test_m['f1']} fpr={test_m['fpr']}")

    update = {
        "client_id":     CLIENT_ID,
        "round":         ROUND,
        "timestamp":     int(time.time()*1e9),
        "n_features":    n_feat,
        "n_samples":     int(len(X)),
        "weights":       w.tolist(),
        "bias":          float(b),
        "byzantine":     True,
        "attack_type":   BYZ_TYPE,
        "train_metrics": train_m,
        "test_metrics":  test_m,
    }
    payload = json.dumps(update).encode()
    cid, sha256, t_ipfs = ipfs_add(payload)

    result = {**update, "cid": cid, "hash": sha256,
              "latencies": {"train_s": round(t_train,3),
                            "ipfs_add_ms": t_ipfs,
                            "total_s": round(time.time()-t_total,3)}}
    os.makedirs("/home/ubuntu/byz-fed-ids-5g/phase8/logs", exist_ok=True)
    with open(f"/home/ubuntu/byz-fed-ids-5g/phase8/logs/fl-byz-{CLIENT_ID}-r{ROUND}.json","w") as f:
        json.dump(result,f,indent=2)
    print(json.dumps(result,indent=2))

if __name__ == "__main__":
    main()
