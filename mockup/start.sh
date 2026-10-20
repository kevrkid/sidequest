#!/bin/sh
# Start the Side Quest mockup with the Claude engine (local Claude Code subscription).
# Live video goes through LiveKit when ~/.sidequest-livekit.env sets SQ_LIVEKIT_URL, _KEY and _SECRET.
[ -f "$HOME/.sidequest-google.env" ] && . "$HOME/.sidequest-google.env" && export SQ_GOOGLE_PLACES_KEY SQ_GOOGLE_DAILY SQ_GOOGLE_MAPS_BROWSER_KEY SQ_GOOGLE_CLIENT_ID SQ_GOOGLE_TTS_KEY SQ_GOOGLE_NIGHT_DAILY SQ_TTS_DAILY_CHARS
[ -f "$HOME/.sidequest-livekit.env" ] && . "$HOME/.sidequest-livekit.env" && export SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET
cd "$(dirname "$0")" && exec ruby server.rb
