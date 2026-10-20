#!/bin/sh
# Side Quest V2 next to V1: http://localhost:8797 (and https://<this Mac's Wi-Fi address>:8444 for phones).
# V1 keeps 8787 / 8443. V2 has its own copy of the data (mockup/data), so nothing you do here touches V1.
#
#   ./start_v2.sh           # no paid Google / LiveKit calls: OpenStreetMap tiles, no Google photos, phone-to-phone video
#   ./start_v2.sh --keys    # same keys as V1 (Google Places / tiles / voice, LiveKit): counts against the same budgets
cd "$(dirname "$0")"
if [ "$1" = "--keys" ]; then
  [ -f "$HOME/.sidequest-google.env" ] && . "$HOME/.sidequest-google.env" && export SQ_GOOGLE_PLACES_KEY SQ_GOOGLE_DAILY SQ_GOOGLE_MAPS_BROWSER_KEY SQ_GOOGLE_CLIENT_ID SQ_GOOGLE_TTS_KEY SQ_GOOGLE_NIGHT_DAILY SQ_TTS_DAILY_CHARS
  [ -f "$HOME/.sidequest-livekit.env" ] && . "$HOME/.sidequest-livekit.env" && export SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET
fi
PORT=8797 SQ_LAN=1 SQ_LAN_PORT=8444 SQ_ADMIN_TOKEN="${SQ_ADMIN_TOKEN:-v2admin}" exec ruby server.rb
