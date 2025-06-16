#!/bin/bash

if [[ -f ".env" ]]; then
  source .env
fi

if [[ ! "$X_SERVICE_KEY" =~ ^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$ ]]; then
  echo "[!] Invalid or missing X_SERVICE_KEY in .env"
  exit 1
fi

VIDEO="$1"
SEGMENT_TIME=2
TIMESTAMP_MS=$(date +%s%3N)
SEGMENTS_DIR="./segments"
M3U8_DIR="./video"
SERVICE_KEY="$X_SERVICE_KEY"

# get IP & set host
IP=$(curl -s https://api.ipify.org)
if [[ ! "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[!] Failed to detect public IP, fallback to 127.0.0.1"
  IP="127.0.0.1"
fi
HOST="https://$IP"


command -v jq >/dev/null 2>&1 || {
  echo >&2 "[!] 'jq' is required but not installed. Aborting.";
  exit 1;
}

if [[ -z "$VIDEO" ]]; then
  echo "Usage: $0 <video_file.mp4>"
  exit 1
fi
if [[ ! -f "$VIDEO" ]]; then
  echo "[!] File not found: $VIDEO"
  exit 1
fi
if [[ ! -r "$VIDEO" ]]; then
  echo "[!] File not readable: $VIDEO"
  exit 1
fi
if [[ ! -x "$(command -v ffmpeg)" ]]; then
  echo "[!] 'ffmpeg' is required but not installed. Aborting."
  exit 1
fi
if [[ ! -x "$(command -v curl)" ]]; then
  echo "[!] 'curl' is required but not installed. Aborting."
  exit 1
fi

mkdir -p "$SEGMENTS_DIR" "$M3U8_DIR"

FILENAME=$(basename -- "$VIDEO")
EXT="${FILENAME##*.}"
BASENAME_NOEXT="${FILENAME%.*}"
BASENAME_ID="${BASENAME_NOEXT}_${TIMESTAMP_MS}"
M3U8_PATH="$M3U8_DIR/${BASENAME_ID}.m3u8"
TMP_M3U8="${M3U8_PATH}.tmp"

echo "[*] Detected input: $FILENAME (extension: $EXT)"
echo "[*] Splitting into .ts segments every ${SEGMENT_TIME}s and generating .m3u8..."

ffmpeg -i "$VIDEO" \
  -c:v libx264 -preset veryfast \
  -b:v 1800k -maxrate 2000k -bufsize 2200k \
  -g $((SEGMENT_TIME * 30)) -keyint_min $((SEGMENT_TIME * 30)) -sc_threshold 0 \
  -c:a aac -b:a 128k \
  -f hls \
  -hls_time $SEGMENT_TIME \
  -hls_list_size 0 \
  -hls_segment_filename "$SEGMENTS_DIR/${BASENAME_ID}_part_%03d.ts" \
  "$M3U8_PATH"

echo "[*] Rewriting .m3u8 to use /ts/<filename> for proxy..."

awk '
  /^#EXTINF/ { print; getline nextline; print "/ts/" nextline; next }
  { print }
' "$M3U8_PATH" > "$TMP_M3U8" && mv "$TMP_M3U8" "$M3U8_PATH"

echo "[*] Uploading .ts segments to Pipe KV in parallel..."

CPU_CORES=$(nproc --ignore=1 2>/dev/null || getconf _NPROCESSORS_ONLN)
PARALLEL_UPLOADS=$(( CPU_CORES > 1 ? CPU_CORES : 1 ))
echo "[*] Detected $CPU_CORES core(s), running $PARALLEL_UPLOADS parallel upload(s)..."

find "$SEGMENTS_DIR" -name "${BASENAME_ID}_part_*.ts" | \
xargs -P "$PARALLEL_UPLOADS" -I{} bash -c '
  FILENAME=$(basename "{}")
  echo "[$(date +%H:%M:%S)] Uploading $FILENAME..."
  curl -s -X PUT -k "'"$HOST"'/kv/$FILENAME" \
    -H "X-Service-Key: '"$SERVICE_KEY"'" \
    --data-binary @"{}" \
    -w "[$(date +%H:%M:%S)] [Upload Time: %{time_total}s] → $FILENAME\n"
'

echo "[*] Uploading .m3u8 file to Pipe KV..."

RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT -k "$HOST/kv/${BASENAME_ID}.m3u8" \
  -H "X-Service-Key: $SERVICE_KEY" \
  -H "Content-Type: application/vnd.apple.mpegurl" \
  --data-binary @"$M3U8_PATH")

if [[ "$RESPONSE" != "200" ]]; then
  echo "[!] Failed to upload .m3u8. Response code: $RESPONSE"
  exit 1
fi

echo "[✓] Uploaded successfully."
echo "→ M3U8 URL: https://<proxy_server:6969>/m3u8/${BASENAME_ID}.m3u8"

# === Update index
echo "[*] Updating m3u8_index_cache.json..."

RAW_LIST="./video/m3u8_index_raw.txt"
CACHE_FILE="./video/m3u8_index_cache.json"

grep -qxF "${BASENAME_ID}.m3u8" "$RAW_LIST" 2>/dev/null || echo "${BASENAME_ID}.m3u8" >> "$RAW_LIST"
jq -R -s -c 'split("\n") | map(select(. != ""))' "$RAW_LIST" > "$CACHE_FILE"

echo "[✓] Index updated: $CACHE_FILE"

# === Cleanup
echo "[*] Cleaning up..."
rm -f "$M3U8_PATH"
rm -f "$SEGMENTS_DIR/${BASENAME_ID}_part_"*.ts
echo "[✓] Cleanup done."
