#!/bin/sh
# From this Mac: copy the app + events service to the server and run the installer.
#   ./deploy/push.sh root@your-server
set -e
[ -n "$1" ] || { echo "usage: $0 user@host"; exit 1; }
here="$(cd "$(dirname "$0")/.." && pwd)"
ssh "$1" 'mkdir -p /opt/sidequest/app /opt/sidequest/events /opt/sidequest/deploy'
rsync -az --delete --exclude data/ --exclude '*.py' "$here/mockup/" "$1:/opt/sidequest/app/"
# Map data made on this Mac (sights, parks, markets, neighborhoods, popularity, event spots): never the users' data,
# never --delete, and --update so the server's newer copy (the weekly places refresh) isn't rolled back
(cd "$here/mockup/data" && rsync -az --update --chmod=F644 areas.json markets.json outdoors.json places.json popular.json sights.json geofix.json "$1:/opt/sidequest/app/data/")
rsync -az --delete --exclude .venv/ --exclude data/ --exclude __pycache__/ "$HOME/claude/live/" "$1:/opt/sidequest/events/"
rsync -az "$here/deploy/" "$1:/opt/sidequest/deploy/"
ssh -t "$1" 'cd /opt/sidequest/deploy && chmod +x *.sh && sh install.sh'
