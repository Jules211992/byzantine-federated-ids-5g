import os, json, subprocess, time, sys
import numpy as np

IPFS_PATH  = os.getenv("IPFS_PATH", "/home/ubuntu/.ipfs")
LOG_DIR    = os.path.expanduser("~/byz-fed-ids-5g/phase8/logs")
SPLITS_DIR = os.path.expanduser("~/byz-fed-ids-5g/phase6/splits")
SSH_KEY    = os.path.expanduser(os.getenv("SSH_KEY", "~/.ssh/id_rsa"))
os.makedirs(LOG_DIR, exist_ok=True)

def fetch(ip, path):
    r = subprocess.run(
        ["ssh", "-i", SSH_KEY, "-o", "StrictHostKeyChecking=no",
         f"ubuntu@{ip}", f"cat {path}"],
        capture_output=True, timeout=30
    )
    if r.returncode != 0:
        raise RuntimeError(f"ssh fetch failed {ip}:{path}: {r.stderr.decode()}")
    return json.loads(r.stdout.decode())

def trimmed_mean_weights(updates, f):
    ws = np.array([u["weights"] for u in updates], dtype=np.float32)
    n = ws.shape[0]
    if n == 0:
        raise ValueError("no updates")
    trim = max(0, int(f))
    if 2 * trim >= n:
        trim = max(0, (n - 1) // 2)
    s = np.sort(ws, axis=0)
    if trim > 0:
        s = s[trim:n-trim, :]
    return np.mean(s, axis=0)

def trimmed_mean_bias(updates, f):
    bs = np.array([u["bias"] for u in updates], dtype=np.float32)
    n = bs.shape[0]
    trim = max(0, int(f))
    if 2 * trim >= n:
        trim = max(0, (n - 1) // 2)
    s = np.sort(bs)
    if trim > 0:
        s = s[trim:n-trim]
    return float(np.mean(s))

def evaluate(w, b):
    X = np.load(f"{SPLITS_DIR}/global_test_X.npy")
    y = np.load(f"{SPLITS_DIR}/global_test_y.npy")
    t0 = time.time()
    p = (1 / (1 + np.exp(-np.clip(X @ w + b, -20, 20))) >= 0.5).astype(int)
    tp = int(np.sum((p == 1) & (y == 1)))
    fp = int(np.sum((p == 1) & (y == 0)))
    fn = int(np.sum((p == 0) & (y == 1)))
    tn = int(np.sum((p == 0) & (y == 0)))
    acc = (tp + tn) / max(len(y), 1)
    prec = tp / max(tp + fp, 1)
    rec = tp / max(tp + fn, 1)
    f1 = 2 * prec * rec / max(prec + rec, 1e-9)
    return {
        "accuracy": round(acc, 4),
        "f1": round(f1, 4),
        "fpr": round(fp / max(fp + tn, 1), 4),
        "recall": round(rec, 4),
        "eval_ms": round((time.time() - t0) * 1000, 2)
    }

def main():
    if len(sys.argv) < 4:
        print("Usage: python3 trimmed_mean_aggregator.py <round> <f> <ip:logpath:client_id|...>")
        sys.exit(1)

    round_num = int(sys.argv[1])
    f = int(sys.argv[2])
    entries = sys.argv[3].split("|")

    updates = []
    for e in entries:
        ip, path, cid = e.split(":")
        u = fetch(ip, path)
        updates.append(u)
        print(f"  [TrimmedMean] {u['client_id']:<28} F1={u['test_metrics']['f1']} byz={u.get('byzantine', False)}")

    t0 = time.time()
    w_tm = trimmed_mean_weights(updates, f)
    b_tm = trimmed_mean_bias(updates, f)
    agg_ms = round((time.time() - t0) * 1000, 2)

    metrics = evaluate(w_tm, b_tm)
    print(f"  [TrimmedMean] global F1={metrics['f1']} fpr={metrics['fpr']} agg={agg_ms}ms")

    log = {
        "phase": "P8",
        "round": round_num,
        "algorithm": "TrimmedMean",
        "f_byzantine": f,
        "n_clients": len(updates),
        "global_metrics": metrics,
        "byzantine_detected": False,
        "rejected": [],
        "aggregation_time_ms": agg_ms,
        "timestamp": int(time.time() * 1e9)
    }

    lp = f"{LOG_DIR}/trimmedmean_r{round_num:02d}.json"
    with open(lp, "w") as f_out:
        json.dump(log, f_out, indent=2)

    print(json.dumps(log, indent=2))

if __name__ == "__main__":
    main()
