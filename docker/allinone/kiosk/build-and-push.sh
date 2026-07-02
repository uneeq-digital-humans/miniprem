#!/usr/bin/env bash
# Build the Dell-branded kiosk image from the uneeq-kiosk source (with our
# conversation/RAG features + Riva STT) and push to Harbor. Run once per kiosk
# code change; the appliance then just pulls the image.
#
# Usage: KIOSK_SRC=/path/to/uneeq-kiosk ./build-and-push.sh [tag]
set -euo pipefail
KIOSK_SRC="${KIOSK_SRC:-../../../../../uneeq-kiosk}"
TAG="${1:-latest}"
IMAGE="${KIOSK_IMAGE:-cr.uneeq.io/dell-isg-containers/digitalhuman-interface}"
# Build PROFILE (npm run build:<profile>). The kubeadm/ISO appliance is an
# ON-BOX MiniPrem kiosk (local NVIDIA RAG + Riva STT), so the default is
# `dell-miniprem` (VITE_DEPLOY_TYPE=miniprem, STT=riva, CONV=local) — NOT
# `dell` (that profile is the hosted web/cloud kiosk: web + deepgram + uneeq).
PROFILE="${KIOSK_PROFILE:-dell-miniprem}"

[ -f "$KIOSK_SRC/package.json" ] || { echo "uneeq-kiosk source not found at $KIOSK_SRC (set KIOSK_SRC)"; exit 1; }

echo "Building $IMAGE:$TAG (profile=build:$PROFILE) from $KIOSK_SRC ..."
# The kiosk repo builds a static SPA; serve it with nginx. We build the dist
# here and package it, so the appliance image is just nginx + dist + config.
( cd "$KIOSK_SRC" && npm ci && npm run "build:${PROFILE}" )

WORK="$(mktemp -d)"
cp -r "$KIOSK_SRC/dist/." "$WORK/"
cat > "$WORK/Dockerfile" <<'DOCKER'
FROM nginx:1.27-alpine
COPY . /usr/share/nginx/html
# SPA routing: fall back to index.html
RUN printf 'server { listen 80; root /usr/share/nginx/html; location / { try_files $uri $uri/ /index.html; } }\n' \
    > /etc/nginx/conf.d/default.conf
DOCKER

docker build -t "$IMAGE:$TAG" "$WORK"
docker push "$IMAGE:$TAG"
# A versioned push also moves :latest, since the kubeadm/ISO chart pulls :latest
# (kubernetes/digitalhuman-interface/values.yaml). Skip the redundant re-tag when
# the caller already pushed :latest.
if [ "$TAG" != "latest" ]; then
  docker tag "$IMAGE:$TAG" "$IMAGE:latest"
  docker push "$IMAGE:latest"
  echo "Also pushed $IMAGE:latest"
fi
rm -rf "$WORK"
echo "Pushed $IMAGE:$TAG"
