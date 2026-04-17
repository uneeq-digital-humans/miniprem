# Upgrading MiniPrem (Monitor + Renny)

This guide covers upgrading your MiniPrem installation to get the latest features and fixes.

## Quick Upgrade

Run this single command:

```bash
cd /path/to/miniprem-2025
sudo ./miniprem.sh upgrade
```

This will automatically:
1. Back up your config files (credentials, terraform vars, etc.)
2. Pull the latest code from git
3. Restore your config files
4. Pull the latest Renny image from Harbor
5. Rebuild MiniPrem Monitor with updated Docker CLI

After upgrade completes, restart services:
```bash
sudo ./miniprem.sh restart
```

## Common Issue: Docker API Version Mismatch

If you see this error in MiniPrem Monitor:

```
Error response from daemon: client version 1.43 is too old. Minimum supported API version is 1.44
```

This means your MiniPrem Monitor container has an outdated Docker CLI. Running `./miniprem.sh upgrade` will fix this.

## Manual Upgrade Steps

If you prefer to run the steps manually:

```bash
# 1. Navigate to your MiniPrem installation
cd /path/to/miniprem-2025

# 2. Pull latest code (your config files will be preserved)
git stash  # Stash any local changes
git pull
git stash pop  # Restore local changes

# 3. Pull the latest Renny image
cd docker
sudo docker compose pull renny

# 4. Rebuild the monitor container (this takes 2-5 minutes)
sudo docker compose build --no-cache --pull miniprem-monitor

# 5. Restart everything with latest images
sudo docker compose down
sudo docker compose up -d
```

> **Note:** The `./miniprem.sh upgrade` command automatically backs up and restores your config files (configuration.dat, terraform.tfvars, .cns_config, etc.) so you don't lose your credentials.

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
