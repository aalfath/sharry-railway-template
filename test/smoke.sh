#!/bin/sh
# Smoke test: sh smoke.sh BASE_URL ADMIN_PASSWORD [upload|check] [SIZE_MB]
# upload: log in, upload a random file, publish it, download it back by its public link.
# check:  log in and confirm the share from an earlier upload is still there.
set -eu
B=$1; P=$2; MODE=${3:-upload}; MB=${4:-20}
J='Content-Type: application/json'
tok=$(curl -fsS -X POST "$B/api/v2/open/auth/login" -H "$J" -d "{\"account\":\"admin\",\"password\":\"$P\"}" | jq -r .token)
[ -n "$tok" ] && [ "$tok" != null ] || { echo "LOGIN FAILED"; exit 1; }
echo "login ok"
echo "proxy login: $(curl -sS -X POST "$B/api/v2/open/auth/proxy" -H 'X-Valid-User: admin' | jq -c '{success,message}')"
echo "bad password: $(curl -sS -X POST "$B/api/v2/open/auth/login" -H "$J" -d '{"account":"admin","password":"admin"}' | jq -c '{success,message}')"
echo "signup: $(curl -sS -X POST "$B/api/v2/open/signup/register" -H "$J" -d '{"login":"eve","password":"evepassword1","invite":null}' | jq -c . 2>/dev/null || true)"
H="Sharry-Auth: $tok"
if [ "$MODE" = upload ]; then
  head -c $((MB*1024*1024)) /dev/urandom > ${TMPDIR:-/tmp}/up.bin
  sha=$(sha256sum ${TMPDIR:-/tmp}/up.bin | cut -d' ' -f1)
  # Same path as the web UI: empty share, then a resumable (tus) upload in 10 MB chunks.
  sid=$(curl -fsS -X POST "$B/api/v2/sec/upload/new" -H "$H" -H "$J" \
      -d '{"validity":604800000,"maxViews":30,"name":"smoke"}' | jq -r .id)
  size=$(stat -c %s ${TMPDIR:-/tmp}/up.bin)
  loc=$(curl -fsS -D - -o /dev/null -X POST "$B/api/v2/sec/upload/$sid/files/tus" -H "$H" -H 'Tus-Resumable: 1.0.0' \
      -H "Sharry-File-Length: $size" -H 'Sharry-File-Name: up.bin' -H 'Sharry-File-Type: application/octet-stream' \
      | tr -d '\r' | awk 'tolower($1)=="location:"{print $2}')
  echo "tus location: $loc"
  split -b 10M -d ${TMPDIR:-/tmp}/up.bin ${TMPDIR:-/tmp}/chunk.; off=0
  for c in ${TMPDIR:-/tmp}/chunk.*; do
    curl -fsS -X PATCH "$loc" -H "$H" -H 'Tus-Resumable: 1.0.0' -H "Upload-Offset: $off" \
      -H 'Content-Type: application/offset+octet-stream' --data-binary "@$c" -o /dev/null
    off=$((off + $(stat -c %s "$c")))
  done
  rm ${TMPDIR:-/tmp}/chunk.*; echo "uploaded $off bytes"
  echo "share $sid"
  curl -fsS -X POST "$B/api/v2/sec/share/$sid/publish" -H "$H" -H "$J" -d '{"reuseId":false}' | jq -c .
  echo "$sid $sha" > ${TMPDIR:-/tmp}/smoke.state
fi
read sid sha < ${TMPDIR:-/tmp}/smoke.state
det=$(curl -fsS "$B/api/v2/sec/share/$sid" -H "$H")
pid=$(echo "$det" | jq -r .publishInfo.id); fid=$(echo "$det" | jq -r '.files[0].id')
got=$(curl -fsS "$B/api/v2/open/share/$pid/file/$fid" | sha256sum | cut -d' ' -f1)
echo "public link: $B/app/open/$pid"
[ "$got" = "$sha" ] && echo "DOWNLOAD OK sha256 matches" || { echo "DOWNLOAD MISMATCH"; exit 1; }
