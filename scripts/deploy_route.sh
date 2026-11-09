#!/usr/bin/env bash
# Deploy the Velo Maps routing service (server/route) to the droplet. Secrets come from the
# Mac keychain (velomaps-mapbox-token, velomaps-tts-app-token) and go to
# /etc/velomaps-route.env (root:velomaps 0640) via a temp file deleted right after — never git.
# No Mapbox token in the keychain yet = the service answers 503 and the app uses public OSRM.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=root@104.236.120.144
ssh $HOST "id velomaps >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin velomaps; mkdir -p /opt/velomaps-route"
scp -q server/route/velomaps_route.py $HOST:/opt/velomaps-route/velomaps_route.py
scp -q server/route/velomaps-route.service $HOST:/etc/systemd/system/velomaps-route.service
ENV=$(mktemp); chmod 600 "$ENV"
trap 'rm -f "$ENV"' EXIT
{
  echo "MAPBOX_TOKEN=$(security find-generic-password -s velomaps-mapbox-token -w 2>/dev/null || true)"
  echo "APP_TOKEN=$(security find-generic-password -s velomaps-tts-app-token -w)"
  echo "DAILY_ROUTES=3000"
} > "$ENV"
scp -q "$ENV" $HOST:/etc/velomaps-route.env
ssh $HOST "chown root:velomaps /etc/velomaps-route.env && chmod 640 /etc/velomaps-route.env && chown -R root:root /opt/velomaps-route && chmod 755 /opt/velomaps-route && chmod 644 /opt/velomaps-route/velomaps_route.py && systemctl daemon-reload && systemctl enable --now velomaps-route && systemctl restart velomaps-route"
scp -q server/nginx-velomaps.conf $HOST:/etc/nginx/sites-available/velomaps
ssh $HOST "nginx -t 2>&1 | grep -v 'protocol options redefined' && systemctl reload nginx"
sleep 2
curl -s -w " (health HTTP %{http_code})\n" https://velomaps.104.236.120.144.sslip.io/route/health
curl -s -o /dev/null -w "no token: HTTP %{http_code}\n" "https://velomaps.104.236.120.144.sslip.io/route?from=40.78,-73.98&to=40.79,-73.97"
