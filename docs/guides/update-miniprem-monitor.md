# Updating MiniPrem (Monitor + Renny)

## Problem

If you see this error in MiniPrem Monitor:

```
Error response from daemon: client version 1.43 is too old. Minimum supported API version is 1.44
```

This means your MiniPrem Monitor container has an outdated Docker CLI that's incompatible with your host's Docker Engine.

## Solution (Easy Way)

Run this single command on each affected server:

```bash
cd /path/to/miniprem-2025
sudo ./miniprem.sh update
```

This will automatically:
1. Pull the latest code from git
2. Pull the latest Renny image
3. Rebuild MiniPrem Monitor with updated Docker CLI
4. Restart all services
5. Verify the update was successful

## Solution (Manual)

If you prefer to run the steps manually:

```bash
# 1. Navigate to your MiniPrem installation
cd /path/to/miniprem-2025

# 2. Discard local changes and pull latest code
git checkout -- docker/docker-compose.yml
git pull

# 3. Pull the latest Renny image
cd docker
sudo docker compose pull renny

# 4. Rebuild the monitor container (this takes 2-5 minutes)
sudo docker compose build --no-cache --pull miniprem-monitor

# 5. Restart everything with latest images
sudo docker compose down
sudo docker compose up -d
```

## Verify the Fix

```bash
# Check the container's Docker CLI version - should show API 1.46+
sudo docker exec miniprem-monitor docker version
```

Expected output should show `API version: 1.46` (not 1.43).

## Troubleshooting

**"Permission denied" errors:**
```bash
sudo git checkout -- docker/docker-compose.yml
sudo git pull
```

**Container won't start after rebuild:**
```bash
# Check logs
sudo docker compose logs miniprem-monitor

# Force recreate
sudo docker compose up -d --force-recreate miniprem-monitor
```

**Still seeing API version errors:**
```bash
# Make sure old image is removed
sudo docker compose down
sudo docker rmi miniprem-monitor:latest 2>/dev/null || true
sudo docker compose build --no-cache --pull miniprem-monitor
sudo docker compose up -d
```

## Background

- Docker Engine 25.0+ (released Jan 2024) requires API version 1.44 minimum
- Older MiniPrem Monitor images shipped with Docker CLI 24.0.7 (API 1.43)
- The fix updates the container's Docker CLI to 27.5.1 (API 1.46)
