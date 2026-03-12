#!/bin/bash
set -euo pipefail

cd ~/byz-fed-ids-5g

RUN_DIR=$(ls -dt "$HOME/byz-fed-ids-5g/rev/runs/rev_"*"_5g" 2>/dev/null | head -n 1 || true)
if [ -z "${RUN_DIR:-}" ]; then
  echo "ERROR: aucun RUN_DIR rev_*_5g trouvé dans ~/byz-fed-ids-5g/rev/runs/"
  exit 1
fi

FILES_JSON=$(ls -t "$RUN_DIR"/manifest/5gnidd_files_raw_*.json 2>/dev/null | head -n 1 || true)
META_JSON=$(ls -t "$RUN_DIR"/manifest/5gnidd_meta_raw_*.json 2>/dev/null | head -n 1 || true)

if [ -z "${FILES_JSON:-}" ] || [ ! -f "$FILES_JSON" ]; then
  echo "ERROR: files_raw introuvable dans $RUN_DIR/manifest (exécute d'abord rev/11-5gnidd-list-files-and-links.sh)"
  exit 1
fi

UUID=""
if [ -n "${META_JSON:-}" ] && [ -f "$META_JSON" ]; then
  UUID=$(python3 - "$META_JSON" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("id","") or "")
PY
)
fi

if [ -z "${UUID:-}" ]; then
  UUID=$(python3 - "$FILES_JSON" <<'PY'
import json,sys
arr=json.load(open(sys.argv[1]))
pid=set()
for f in arr:
  fp=f.get("file_path","")
  if fp:
    pid.add("x")
print("")
PY
)
fi

DS_DIR="$RUN_DIR/dataset"
mkdir -p "$DS_DIR"

SEL="${FILES:-README.pdf Encoded.zip}"

echo "RUN_DIR=$RUN_DIR"
echo "FILES_JSON=$FILES_JSON"
echo "META_JSON=${META_JSON:-NONE}"
echo "UUID=${UUID:-UNKNOWN}"
echo "SELECTED=$SEL"
echo

python3 - "$FILES_JSON" <<'PY' > "$RUN_DIR/manifest/5gnidd_files_index.tsv"
import json,sys,os
arr=json.load(open(sys.argv[1]))
print("file_name\tfile_path\tidentifier\tbyte_size\tsha256")
for f in arr:
  name=f.get("file_name","")
  path=f.get("file_path","")
  fid=f.get("identifier","")
  bs=f.get("byte_size",0)
  c=f.get("checksum") or {}
  sha=c.get("value","")
  alg=(c.get("algorithm","") or "").upper()
  if alg!="SHA-256":
    sha=""
  if name and path and fid:
    print(f"{name}\t{path}\t{fid}\t{bs}\t{sha}")
PY

echo "INDEX=$RUN_DIR/manifest/5gnidd_files_index.tsv"
echo

want() {
  local name="$1"
  for x in $SEL; do
    [ "$x" = "$name" ] && return 0
  done
  return 1
}

head_ok() {
  local url="$1"
  local h
  h=$(curl -sSIL --max-redirs 5 "$url" | tr -d '\r' || true)
  echo "$h" | tail -n 1 | grep -Eq '^HTTP/' || return 1
  echo "$h" | grep -E '^HTTP/' | tail -n 1 | grep -Eq ' 200 | 302 | 301 ' || return 1
  echo "$h" | grep -i '^content-type:' | tail -n 1 | grep -iv 'text/html' >/dev/null 2>&1 || true
  return 0
}

download_one() {
  local name="$1"
  local path="$2"
  local fid="$3"
  local bs="$4"
  local sha="$5"

  local out="$DS_DIR/$name"
  local tmp="$out.part"

  echo
  echo "=== DOWNLOAD $name ==="
  echo "file_path=$path"
  echo "identifier=$fid"
  echo "expected_bytes=$bs"
  echo "sha256=${sha:-NONE}"
  echo "out=$out"

  if [ -f "$out" ] && [ "$bs" != "0" ]; then
    local cur
    cur=$(stat -c%s "$out" 2>/dev/null || echo 0)
    if [ "$cur" = "$bs" ]; then
      echo "SKIP: already downloaded (size matches)"
      return 0
    fi
  fi

  local tries=(
    "https://ida.fairdata.fi/api/access/data/${fid}"
    "https://ida.fairdata.fi/api/access/data${path}"
    "https://ida.fairdata.fi/api/download${path}"
    "https://ida.fairdata.fi/download${path}"
    "https://etsin.fairdata.fi/api/access/data/${fid}"
    "https://etsin.fairdata.fi/api/download${path}"
    "https://etsin.fairdata.fi/download${path}"
  )

  local ok=""
  for u in "${tries[@]}"; do
    if head_ok "$u"; then
      ok="$u"
      break
    fi
  done

  if [ -z "$ok" ]; then
    echo "ERROR: impossible de déterminer un endpoint de download valide pour $name"
    echo "DETAIL: essais = ${#tries[@]}"
    return 1
  fi

  echo "URL=$ok"
  mkdir -p "$DS_DIR"

  set +e
  curl -L --retry 5 --retry-delay 2 --connect-timeout 20 --max-time 0 -C - -o "$tmp" "$ok"
  rc=$?
  set -e
  if [ $rc -ne 0 ]; then
    echo "ERROR: curl failed rc=$rc"
    return 1
  fi

  mv -f "$tmp" "$out"

  if [ -n "${sha:-}" ]; then
    echo "$sha  $out" | sha256sum -c - >/dev/null 2>&1 && echo "SHA256_OK" || { echo "SHA256_MISMATCH"; return 1; }
  fi

  echo "DONE: $(stat -c%s "$out" 2>/dev/null || echo 0) bytes"
}

while IFS=$'\t' read -r name path fid bs sha; do
  [ "$name" = "file_name" ] && continue
  if want "$name"; then
    download_one "$name" "$path" "$fid" "$bs" "$sha"
  fi
done < "$RUN_DIR/manifest/5gnidd_files_index.tsv"

echo
echo "OK: downloads finished"
ls -lah "$DS_DIR" | sed -n '1,220p'
