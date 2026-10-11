#!/bin/bash
set -euo pipefail
if [ "${RENEWED_LINEAGE:-}" = /etc/letsencrypt/live/epochrush-public ]; then
    if [ -x /www/server/nginx/sbin/nginx ]; then
        /www/server/nginx/sbin/nginx -t
        /www/server/nginx/sbin/nginx -s reload
    else
        nginx -t
        systemctl reload nginx
    fi
fi
