#!/bin/bash
set -euo pipefail
free_kb=$(df -Pk /var/lib/epochrush | awk 'NR==2 {print $4}')
if [ "$free_kb" -lt 524288 ]; then
    touch /var/lib/epochrush/draining.flag
    chown epochrush:epochrush /var/lib/epochrush/draining.flag
    logger -t epochrush-health 'Low disk space: stopped new matches; existing matches remain active.'
fi
if curl --fail --silent --max-time 3 http://127.0.0.1:28187/healthz | python3 -c 'import json,sys;sys.exit(0 if json.load(sys.stdin).get("ok") else 1)'; then
    printf '0\n' > /var/lib/epochrush/health-failures
else
    failures=$(cat /var/lib/epochrush/health-failures 2>/dev/null || printf '0')
    failures=$((failures + 1))
    printf '%s\n' "$failures" > /var/lib/epochrush/health-failures
    logger -t epochrush-health "Health check failure $failures"
    if [ "$failures" -ge 3 ]; then
        systemctl try-restart epochrush-online.service
        printf '0\n' > /var/lib/epochrush/health-failures
    fi
fi
