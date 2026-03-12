#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

FILES_RAW=$(ls -t "$RUN_DIR"/manifest/5gnidd_files_raw_*.json 2>/dev/null | head -n 1 || true)
if [ -z "${FILES_RAW:-}" ]; then
  echo "ERROR: aucun 5gnidd_files_raw_*.json trouvé dans $RUN_DIR/manifest"
  exit 1
fi

TARGET="${1:-README.pdf}"
MODE="${2:-probe}"   # probe | download
TS=$(date -u +%Y%m%d_%H%M%S)

OUT_DIR="$RUN_DIR/dataset"
mkdir -p "$OUT_DIR" "$RUN_DIR/manifest"

OUT_PROBE="$RUN_DIR/manifest/5gnidd_probe_${TARGET//\//_}_${TS}.txt"
OUT_URL="$RUN_DIR/manifest/5gnidd_winning_url_${TARGET//\//_}_${TS}.txt"

python3 - "$FILES_RAW" "$TARGET" "$MODE" "$OUT_DIR" "$OUT_PROBE" "$OUT_URL" <<'PY'
import json, sys, os, subprocess, urllib.parse, time, hashlib

files_raw, target, mode, out_dir, out_probe, out_url = sys.argv[1:]

def sh(cmd):
    return subprocess.check_output(cmd, shell=True, text=True, stderr=subprocess.STDOUT)

with open(files_raw, "r") as f:
    obj = json.load(f)

items = obj if isinstance(obj, list) else obj.get("files", obj)
if not isinstance(items, list):
    raise SystemExit("ERROR: files_raw JSON format unexpected (not a list)")

t = target.strip()
if not t.startswith("/"):
    t2 = "/" + t
else:
    t2 = t

picked = None
for it in items:
    fp = it.get("file_path","")
    fn = it.get("file_name","")
    if fp == t2 or fp.endswith(t2) or fn == t or fn == os.path.basename(t):
        picked = it
        break

if not picked:
    raise SystemExit(f"ERROR: target not found in files list: {target}")

identifier = str(picked.get("identifier",""))
file_path  = str(picked.get("file_path",""))
file_name  = str(picked.get("file_name", os.path.basename(file_path)))
proj       = str(picked.get("project_identifier",""))
byte_size  = int(picked.get("byte_size") or 0)

checksum = picked.get("checksum") or {}
sha256 = ""
if isinstance(checksum, dict) and str(checksum.get("algorithm","")).upper() == "SHA-256":
    sha256 = str(checksum.get("value",""))

def urlenc_path(path):
    # keep slashes, encode spaces etc.
    return urllib.parse.quote(path, safe="/")

# Candidate URL patterns (on test en GET range 0-0 pour éviter de télécharger)
cands = []

# 1) by file identifier
cands += [
  f"https://ida.fairdata.fi/api/access/data/{identifier}",
  f"https://ida.fairdata.fi/api/access/data/{identifier}?download=1",
  f"https://ida.fairdata.fi/api/access/data/{identifier}?filename={urllib.parse.quote(file_name)}",
]

# 2) by project + path (if available)
if proj and file_path:
    ep = urlenc_path(file_path)
    cands += [
      f"https://ida.fairdata.fi/api/access/data/{proj}{ep}",
      f"https://ida.fairdata.fi/api/access/data/{proj}{ep}?download=1",
      f"https://ida.fairdata.fi/api/access/data/{proj}/{ep.lstrip('/')}",
      f"https://ida.fairdata.fi/api/access/data/{proj}/files{ep}",
    ]

# 3) fallbacks (some services accept "path" param)
if proj and file_path:
    ep = urlenc_path(file_path)
    cands += [
      f"https://ida.fairdata.fi/api/access/data?project={urllib.parse.quote(proj)}&path={urllib.parse.quote(file_path)}",
      f"https://ida.fairdata.fi/api/access/data?project={urllib.parse.quote(proj)}&path={urllib.parse.quote(ep)}",
    ]

# de-dup preserving order
seen=set()
uniq=[]
for u in cands:
    if u not in seen:
        seen.add(u); uniq.append(u)

hdr = []
hdr.append(f"FILES_RAW={files_raw}")
hdr.append(f"TARGET={target}")
hdr.append(f"IDENTIFIER={identifier}")
hdr.append(f"FILE_PATH={file_path}")
hdr.append(f"FILE_NAME={file_name}")
hdr.append(f"PROJECT_IDENTIFIER={proj}")
hdr.append(f"EXPECTED_BYTES={byte_size}")
hdr.append(f"EXPECTED_SHA256={sha256}")
hdr.append(f"N_CANDIDATES={len(uniq)}")

lines = []
lines += hdr
lines.append("")
lines.append("=== PROBE RESULTS (GET range 0-0) ===")

def probe(url):
    # range 0-0 => 1 byte if supported; -L follow redirects; output code + effective URL
    cmd = f"curl -sS -L --max-time 25 --retry 0 --range 0-0 -o /dev/null -w '%{{http_code}} %{{size_download}} %{{url_effective}}' '{url}'"
    try:
        out = sh(cmd).strip()
        parts = out.split(" ",2)
        code = parts[0]
        size = parts[1] if len(parts)>1 else "?"
        eff  = parts[2] if len(parts)>2 else ""
        return code, size, eff, ""
    except subprocess.CalledProcessError as e:
        txt = e.output.strip().replace("\n"," | ")
        return "ERR", "0", "", txt[:220]

best = None
for i,u in enumerate(uniq, start=1):
    code,size,eff,err = probe(u)
    tag = ""
    if code in ("200","206"):
        tag = "OK"
        if not best:
            best = (u, code, eff)
    elif code in ("301","302","303","307","308"):
        tag = "REDIR"
    elif code in ("401","403"):
        tag = "AUTH"
    elif code in ("404",):
        tag = "MISS"
    elif code == "ERR":
        tag = "ERR"
    else:
        tag = "OTHER"
    lines.append(f"[{i:02d}] {tag} code={code} size={size} url={u}")
    if eff:
        lines.append(f"     effective={eff}")
    if err:
        lines.append(f"     err={err}")

lines.append("")
if best:
    lines.append(f"WINNER={best[0]}")
else:
    lines.append("WINNER=NONE")

os.makedirs(os.path.dirname(out_probe), exist_ok=True)
with open(out_probe,"w") as f:
    f.write("\n".join(lines) + "\n")

print("\n".join(lines))
print("")
print(f"SAVED_PROBE={out_probe}")

if not best:
    raise SystemExit("ERROR: no working download endpoint found (code 200/206). Share the probe output.")

with open(out_url,"w") as f:
    f.write(best[0] + "\n")
print(f"SAVED_URL={out_url}")

if mode != "download":
    sys.exit(0)

out_path = os.path.join(out_dir, os.path.basename(file_path) if file_path else file_name)
tmp_path = out_path + ".part"

print("")
print("=== DOWNLOAD ===")
print(f"OUT={out_path}")

dl_cmd = f"curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 0 -o '{tmp_path}' '{best[0]}'"
print(f"CMD={dl_cmd}")
subprocess.check_call(dl_cmd, shell=True)

os.replace(tmp_path, out_path)

if sha256:
    h = hashlib.sha256()
    with open(out_path,"rb") as f:
        for chunk in iter(lambda: f.read(8*1024*1024), b""):
            h.update(chunk)
    got = h.hexdigest()
    print(f"SHA256_GOT={got}")
    print(f"SHA256_EXP={sha256}")
    if got.lower() != sha256.lower():
        raise SystemExit("ERROR: sha256 mismatch")
print("DOWNLOAD_OK=1")
PY
