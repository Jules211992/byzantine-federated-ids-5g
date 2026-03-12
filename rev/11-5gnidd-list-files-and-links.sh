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
FILES_RAW="$RUN_DIR/manifest/5gnidd_files_raw_${TS}.json"
SUMMARY_TXT="$RUN_DIR/manifest/5gnidd_files_summary_${TS}.txt"
LINKS_TXT="$RUN_DIR/manifest/5gnidd_links_${TS}.txt"
HTML_LINKS_TXT="$RUN_DIR/manifest/5gnidd_links_from_html_${TS}.txt"

RESOLVED=$(curl -sI "https://doi.org/${DOI}" | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}' | tail -n 1)
UUID=$(echo "$RESOLVED" | awk -F'/dataset/' '{print $2}' | awk -F'[/?#]' '{print $1}')

echo "RUN_DIR=$RUN_DIR"
echo "DOI=$DOI"
echo "RESOLVED=$RESOLVED"
echo "UUID=$UUID"
echo

META_URL="https://metax-legacy.fairdata.fi/rest/v2/datasets/${UUID}"
FILES_URL="https://metax-legacy.fairdata.fi/rest/v2/datasets/${UUID}/files"

curl -fsSL -H "Accept: application/json" "$META_URL" > "$META_RAW"

set +e
curl -fsSL -H "Accept: application/json" "$FILES_URL" > "$FILES_RAW"
RC_FILES=$?
set -e

echo "META_URL=$META_URL"
echo "FILES_URL=$FILES_URL"
echo "META_RAW=$META_RAW"
echo "FILES_RAW=$FILES_RAW"
echo "FILES_HTTP_RC=$RC_FILES"
echo

python3 - "$META_RAW" "$FILES_RAW" > "$SUMMARY_TXT" <<'PY'
import json, sys
from collections import Counter

meta_path = sys.argv[1]
files_path = sys.argv[2]

def load(p):
  try:
    with open(p,"r",encoding="utf-8") as f:
      return json.load(f)
  except Exception as e:
    return {"__error__": str(e)}

meta = load(meta_path)
files = load(files_path)

print("META_TOP_KEYS=", sorted(list(meta.keys()))[:80])
rd = meta.get("research_dataset", {})
print("META_DATA_CATALOG=", meta.get("data_catalog"))
print("META_STATE=", meta.get("state"))
print("META_PREFERRED_IDENTIFIER=", rd.get("preferred_identifier"))
title = rd.get("title") or {}
print("META_TITLE=", title.get("en") or title.get("fi") or title.get("sv"))
print()

if "__error__" in files:
  print("FILES_ERROR=", files["__error__"])
  sys.exit(0)

if isinstance(files, dict):
  arr = files.get("results") or files.get("files") or files.get("data") or []
  print("FILES_DICT_KEYS=", sorted(list(files.keys()))[:80])
  if "count" in files: print("FILES_COUNT_FIELD=", files.get("count"))
  if "next" in files: print("FILES_NEXT=", files.get("next"))
  if "previous" in files: print("FILES_PREV=", files.get("previous"))
else:
  arr = files

print("FILES_TYPE=", type(files).__name__)
print("FILES_ITEMS=", len(arr))
print()

if len(arr) > 0 and isinstance(arr[0], dict):
  k = Counter()
  for it in arr[:80]:
    k.update(it.keys())
  print("FILES_COMMON_KEYS_SAMPLE=", [x for x,_ in k.most_common(50)])
  print()
  for i,it in enumerate(arr[:15], start=1):
    line = {
      "i": i,
      "identifier": it.get("identifier"),
      "file_path": it.get("file_path") or it.get("path") or it.get("relative_path"),
      "byte_size": it.get("byte_size") or it.get("file_size") or it.get("size"),
      "mime_type": it.get("mime_type"),
      "checksum_alg": it.get("checksum_algorithm"),
      "checksum": it.get("checksum_value") or it.get("checksum"),
      "storage": it.get("file_storage") or it.get("storage") or it.get("storage_identifier"),
    }
    print(line)
PY

python3 - "$FILES_RAW" > "$LINKS_TXT" <<'PY'
import json, sys

p = sys.argv[1]
try:
  data = json.load(open(p,"r",encoding="utf-8"))
except Exception:
  print("")
  sys.exit(0)

urls = set()
def walk(x):
  if isinstance(x, dict):
    for v in x.values():
      walk(v)
  elif isinstance(x, list):
    for v in x:
      walk(v)
  elif isinstance(x, str):
    if x.startswith("http://") or x.startswith("https://"):
      urls.add(x)

walk(data)

for u in sorted(urls):
  print(u)
PY

set +e
curl -fsSL "$RESOLVED" | tr '\r' '\n' | grep -Eo 'https?://[^"<> ]+' | sort -u > "$HTML_LINKS_TXT"
RC_HTML=$?
set -e

echo "SUMMARY_TXT=$SUMMARY_TXT"
echo "LINKS_TXT=$LINKS_TXT"
echo "HTML_LINKS_TXT=$HTML_LINKS_TXT"
echo "HTML_FETCH_RC=$RC_HTML"
echo
echo "=== SUMMARY (head) ==="
sed -n '1,220p' "$SUMMARY_TXT" || true
echo
echo "=== LINKS from files endpoint (first 120) ==="
sed -n '1,120p' "$LINKS_TXT" || true
echo
echo "=== LINKS from Etsin HTML (download/ida/metax/zip/csv/tar, first 200) ==="
grep -Ei 'download|fairdata|ida|metax|zip|csv|tgz|tar|dataset' "$HTML_LINKS_TXT" | sed -n '1,200p' || true

echo
echo "OK"
