#!/usr/bin/env bash
# Upload NYC speed-limit tiles (build_speed_limit_tiles.sh) to the droplet and make sure the
# vhost + cert exist. Configs go up by scp, never via an ssh heredoc (droplet gotcha).
set -euo pipefail
cd "$(dirname "$0")/.."
HOST=root@104.236.120.144
NAME=velomaps.104.236.120.144.sslip.io
[ -d build.nosync/tiles ] || { echo "run build_speed_limit_tiles.sh first"; exit 1; }

ssh $HOST "mkdir -p /var/www/velomaps/speedlimits/v1"
# System rsync (Homebrew's breaks some Apple tooling; harmless here but keep one rsync).
/usr/bin/rsync -az --delete build.nosync/tiles/ $HOST:/var/www/velomaps/speedlimits/v1/
ssh $HOST "chown -R www-data:www-data /var/www/velomaps && find /var/www/velomaps -type d -exec chmod 755 {} + && find /var/www/velomaps -type f -exec chmod 644 {} +"

if ! ssh $HOST "test -f /etc/letsencrypt/live/velomaps/fullchain.pem"; then
  scp server/nginx-velomaps-bootstrap.conf $HOST:/etc/nginx/sites-available/velomaps
  ssh $HOST "ln -sf /etc/nginx/sites-available/velomaps /etc/nginx/sites-enabled/velomaps && nginx -t && systemctl reload nginx"
  ssh $HOST "certbot certonly --webroot -w /var/www/html --cert-name velomaps -d $NAME --non-interactive --agree-tos --keep-until-expiring --account 1185545de5ca9457f70f80eb8f49fdc1"
fi
scp server/nginx-velomaps.conf $HOST:/etc/nginx/sites-available/velomaps
ssh $HOST "ln -sf /etc/nginx/sites-available/velomaps /etc/nginx/sites-enabled/velomaps && nginx -t && systemctl reload nginx"

echo "== check =="
curl -s -o /dev/null -w "tile: HTTP %{http_code}, %{size_download} bytes (gzip)\n" -H "Accept-Encoding: gzip" https://$NAME/speedlimits/v1/4078_-7399.json
curl -s -o /dev/null -w "missing tile: HTTP %{http_code}\n" https://$NAME/speedlimits/v1/0_0.json
