#!/bin/sh
# Nightly copy of accounts, posts, stories and scraped events; keeps 14 days.
# cron: 15 4 * * *  /opt/sidequest/deploy/backup.sh
set -e
dest=/var/backups/sidequest; mkdir -p "$dest"
tar -czf "$dest/sidequest-$(date +%F).tgz" -C /opt/sidequest app/data events/data
find "$dest" -name 'sidequest-*.tgz' -mtime +14 -delete
