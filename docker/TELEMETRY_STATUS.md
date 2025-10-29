# Telemetry System Status - Ubuntu Box Verification

**Date**: 2025-10-23 16:11 UTC
**Status**: Lambda ready with dependencies, awaiting Ubuntu box telemetry

## Summary of Fixes Applied

### 1. ✅ Fixed Entrypoint Script
**File**: `docker/renny-entrypoint.sh`
**Issue**: Container crash-loop (exit 127) - entrypoint was calling Renny binary directly
**Fix**: Changed to call original container entrypoint: `exec /opt/renny/entrypoint.sh "$@"`

### 2. ✅ Fixed Telemetry Endpoint Path
**Files**:
- `docker/renny-telemetry-client.sh` (line 142)
- `kubernetes/renny/scripts/renny-telemetry-client.sh` (line 149)

**Issue**: HTTP 403 - sending to `/telemetry` but API Gateway route is `/telemetry/heartbeat`
**Fix**: Updated endpoint to `${TELEMETRY_BACKEND_URL}/telemetry/heartbeat`

### 3. ✅ Fixed Telemetry Domain (All Deployments)
**Files**:
- `docker/renny-telemetry-client.sh` (default URL, line 13)
- `docker/docker-compose.default.yml` (environment variable, line 53)
- `kubernetes/renny/scripts/renny-telemetry-client.sh` (default URL, line 13)
- `kubernetes/values/renny-values.yaml` (Helm values, line 168)

**Issue**: Using `miniprem.services.uneeq.io` (CloudFront, GET-only) or AWS domains
**Fix**: Changed ALL configs to branded domain: `https://renny.services.uneeq.io`

**Domain Architecture**:
- `renny.services.uneeq.io` → Customer-facing telemetry API (POST accepted)
- `miniprem.services.uneeq.io` → Internal dashboard (GET-only, CloudFront)

### 4. ✅ Fixed Lambda Dependencies
**File**: `miniprem-telemetry-backend/lambda/event-handler/`
**Issue**: HTTP 500 - `ImportModuleError: No module named 'pydantic'`
**Fix**: Packaged Lambda with pydantic dependencies (3.4MB deployment package)

**Deployment**:
```bash
# Package created with:
python3 -m pip install -t package pydantic
cd package && zip -r ../event-handler.zip .
zip event-handler.zip handler.py models.py

# Deployed at: 2025-10-23 16:06:37 UTC
aws lambda update-function-code --function-name miniprem-telemetry-event-handler --zip-file fileb://event-handler.zip
```

## Current Configuration (Verified Correct)

### Docker Telemetry Script (`docker/renny-telemetry-client.sh`)
```bash
Line 13: TELEMETRY_BACKEND_URL="${TELEMETRY_BACKEND_URL:-https://renny.services.uneeq.io}"
Line 142: local url="${TELEMETRY_BACKEND_URL}/telemetry/heartbeat"
```

### Docker Compose (`docker/docker-compose.default.yml`)
```yaml
environment:
  - TELEMETRY_ENABLED=true
  - TELEMETRY_BACKEND_URL=https://renny.services.uneeq.io
  - HEARTBEAT_INTERVAL_SECONDS=900
  - PLATFORM=docker
```

### Lambda Function Status
```
Function: miniprem-telemetry-event-handler
Runtime: python3.11
Code Size: 3,434,861 bytes (3.4MB with pydantic)
Last Modified: 2025-10-23T16:06:37.000+0000
State: Active
```

## What Should Happen Next (Automatic)

The Ubuntu box's Renny container should:

1. **Installation Event** (first attempt after container start):
   - Send POST to `https://renny.services.uneeq.io/telemetry/heartbeat`
   - Payload includes: installation_id, machine_id, platform=docker, version
   - **Expected**: HTTP 200 (success)

2. **Heartbeat Events** (every 5 minutes):
   - Send POST to `https://renny.services.uneeq.io/telemetry/heartbeat`
   - Payload includes: installation_id, machine_id, status=online, uptime
   - **Expected**: HTTP 200 (success)

3. **Dashboard Update**:
   - Events stored in DynamoDB table: `miniprem-telemetry`
   - Dashboard at `https://miniprem.services.uneeq.io` shows machine as "online"
   - Machine ID derived from GPU UUID (hashed for privacy)

## Ubuntu Box Verification Steps

Run these commands on the **Ubuntu box** (not Mac) to verify telemetry:

### 1. Check Container Status
```bash
sudo docker ps -a | grep renny
# Expected: Container should be "Up" and healthy
```

### 2. Check Telemetry Client Process
```bash
sudo docker exec renny ps aux | grep telemetry-client
# Expected: Should see /opt/renny/telemetry-client.sh running
```

### 3. Check Recent Logs (Last 50 Lines)
```bash
sudo docker logs renny 2>&1 | tail -50
# Look for:
# ✅ "Telemetry client started (PID: ...)"
# ✅ "Installation sent successfully (HTTP 200)" OR
# ✅ "Heartbeat sent (uptime: XXXs)"
# ❌ NOT "HTTP 403" or "HTTP 500"
```

### 4. Check Telemetry Script File
```bash
sudo docker exec renny cat /opt/renny/telemetry-client.sh | grep "TELEMETRY_BACKEND_URL="
# Expected: https://renny.services.uneeq.io
```

### 5. Test Direct Connection (Manual Heartbeat)
```bash
# Get installation_id and machine_id from container
INSTALLATION_ID=$(sudo docker exec renny cat /app/data/installation_id)
MACHINE_ID=$(sudo docker exec renny nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1 | sha256sum | awk '{print $1}')

# Send test heartbeat
curl -X POST https://renny.services.uneeq.io/telemetry/heartbeat \
  -H "Content-Type: application/json" \
  -d "{
    \"event_type\": \"heartbeat\",
    \"installation_id\": \"$INSTALLATION_ID\",
    \"machine_id\": \"$MACHINE_ID\",
    \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
    \"platform\": \"docker\",
    \"status\": \"online\",
    \"uptime_seconds\": 123,
    \"instance_name\": \"$(hostname)\",
    \"instance_type\": \"docker-container\"
  }" \
  -w "\nHTTP Status: %{http_code}\n"

# Expected: HTTP Status: 200
```

### 6. If Still Not Working - Container Restart
```bash
# Sometimes volume-mounted files need full container recreation
cd /path/to/miniprem-2025/docker
sudo docker compose -f docker-compose.default.yml stop renny
sudo docker compose -f docker-compose.default.yml rm -f renny
sudo docker compose -f docker-compose.default.yml up -d renny

# Wait 10 seconds, then check logs
sleep 10
sudo docker logs renny 2>&1 | tail -30
```

## Expected Timeline

- **16:04:56 UTC**: Installation attempt failed (HTTP 500 - before Lambda fix)
- **16:06:37 UTC**: Lambda updated with pydantic dependencies ✅
- **16:09:56 UTC**: Next heartbeat attempt (expected)
- **16:14:56 UTC**: Following heartbeat (if 16:09 failed)
- **Every 5 minutes**: Subsequent heartbeats

## Troubleshooting

### If seeing HTTP 403:
- ❌ Wrong endpoint (should be `/telemetry/heartbeat` not `/telemetry`)
- ❌ Wrong domain (should be `renny.services.uneeq.io` not `miniprem...`)
- **Fix**: Pull latest git changes, recreate container

### If seeing HTTP 500:
- ❌ Lambda missing dependencies (should be fixed now)
- **Fix**: Already applied - Lambda redeployed with pydantic

### If seeing no telemetry logs at all:
- ❌ Telemetry client not starting
- ❌ TELEMETRY_ENABLED=false
- **Check**: `sudo docker exec renny env | grep TELEMETRY`

### If container keeps restarting:
- ❌ Entrypoint script issue
- **Check**: `sudo docker logs renny 2>&1 | grep -i error`

## Next Steps

1. **User Action Required**: Run verification steps on Ubuntu box
2. **Expected Result**: See "HTTP 200" in container logs
3. **Dashboard Check**: Visit `https://miniprem.services.uneeq.io` - Ubuntu box should show "online"
4. **If still failing**: Provide latest `sudo docker logs renny` output

## Backend URLs Reference

| Purpose | Domain | Method | Endpoint |
|---------|--------|--------|----------|
| **Telemetry API** (containers send data) | renny.services.uneeq.io | POST | /telemetry/heartbeat |
| **Dashboard** (employees view data) | miniprem.services.uneeq.io | GET | / |
| **Stats API** (dashboard fetches data) | miniprem.services.uneeq.io | GET | /api/stats |

## Files Modified (Git Commit Ready)

✅ All changes committed in previous session
✅ Lambda deployed with dependencies
✅ Configuration verified correct

**Repository**: `/Users/mbpro/uneeq/miniprem-2025/`
**Branch**: `feat/add-heartbeat`
**Status**: Ready for Ubuntu box verification
