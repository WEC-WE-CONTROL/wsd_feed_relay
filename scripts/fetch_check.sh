#!/usr/bin/env bash
# Fetch the WSD file, check it, and write wsms_open_data.csv and status.json. Exit 1 (writing nothing) on any failed check.
set -euo pipefail
URL='https://www.esd.wsd.gov.hk/wsms_open_data/WSMS_OPEN_DATA(all).csv'
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36'
HEADER='SUSPENSION_ID|WATER_TYPE_DESCRIPTION|WATER_TYPE_DESCRIPTION_ZHT|DISTRICT_ENG|DISTRICT_ZHT|NATURE_DESCRIPTION|NATURE_DESCRIPTION_ZHT|SUSPENSION_DATE_TIME|ACTUAL_RESUMPTION_DATE_TIME|LONG_ADDRESS|LONG_ADDRESS_ZHT|CAUSE|CAUSE_ZHT|STATUS|STATUS_ZHT'
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
code=$(curl -sS -m 60 -A "$UA" -o "$tmp" -w '%{http_code}' "$URL")
size=$(wc -c < "$tmp")
[ "$code" = "200" ] || { echo "REFUSING: HTTP $code"; exit 1; }
[ "$size" -gt 10240 ] || { echo "REFUSING: only $size bytes"; exit 1; }
if head -c 512 "$tmp" | grep -qi '<html\|<!doctype'; then echo "REFUSING: this is a web page, not the CSV"; exit 1; fi
first=$(head -n 1 "$tmp" | tr -d '\r')
[ "$first" = "$HEADER" ] || { echo "REFUSING: header row changed: $first"; exit 1; }
cp "$tmp" wsms_open_data.csv
sha=$(sha256sum wsms_open_data.csv | cut -d' ' -f1)
printf '{"checked_at":"%s","bytes":%s,"sha256":"%s","source_url":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$size" "$sha" "$URL" > status.json
