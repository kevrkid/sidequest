#!/bin/sh
# Run on the server as root, from /opt/sidequest/deploy after push.sh has copied the code.
# Safe to re-run: it updates code and restarts the services.
set -e
apt-get update -qq
apt-get install -y -qq ruby python3-venv caddy >/dev/null
gem list -i webrick >/dev/null || gem install webrick --no-document   # WEBrick left Ruby's standard library in 3.0
id sidequest >/dev/null 2>&1 || useradd --system --home /opt/sidequest --shell /usr/sbin/nologin sidequest
mkdir -p /opt/sidequest/app/data /opt/sidequest/events/data /etc/sidequest
[ -f /etc/sidequest/env ] || { install -m 600 env.example /etc/sidequest/env; echo ">>> Fill in /etc/sidequest/env, then re-run."; exit 1; }
grep -q '^SQ_ADMIN_TOKEN=.\+' /etc/sidequest/env || { echo ">>> Set SQ_ADMIN_TOKEN in /etc/sidequest/env"; exit 1; }
grep -q '^ANTHROPIC_API_KEY=.\+' /etc/sidequest/env || echo ">>> Warning: no ANTHROPIC_API_KEY, Claude features will fail"
grep -q "^SQ_ENGINE=cli" /etc/sidequest/env && { command -v "$(sed -n "s/^CLAUDE_BIN=//p" /etc/sidequest/env)" >/dev/null || echo ">>> Warning: Claude Code CLI not found at CLAUDE_BIN"; }
cd /opt/sidequest/events
[ -d .venv ] || python3 -m venv .venv
.venv/bin/pip install -q -r requirements.txt
chown -R sidequest:sidequest /opt/sidequest
install -m 644 /opt/sidequest/deploy/sidequest.service /opt/sidequest/deploy/sidequest-events.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now sidequest-events sidequest
systemctl restart sidequest-events sidequest
# Food & drink places from OpenStreetMap: first download now (resumable), then a fresh copy every Monday 4:30 AM.
[ -f /opt/sidequest/app/data/places.json ] || su -s /bin/sh sidequest -c 'cd /opt/sidequest/app && ruby fetch_places.rb' || echo ">>> Places download incomplete; run it again later"
( crontab -l 2>/dev/null | grep -v -e sidequest/deploy/backup.sh -e fetch_places.rb
  echo "15 4 * * * /opt/sidequest/deploy/backup.sh"
  echo "30 4 * * 1 su -s /bin/sh sidequest -c 'cd /opt/sidequest/app && ruby fetch_places.rb --fresh' >/var/log/sidequest-places.log 2>&1" ) | crontab -
sleep 2
curl -fsS http://127.0.0.1:8787/api/health && echo && echo ">>> App is up. Add Caddyfile.snippet (with your domain) to /etc/caddy/Caddyfile and reload Caddy."
