#!/bin/sh
# LiveKit's TURN-over-TLS (port 5349) needs this site's certificate. Caddy gets and renews it; this copies
# the current one where LiveKit can read it, and restarts LiveKit only when it changed.
# cron (install.sh adds it): 45 4 * * *  /opt/sidequest/deploy/livekit-cert.sh
set -e
domain=$(sed -n 's/^SQ_DOMAIN=//p' /etc/sidequest/env)
[ -n "$domain" ] || { echo "Set SQ_DOMAIN in /etc/sidequest/env"; exit 1; }
src=$(ls -t /var/lib/caddy/.local/share/caddy/certificates/*/"$domain"/"$domain".crt 2>/dev/null | head -1)
[ -n "$src" ] || { echo "Caddy has no certificate for $domain yet: add Caddyfile.snippet, reload Caddy, wait a minute"; exit 1; }
dst=/etc/sidequest/livekit-turn
mkdir -p "$dst"
if ! cmp -s "$src" "$dst/cert.pem"; then
  install -m 644 -o root -g livekit "$src" "$dst/cert.pem"
  install -m 640 -o root -g livekit "${src%.crt}.key" "$dst/key.pem"
  echo "TURN certificate updated from $src"
  ! systemctl is-enabled -q sidequest-livekit 2>/dev/null || systemctl restart sidequest-livekit
fi
