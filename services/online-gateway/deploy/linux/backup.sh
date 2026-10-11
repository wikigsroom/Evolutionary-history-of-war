#!/bin/bash
set -euo pipefail
install -d -m 0700 /var/backups/epochrush
backup_file="/var/backups/epochrush/epochrush-$(date -u +%Y%m%dT%H%M%SZ).dump"
runuser -u postgres -- pg_dump -p 5432 -d epochrush_online -Fc > "$backup_file.partial"
test -s "$backup_file.partial"
mv "$backup_file.partial" "$backup_file"
sha256sum "$backup_file" > "$backup_file.sha256"
find /var/backups/epochrush -maxdepth 1 -type f -name 'epochrush-*.dump*' -mmin +10080 -delete
echo "Epoch Rush backup complete: $(basename "$backup_file")"
