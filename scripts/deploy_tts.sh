#!/usr/bin/env bash
# Deploy the Velo Maps voice service (server/tts) to the droplet. Secrets come from the Mac
# keychain (nemo-elevenlabs, velomaps-tts-app-token) and go to /etc/velomaps-tts.env
# (root:velomaps 0640) via a temp file that is deleted right after — never into git.
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=root@104.236.120.144
ssh $HOST "id velomaps >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin velomaps; mkdir -p /opt/velomaps-tts"
scp -q server/tts/velomaps_tts.py $HOST:/opt/velomaps-tts/velomaps_tts.py
scp -q server/tts/velomaps-tts.service $HOST:/etc/systemd/system/velomaps-tts.service
ENV=$(mktemp); chmod 600 "$ENV"
trap 'rm -f "$ENV"' EXIT
{
  echo "ELEVENLABS_API_KEY=$(security find-generic-password -s nemo-elevenlabs -w)"
  echo "APP_TOKEN=$(security find-generic-password -s velomaps-tts-app-token -w)"
  echo "DAILY_CHARS=5000"
} > "$ENV"
scp -q "$ENV" $HOST:/etc/velomaps-tts.env
ssh $HOST "chown root:velomaps /etc/velomaps-tts.env && chmod 640 /etc/velomaps-tts.env && chown -R root:root /opt/velomaps-tts && chmod 755 /opt/velomaps-tts && chmod 644 /opt/velomaps-tts/velomaps_tts.py && systemctl daemon-reload && systemctl enable --now velomaps-tts && systemctl restart velomaps-tts"
scp -q server/nginx-velomaps.conf $HOST:/etc/nginx/sites-available/velomaps
ssh $HOST "nginx -t 2>&1 | grep -v 'protocol options redefined' && systemctl reload nginx"
sleep 2
curl -s -w " (health HTTP %{http_code})\n" https://velomaps.104.236.120.144.sslip.io/tts/health
curl -s -o /dev/null -w "no token: HTTP %{http_code}\n" "https://velomaps.104.236.120.144.sslip.io/tts?text=hello"
