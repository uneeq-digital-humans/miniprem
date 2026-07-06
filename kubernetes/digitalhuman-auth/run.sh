#!/usr/bin/env bash
# Deploy the kiosk settings-auth container (localhost-only JWT issuer).
#
# Set the admin password via KIOSK_ADMIN_PASSWORD before running. A stable
# JWT_SECRET keeps tokens valid across restarts (optional; omit to rotate).
set -euo pipefail

: "${KIOSK_ADMIN_PASSWORD:?set KIOSK_ADMIN_PASSWORD to the kiosk admin password}"
JWT_SECRET="${JWT_SECRET:-}"
TOKEN_TTL_HOURS="${TOKEN_TTL_HOURS:-12}"

sudo docker build -t kiosk-auth:local .

sudo docker rm -f kiosk-auth >/dev/null 2>&1 || true
sudo docker run -d --name kiosk-auth --restart unless-stopped \
  --network host \
  -e "KIOSK_ADMIN_PASSWORD=${KIOSK_ADMIN_PASSWORD}" \
  -e "JWT_SECRET=${JWT_SECRET}" \
  -e "TOKEN_TTL_HOURS=${TOKEN_TTL_HOURS}" \
  kiosk-auth:local

echo "kiosk-auth on http://127.0.0.1:8087 (kiosk reaches it via nginx /auth/)."
echo "Add to the kiosk nginx default.conf:"
echo '  location /auth/ { proxy_pass http://127.0.0.1:8087/; }'
