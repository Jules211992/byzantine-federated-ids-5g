#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

mkdir -p "$RUN_DIR/manifest" "$RUN_DIR/dataset"

DOI="${DOI:-10.23729/e80ac9df-d9fb-47e7-8d0d-01384a415361}"
TS=$(date -u +%Y%m%d_%H%M%S)
META_RAW="$RUN_DIR/manifest/5gnidd_meta_raw_${TS}.json"
META_PICK="$RUN_DIR/manifest/5gnidd_meta_pick_${TS}.json"
URL_TXT="$RUN_DIR/manifest/5gnidd_resolved_${TS}.txt"
URLS_TXT="$RUN_DIR/manifest/5gnidd_urls_${TS}.txt"

python3 - <<PY > "$URL_TXT"
import urllib.request
doi = "https://doi.org/" + "${DOI}"
req = urllib.request.Request(doi, headers={"User-Agent":"Mozilla/5.0"})
u = urllib.request.urlopen(req)
print(u.geturl())
PY

RESOLVED=$(cat "$URL_TXT" | tr -d '\r\n')
echo "RUN_DIR=$RUN_DIR"
echo "DOI=$DOI"
echo "RESOLVED=$RESOLVED"

UUID=$(python3 - <<PY
import re
u="${RESOLVED}"
m=re.search(r"/dataset/([0-9a-fA-F-]{36})", u)
print(m.group(1) if m else "")
PY
)

if [ -z "${UUID:-}" ]; then
  echo "ERROR: impossible d'extraire UUID dataset depuis RESOLVED"
  exit 1
fi
echo "UUID=$UUID"

ok=0
for base in \
  "https://metax-legacy.fairdata.fi/rest/v2/datasets" \
  "https://metax-legacy.fairdata.fi/rest/datasets" \
  "https://metax.fairdata.fi/rest/v2/datasets" \
  "https://metax.fairdata.fi/rest/datasets" \
  "https://metax.fairdata.fi/v3/datasets" \
; do
  url="${base}/${UUID}"
  if curl -fsSL -H "Accept: application/json" "$url" > "$META_RAW" 2>/dev/null; then
    echo "META_SOURCE=$url"
    ok=1
    break
  fi
done

if [ "$ok" -ne 1 ]; then
  echo "ERROR: aucun endpoint Metax n'a répondu."
  echo "ACTION: ouvre le DOI dans ton navigateur et télécharge manuellement, puis on passera au script d'import."
  echo "DOI_BROWSER=https://doi.org/${DOI}"
  exit 2
fi

python3 - "$META_RAW" "$META_PICK" "$URLS_TXT" <<'PY'
import json, sys, re
raw = sys.argv[1]
out_json = sys.argv[2]
out_urls = sys.argv[3]
j = json.load(open(raw))

urls=set()
files=[]
def walk(x):
  if isinstance(x, dict):
    name=None
    for k in ("file_name","filename","name","title"):
      v=x.get(k)
      if isinstance(v,str) and 1 <= len(v) <= 220:
        name=v
        break
    url=None
    for k in ("download_url","downloadUrl","url","file_download_url","download"):
      v=x.get(k)
      if isinstance(v,str) and v.startswith("http"):
        url=v
        break
    size=None
    for k in ("byte_size","bytes","size","file_size"):
      v=x.get(k)
      if isinstance(v,(int,float)):
        size=int(v)
        break

    if url:
      urls.add(url)
      if name or size is not None:
        files.append({"name":name, "bytes":size, "url":url})

    for v in x.values():
      walk(v)

  elif isinstance(x, list):
    for v in x:
      walk(v)

walk(j)

def keep(u):
  return re.search(r"\.(zip|csv|parquet|json|tar|gz|tgz|7z)(\?|$)", u, re.IGNORECASE) is not None

picked = sorted([u for u in urls if keep(u)])
with open(out_urls,"w") as f:
  for u in picked:
    f.write(u+"\n")

seen=set()
uniq=[]
for it in files:
  u=it.get("url")
  if not u or u in seen:
    continue
  seen.add(u)
  uniq.append(it)

uniq=sorted(uniq, key=lambda x: (x.get("bytes") is None, x.get("bytes") or 0))
json.dump({"n_urls_total":len(urls),"n_urls_picked":len(picked),"files_like":uniq[:200]}, open(out_json,"w"), indent=2)
print("N_URLS_TOTAL=",len(urls))
print("N_URLS_PICKED=",len(picked))
print("SAVED_URLS_TXT=",out_urls)
print("SAVED_PICK_JSON=",out_json)
PY

echo "SAVED_META_RAW=$META_RAW"
echo "SAVED_URLS_TXT=$URLS_TXT"
echo "SAVED_PICK_JSON=$META_PICK"
echo
echo "=== First 40 picked URLs ==="
sed -n '1,40p' "$URLS_TXT" || true
