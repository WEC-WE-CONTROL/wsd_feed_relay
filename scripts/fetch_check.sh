#!/usr/bin/env bash
# Fetch the WSD file, check it, and write wsms_open_data.csv and status.json.
#
# The WSD site sometimes times out for one check and answers again 10 minutes later. So:
#   - the download is tried up to 3 times, with a pause between tries;
#   - if every try fails, nothing is written, and the exit code depends on how old the last good check is:
#       last good check younger than MAX_STALE_SECONDS (2 hours) -> exit 0 with a clear "unreachable" line;
#       last good check 2 hours or older, or unknown             -> exit 1 (the run fails and GitHub emails).
#   - a changed header row means the file format changed. That needs a person, so it exits 1 at once.
# Every safety check stays: HTTP 200, size, not a web page, exact header row.
set -euo pipefail
URL="${WSD_URL:-https://www.esd.wsd.gov.hk/wsms_open_data/WSMS_OPEN_DATA(all).csv}"
CURL_TIMEOUT="${CURL_TIMEOUT:-60}"
RETRY_PAUSES="${RETRY_PAUSES:-20 60}"            # pauses in seconds between tries; 2 pauses = 3 tries
MAX_STALE_SECONDS="${MAX_STALE_SECONDS:-7200}"   # 2 hours
STATUS_FILE="${STATUS_FILE:-status.json}"
CSV_FILE="${CSV_FILE:-wsms_open_data.csv}"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
HEADER='SUSPENSION_ID|WATER_TYPE_DESCRIPTION|WATER_TYPE_DESCRIPTION_ZHT|DISTRICT_ENG|DISTRICT_ZHT|NATURE_DESCRIPTION|NATURE_DESCRIPTION_ZHT|SUSPENSION_DATE_TIME|ACTUAL_RESUMPTION_DATE_TIME|LONG_ADDRESS|LONG_ADDRESS_ZHT|CAUSE|CAUSE_ZHT|STATUS|STATUS_ZHT'
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# One try: download and check. Returns 0 when the file is good, 1 on a failure worth retrying,
# 2 when the header row changed (not worth retrying).
try_once() {
  local code size first
  : > "$tmp"
  if ! code=$(curl -sS -m "$CURL_TIMEOUT" -A "$UA" -o "$tmp" -w '%{http_code}' "$URL"); then
    echo "REFUSING: download failed (curl error above)"; return 1
  fi
  size=$(wc -c < "$tmp")
  [ "$code" = "200" ] || { echo "REFUSING: HTTP $code"; return 1; }
  [ "$size" -gt 10240 ] || { echo "REFUSING: only $size bytes"; return 1; }
  if head -c 512 "$tmp" | grep -qi '<html\|<!doctype'; then echo "REFUSING: this is a web page, not the CSV"; return 1; fi
  first=$(head -n 1 "$tmp" | tr -d '\r')
  [ "$first" = "$HEADER" ] || { echo "REFUSING: header row changed: $first"; return 2; }
  return 0
}

pauses=($RETRY_PAUSES)
tries=$(( ${#pauses[@]} + 1 ))
result=1
for (( n = 1; n <= tries; n++ )); do
  rc=0; try_once || rc=$?
  if [ "$rc" -eq 0 ]; then result=0; break; fi
  if [ "$rc" -eq 2 ]; then echo "WSD file format changed. Not retrying."; exit 1; fi
  if [ "$n" -lt "$tries" ]; then
    echo "try $n of $tries failed; waiting ${pauses[$((n - 1))]} s"
    sleep "${pauses[$((n - 1))]}"
  fi
done

if [ "$result" -eq 0 ]; then
  size=$(wc -c < "$tmp")
  cp "$tmp" "$CSV_FILE"
  sha=$(sha256sum "$CSV_FILE" | cut -d' ' -f1)
  printf '{"checked_at":"%s","bytes":%s,"sha256":"%s","source_url":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$size" "$sha" "$URL" > "$STATUS_FILE"
  [ "$n" -gt 1 ] && echo "good on try $n of $tries"
  exit 0
fi

# Every try failed. Fail the run only when the mirror is really stale.
last=$(sed -n 's/.*"checked_at":"\([^"]*\)".*/\1/p' "$STATUS_FILE" 2>/dev/null || true)
if [ -z "$last" ] || ! last_epoch=$(date -u -d "$last" +%s 2>/dev/null); then
  echo "WSD site unreachable after $tries tries, and no readable last good check in $STATUS_FILE. Failing."
  exit 1
fi
age=$(( $(date -u +%s) - last_epoch ))
if [ "$age" -lt "$MAX_STALE_SECONDS" ]; then
  echo "WSD site unreachable after $tries tries, last good check $last ($(( age / 60 )) min ago). Not failing: under $(( MAX_STALE_SECONDS / 60 )) min."
  exit 0
fi
echo "WSD site unreachable after $tries tries, last good check $last ($(( age / 60 )) min ago). Mirror is stale: failing."
exit 1
