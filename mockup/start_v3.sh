#!/bin/sh
# Side Quest V3 (map first) next to V2: http://localhost:8802 (and https://<this Mac's Wi-Fi address>:8446 for phones).
# V2 keeps 8797 / 8444. V3 has its own data (this folder's mockup/data), so nothing you do here touches V2 or the live site.
#
#   ./start_v3.sh           # no paid Google / LiveKit calls: OpenStreetMap tiles, no Google photos, phone-to-phone video
#   ./start_v3.sh --keys    # same keys as V1 (Google Places / tiles / voice, LiveKit): counts against the same budgets
#   ./start_v3.sh --voice   # only Scout's Google voice (capped by SQ_TTS_DAILY_CHARS); everything else stays free
cd "$(dirname "$0")"
if [ "$1" = "--keys" ]; then
  [ -f "$HOME/.sidequest-google.env" ] && . "$HOME/.sidequest-google.env" && export SQ_GOOGLE_PLACES_KEY SQ_GOOGLE_DAILY SQ_GOOGLE_MAPS_BROWSER_KEY SQ_GOOGLE_CLIENT_ID SQ_GOOGLE_TTS_KEY SQ_GOOGLE_NIGHT_DAILY SQ_TTS_DAILY_CHARS
  [ -f "$HOME/.sidequest-livekit.env" ] && . "$HOME/.sidequest-livekit.env" && export SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET
fi
if [ "$1" = "--voice" ] && [ -f "$HOME/.sidequest-google.env" ]; then
  SQ_GOOGLE_TTS_KEY=$(sed -n 's/^SQ_GOOGLE_TTS_KEY=//p' "$HOME/.sidequest-google.env" | tr -d '"')
  TTS_CAP=$(sed -n 's/^SQ_TTS_DAILY_CHARS=//p' "$HOME/.sidequest-google.env" | tr -d '"')
  [ -n "$TTS_CAP" ] && export SQ_TTS_DAILY_CHARS="$TTS_CAP"
  export SQ_GOOGLE_TTS_KEY
fi
PORT=8802 SQ_LAN=1 SQ_LAN_PORT=8446 SQ_ADMIN_TOKEN="${SQ_ADMIN_TOKEN:-v3admin}" exec ruby server.rb
