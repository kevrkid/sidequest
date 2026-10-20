#!/bin/sh
# Public beta: guests can browse, sign-up is invite-only, no demo content, admin page on.
# Before running, set (for example in ~/.sidequest.env):
#   SQ_INVITES="austin-beta,launch-night"      comma-separated invite codes (leave unset for open sign-up)
#   SQ_ADMIN_TOKEN="<long random string>"      e.g. from: openssl rand -hex 24
#   SQ_USE_API_KEY=1 ANTHROPIC_API_KEY=...     bill Claude to an API key, not your personal subscription
#   SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET   live video relay (LiveKit Cloud project settings)
cd "$(dirname "$0")"
[ -f "$HOME/.sidequest.env" ] && . "$HOME/.sidequest.env"
[ -z "$SQ_ADMIN_TOKEN" ] && echo "Set SQ_ADMIN_TOKEN first (openssl rand -hex 24) so you can review reports." && exit 1
export SQ_BETA=1 SQ_INVITES SQ_ADMIN_TOKEN SQ_USE_API_KEY ANTHROPIC_API_KEY SQ_LIVEKIT_URL SQ_LIVEKIT_KEY SQ_LIVEKIT_SECRET SQ_GOOGLE_PLACES_KEY SQ_GOOGLE_DAILY SQ_GOOGLE_MAPS_BROWSER_KEY SQ_GOOGLE_CLIENT_ID SQ_GOOGLE_TTS_KEY SQ_GOOGLE_NIGHT_DAILY SQ_TTS_DAILY_CHARS
exec ruby server.rb
