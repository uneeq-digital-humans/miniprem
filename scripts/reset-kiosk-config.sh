#!/usr/bin/env bash
# Reset the kiosk's saved settings (personas, languages, welcome text, FAQs,
# theme, standby video) back to the deployment defaults baked into the build.
#
# For the kiosk owner / Dell field tech: if the on-box config gets into a bad
# state, run this on the kiosk server (needs sudo / docker access). The kiosk
# picks up the reset automatically the next time it's idle (within ~20s), or on
# the next page reload.
#
# NOTE: this does NOT change the Settings password — use reset-kiosk-password.sh
# for that.
set -euo pipefail

echo "Resetting kiosk settings to the deployment defaults…"

# The config lives in the rag-adapter's /data volume. Remove it → defaults.
if sudo docker exec rag-adapter sh -c 'rm -f /data/kiosk-config.json' 2>/dev/null; then
  echo "Done (via container)."
else
  # Fallback: remove straight from the Docker volume on disk.
  sudo rm -f /var/lib/docker/volumes/rag-adapter-data/_data/kiosk-config.json 2>/dev/null || true
  echo "Done (via volume)."
fi

echo "The kiosk will revert to defaults automatically when idle (or reload it now)."
