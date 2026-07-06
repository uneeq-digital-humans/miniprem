#!/usr/bin/env bash
# Reset the kiosk Settings password back to the factory default.
#
# The factory default is "digitalhuman" unless this kiosk was installed with a
# custom KIOSK_SETTINGS_PASSWORD (set on the rag-adapter container by the ISO /
# installer) — in that case it reverts to whatever the installer configured.
#
# For the kiosk owner / Dell field tech: if the Settings admin password is lost,
# run this on the kiosk server (needs sudo / docker access). After running, open
# Settings with the default password and set a new one.
set -euo pipefail

echo "Resetting kiosk Settings password to the installation default…"

# The password hash lives in the rag-adapter's /data volume. Remove it → default.
if sudo docker exec rag-adapter sh -c 'rm -f /data/settings-password.json' 2>/dev/null; then
  echo "Done (via container)."
else
  # Fallback: remove straight from the Docker volume on disk.
  sudo rm -f /var/lib/docker/volumes/rag-adapter-data/_data/settings-password.json 2>/dev/null || true
  echo "Done (via volume)."
fi

echo "Open the kiosk Settings and enter:  changeme  — then set a new password."
