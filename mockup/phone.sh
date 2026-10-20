#!/bin/sh
# Same as start.sh, plus an HTTPS server on your Wi-Fi so a phone can stream from its camera.
[ -f "$HOME/.sidequest-google.env" ] && . "$HOME/.sidequest-google.env" && export SQ_GOOGLE_PLACES_KEY SQ_GOOGLE_DAILY SQ_GOOGLE_MAPS_BROWSER_KEY SQ_GOOGLE_CLIENT_ID SQ_GOOGLE_TTS_KEY SQ_GOOGLE_NIGHT_DAILY SQ_TTS_DAILY_CHARS
[ -f "$HOME/.sidequest-livekit.env" ] && . "$HOME/.sidequest-livekit.env" && export SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET
cd "$(dirname "$0")" && SQ_LAN=1 exec ruby server.rb
