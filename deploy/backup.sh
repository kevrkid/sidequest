#!/bin/sh
# Nightly copy of accounts, posts, stories and scraped events; keeps 14 days.
# cron: 15 4 * * *  /opt/sidequest/deploy/backup.sh
# The events database is live SQLite (WAL): copying its files while it writes can give a broken copy, so it goes in
# as a snapshot from SQLite's own backup API (checked before it's kept). app.json is always written whole (tmp + rename).
set -e
dest=/var/backups/sidequest; mkdir -p "$dest"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/events/data"
python3 - "$tmp/events/data/events.db" <<'EOF'
import sqlite3, sys
src = sqlite3.connect("file:/opt/sidequest/events/data/events.db?mode=ro", uri=True)
dst = sqlite3.connect(sys.argv[1])
src.backup(dst)
ok = dst.execute("pragma integrity_check").fetchone()[0]
dst.close(); src.close()
sys.exit(0 if ok == "ok" else "events snapshot failed its integrity check: " + ok)
EOF
tar -czf "$dest/sidequest-$(date +%F).tgz.part" -C /opt/sidequest app/data -C "$tmp" events/data
mv "$dest/sidequest-$(date +%F).tgz.part" "$dest/sidequest-$(date +%F).tgz"
find "$dest" -name 'sidequest-*.tgz' -mtime +14 -delete
