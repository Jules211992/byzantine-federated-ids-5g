import json, sys, os, subprocess, tempfile
import numpy as np

def run(cmd, env=None):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"cmd failed: {' '.join(cmd)}\n{r.stderr}")
    return r.stdout.strip()

def ipfs_cat(cid, ipfs_path=None):
    env = dict(os.environ)
    if ipfs_path:
        env["IPFS_PATH"] = ipfs_path
    env["HOME"] = env.get("HOME", "/home/ubuntu")
    env["PATH"] = env.get("PATH", "/usr/local/bin:/usr/bin:/bin")
    out = run(["ipfs", "cat", cid], env=env)
    return out

def extract_weights_bias(d):
    w = None
    b = None

    if "global_weights" in d:
        w = d["global_weights"]
        b = d.get("global_bias", 0.0)
    elif "weights" in d:
        w = d["weights"]
        b = d.get("bias", 0.0)
    elif "global_model" in d and isinstance(d["global_model"], dict) and "weights" in d["global_model"]:
        w = d["global_model"]["weights"]
        b = d["global_model"].get("bias", 0.0)

    if w is None:
        return None, None
    return np.array(w, dtype=np.float32), float(b)

def main():
    if len(sys.argv) < 4:
        print("usage: distribute_global.py <agg_log.json> <ssh_key> <client_id:ip> [client_id:ip] ...", file=sys.stderr)
        sys.exit(2)

    agg_log = sys.argv[1]
    ssh_key = sys.argv[2]
    pairs = sys.argv[3:]

    with open(agg_log) as f:
        d = json.load(f)

    w, b = extract_weights_bias(d)

    if w is None or w.size == 0:
        cid = d.get("cid_global") or d.get("cid")
        if not cid:
            raise RuntimeError("No weights in log and no cid_global/cid found to fetch from IPFS")

        ipfs_path = d.get("ipfs_path") or os.environ.get("IPFS_PATH")
        raw = ipfs_cat(cid, ipfs_path=ipfs_path)

        try:
            j = json.loads(raw)
        except Exception:
            j = None

        if isinstance(j, dict):
            w, b = extract_weights_bias(j)

        if w is None or w.size == 0:
            raise RuntimeError("No global weights found in aggregator log nor in IPFS payload")

    tmpdir = tempfile.mkdtemp(prefix="fl-global-")
    npz_path = os.path.join(tmpdir, "global_model.npz")
    np.savez(npz_path, w=w, b=np.array(b, dtype=np.float32))

    for p in pairs:
        if ":" not in p:
            raise RuntimeError(f"bad pair {p}, expected client_id:ip")
        client_id, ip = p.split(":", 1)

        remote_tmp = f"/tmp/global_model_{client_id}.npz"

        run(["scp", "-i", ssh_key, "-o", "StrictHostKeyChecking=no", npz_path, f"ubuntu@{ip}:{remote_tmp}"])

        remote_cmd = (
            f"sudo mkdir -p /opt/fl-client/models && "
            f"sudo mv {remote_tmp} /opt/fl-client/models/{client_id}_model.npz && "
            f"sudo chown -R ubuntu:ubuntu /opt/fl-client/models"
        )
        run(["ssh", "-i", ssh_key, "-o", "StrictHostKeyChecking=no", f"ubuntu@{ip}", remote_cmd])

    print("OK")

if __name__ == "__main__":
    main()
