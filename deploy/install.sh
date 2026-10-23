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
# Scout's ears for phones whose own speech recognition doesn't work: whisper.cpp + ffmpeg turn mic recordings into
# text on this box (optional: without them the app uses the browser's recognition only)
if apt-get install -y -qq whisper.cpp ffmpeg >/dev/null 2>&1; then
  WM=/opt/sidequest/whisper/ggml-base-q5_1.bin; WM_SHA=422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898   # sha256 from the model's Hugging Face page
  mkdir -p /opt/sidequest/whisper
  if ! echo "$WM_SHA  $WM" | sha256sum -c - >/dev/null 2>&1; then
    curl -fsSL -o "$WM.tmp" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin &&
      echo "$WM_SHA  $WM.tmp" | sha256sum -c - >/dev/null && mv "$WM.tmp" "$WM" || { rm -f "$WM.tmp"; echo ">>> Whisper model download failed; Scout uses the browser's speech recognition only"; }
  fi
else echo ">>> No whisper.cpp package here; Scout uses the browser's speech recognition only"; fi
chown -R sidequest:sidequest /opt/sidequest
install -m 644 /opt/sidequest/deploy/sidequest.service /opt/sidequest/deploy/sidequest-events.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now sidequest-events sidequest
systemctl restart sidequest-events sidequest
# Food & drink places from OpenStreetMap: first download now (resumable), then a fresh copy every Monday 4:30 AM.
[ -f /opt/sidequest/app/data/places.json ] || su -s /bin/sh sidequest -c 'cd /opt/sidequest/app && ruby fetch_places.rb' || echo ">>> Places download incomplete; run it again later"
( crontab -l 2>/dev/null | grep -v -e sidequest/deploy/backup.sh -e fetch_places.rb || true   # set -e: an empty list must not end the subshell
  echo "15 4 * * * /opt/sidequest/deploy/backup.sh"
  echo "30 4 * * 1 su -s /bin/sh sidequest -c 'cd /opt/sidequest/app && ruby fetch_places.rb --fresh' >/var/log/sidequest-places.log 2>&1" ) | crontab -
# Live video on this box (optional; the other choice is LiveKit Cloud, which needs nothing here).
if grep -q '^SQ_LIVEKIT_SELFHOST=1' /etc/sidequest/env; then
  LK_VERSION=1.13.10   # pinned; checksums from the release's checksums.txt
  arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64) LK_SHA=c25a3e45fb922e9a93c6443d10c0ed041ba64342097e38632331736630283165 ;;
    arm64) LK_SHA=ff60607e1931ff078576882fa11c087aa5821d635ac0c47f56ff77e203e32006 ;;
    *) echo ">>> LiveKit: no build for $arch"; exit 1 ;;
  esac
  key=$(sed -n 's/^SQ_LIVEKIT_KEY=//p' /etc/sidequest/env); secret=$(sed -n 's/^SQ_LIVEKIT_SECRET=//p' /etc/sidequest/env)
  { [ -n "$key" ] && [ ${#secret} -ge 32 ]; } || { echo ">>> Set SQ_LIVEKIT_KEY and SQ_LIVEKIT_SECRET (32+ characters) in /etc/sidequest/env"; exit 1; }
  id livekit >/dev/null 2>&1 || useradd --system --home /opt/sidequest/livekit --shell /usr/sbin/nologin livekit
  mkdir -p /opt/sidequest/livekit
  if ! /opt/sidequest/livekit/livekit-server --version 2>/dev/null | grep -q "$LK_VERSION"; then
    tmp=$(mktemp -d)
    curl -fsSL -o "$tmp/lk.tgz" "https://github.com/livekit/livekit/releases/download/v$LK_VERSION/livekit_${LK_VERSION}_linux_$arch.tar.gz"
    echo "$LK_SHA  $tmp/lk.tgz" | sha256sum -c - >/dev/null
    tar -xzf "$tmp/lk.tgz" -C "$tmp"
    install -m 755 "$(find "$tmp" -type f -name livekit-server | head -1)" /opt/sidequest/livekit/livekit-server
    rm -rf "$tmp"
  fi
  ( umask 027; printf '%s: %s\n' "$key" "$secret" > /etc/sidequest/livekit-keys.yaml )
  chown root:livekit /etc/sidequest/livekit-keys.yaml
  sh /opt/sidequest/deploy/livekit-cert.sh || echo ">>> LiveKit's TURN needs Caddy's certificate: add Caddyfile.snippet, reload Caddy, then run /opt/sidequest/deploy/livekit-cert.sh"
  install -m 644 /opt/sidequest/deploy/sidequest-livekit.service /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable sidequest-livekit
  systemctl restart sidequest-livekit || true
  ( crontab -l 2>/dev/null | grep -v livekit-cert.sh || true
    echo "45 4 * * * /opt/sidequest/deploy/livekit-cert.sh >/var/log/sidequest-livekit-cert.log 2>&1" ) | crontab -
  if command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
    ufw allow 7881/tcp >/dev/null; ufw allow 5349/tcp >/dev/null; ufw allow 3478/udp >/dev/null; ufw allow 50000:60000/udp >/dev/null
  fi
  echo ">>> LiveKit installed. In the Hetzner Cloud firewall allow TCP 7881 and 5349, UDP 3478 and 50000-60000."
fi
sleep 2
curl -fsS http://127.0.0.1:8787/api/health && echo && echo ">>> App is up. Add Caddyfile.snippet (with your domain) to /etc/caddy/Caddyfile and reload Caddy."
