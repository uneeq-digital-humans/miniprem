#!/bin/bash
##
# Telemetry Verification Script for Ubuntu Box
#
# Run this script on the Ubuntu box to verify telemetry is working
##

set -e

echo "=========================================="
echo "MiniPrem Telemetry Verification"
echo "=========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Container Status
echo "1. Checking Renny container status..."
CONTAINER_STATUS=$(sudo docker ps -a --filter name=renny --format "{{.Status}}")
if [[ "$CONTAINER_STATUS" == *"Up"* ]]; then
    echo -e "${GREEN}✓${NC} Container is running: $CONTAINER_STATUS"
else
    echo -e "${RED}✗${NC} Container not running: $CONTAINER_STATUS"
    echo "   Fix: sudo docker compose -f docker-compose.yml up -d renny"
    exit 1
fi
echo ""

# Check 2: Telemetry Client Process
echo "2. Checking telemetry client process..."
if sudo docker exec renny ps aux | grep -q "[t]elemetry-client.sh"; then
    echo -e "${GREEN}✓${NC} Telemetry client is running"
else
    echo -e "${RED}✗${NC} Telemetry client not found"
    echo "   Check container logs: sudo docker logs renny"
fi
echo ""

# Check 3: Environment Variables
echo "3. Checking telemetry configuration..."
TELEMETRY_ENABLED=$(sudo docker exec renny env | grep "TELEMETRY_ENABLED=" | cut -d= -f2)
TELEMETRY_URL=$(sudo docker exec renny env | grep "TELEMETRY_BACKEND_URL=" | cut -d= -f2)

if [[ "$TELEMETRY_ENABLED" == "true" ]]; then
    echo -e "${GREEN}✓${NC} TELEMETRY_ENABLED=true"
else
    echo -e "${RED}✗${NC} TELEMETRY_ENABLED=$TELEMETRY_ENABLED (should be true)"
fi

if [[ "$TELEMETRY_URL" == "https://renny.services.uneeq.io" ]]; then
    echo -e "${GREEN}✓${NC} TELEMETRY_BACKEND_URL=https://renny.services.uneeq.io"
else
    echo -e "${YELLOW}⚠${NC} TELEMETRY_BACKEND_URL=$TELEMETRY_URL"
    echo "   Expected: https://renny.services.uneeq.io"
fi
echo ""

# Check 4: Telemetry Script Endpoint
echo "4. Checking telemetry script endpoint..."
SCRIPT_URL=$(sudo docker exec renny grep "TELEMETRY_BACKEND_URL=" /opt/renny/telemetry-client.sh | head -1)
if echo "$SCRIPT_URL" | grep -q "renny.services.uneeq.io"; then
    echo -e "${GREEN}✓${NC} Script uses correct domain: renny.services.uneeq.io"
else
    echo -e "${YELLOW}⚠${NC} Script URL: $SCRIPT_URL"
fi

ENDPOINT=$(sudo docker exec renny grep "local url=" /opt/renny/telemetry-client.sh)
if echo "$ENDPOINT" | grep -q "/telemetry/heartbeat"; then
    echo -e "${GREEN}✓${NC} Script uses correct endpoint: /telemetry/heartbeat"
else
    echo -e "${YELLOW}⚠${NC} Endpoint: $ENDPOINT"
fi
echo ""

# Check 5: Recent Logs
echo "5. Checking recent telemetry logs (last 20 lines with 'telemetry')..."
RECENT_LOGS=$(sudo docker logs renny 2>&1 | grep -i "telemetry\|heartbeat\|installation" | tail -20)

if echo "$RECENT_LOGS" | grep -q "HTTP 200"; then
    echo -e "${GREEN}✓${NC} Telemetry working - HTTP 200 responses found:"
    echo "$RECENT_LOGS" | grep "HTTP 200" | tail -3
elif echo "$RECENT_LOGS" | grep -q "HTTP 500"; then
    echo -e "${RED}✗${NC} Telemetry failing - HTTP 500 errors:"
    echo "$RECENT_LOGS" | grep "HTTP 500" | tail -3
    echo "   Backend issue - Lambda may need redeployment"
elif echo "$RECENT_LOGS" | grep -q "HTTP 403"; then
    echo -e "${RED}✗${NC} Telemetry failing - HTTP 403 errors:"
    echo "$RECENT_LOGS" | grep "HTTP 403" | tail -3
    echo "   Wrong endpoint or domain - container needs update"
else
    echo -e "${YELLOW}⚠${NC} No HTTP status codes found in recent logs"
    echo "   Latest telemetry-related logs:"
    echo "$RECENT_LOGS" | tail -5
fi
echo ""

# Check 6: Installation ID
echo "6. Checking installation ID..."
if sudo docker exec renny test -f /app/data/installation_id; then
    INSTALLATION_ID=$(sudo docker exec renny cat /app/data/installation_id)
    echo -e "${GREEN}✓${NC} Installation ID exists: $INSTALLATION_ID"
else
    echo -e "${RED}✗${NC} Installation ID file missing: /app/data/installation_id"
fi
echo ""

# Check 7: GPU Access for Machine ID
echo "7. Checking GPU access for machine ID generation..."
if sudo docker exec renny nvidia-smi --query-gpu=uuid --format=csv,noheader &>/dev/null; then
    GPU_UUID=$(sudo docker exec renny nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)
    MACHINE_ID=$(echo -n "$GPU_UUID" | sha256sum | awk '{print $1}')
    echo -e "${GREEN}✓${NC} GPU accessible: $GPU_UUID"
    echo "   Machine ID (hashed): ${MACHINE_ID:0:16}..."
else
    echo -e "${YELLOW}⚠${NC} GPU not accessible - will use hostname fallback"
    HOSTNAME=$(sudo docker exec renny hostname)
    MACHINE_ID=$(echo -n "$HOSTNAME" | sha256sum | awk '{print $1}')
    echo "   Hostname: $HOSTNAME"
    echo "   Machine ID (hashed): ${MACHINE_ID:0:16}..."
fi
echo ""

# Check 8: Test Connection
echo "8. Testing direct connection to telemetry API..."
INSTALLATION_ID=$(sudo docker exec renny cat /app/data/installation_id 2>/dev/null || echo "test-install-id")
GPU_UUID=$(sudo docker exec renny nvidia-smi --query-gpu=uuid --format=csv,noheader 2>/dev/null | head -n1 || echo "")
if [ -n "$GPU_UUID" ]; then
    MACHINE_ID=$(echo -n "$GPU_UUID" | sha256sum | awk '{print $1}')
else
    HOSTNAME=$(sudo docker exec renny hostname)
    MACHINE_ID=$(echo -n "$HOSTNAME" | sha256sum | awk '{print $1}')
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST https://renny.services.uneeq.io/telemetry/heartbeat \
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
  --max-time 10 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✓${NC} Manual telemetry test: HTTP $HTTP_CODE (SUCCESS)"
    echo "   Telemetry backend is working correctly!"
elif [[ "$HTTP_CODE" == "403" ]]; then
    echo -e "${RED}✗${NC} Manual telemetry test: HTTP $HTTP_CODE (FORBIDDEN)"
    echo "   Possible causes:"
    echo "   - Wrong endpoint (check CloudFront vs API Gateway)"
    echo "   - CORS issue"
elif [[ "$HTTP_CODE" == "500" ]]; then
    echo -e "${RED}✗${NC} Manual telemetry test: HTTP $HTTP_CODE (SERVER ERROR)"
    echo "   Backend Lambda function issue"
    echo "   Check Lambda logs in AWS CloudWatch"
else
    echo -e "${RED}✗${NC} Manual telemetry test: HTTP $HTTP_CODE (FAILED)"
    echo "   Network issue or API unavailable"
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
if sudo docker logs renny 2>&1 | grep -q "HTTP 200"; then
    echo -e "${GREEN}✓ Telemetry is working!${NC}"
    echo "  Check dashboard: https://miniprem.services.uneeq.io"
    echo "  Your machine should appear as 'online'"
elif sudo docker logs renny 2>&1 | grep -q "HTTP 500"; then
    echo -e "${YELLOW}⚠ Telemetry reaching backend but Lambda failing${NC}"
    echo "  Backend team: Check Lambda function logs"
    echo "  Deployment: Ensure Lambda has pydantic dependencies"
elif sudo docker logs renny 2>&1 | grep -q "HTTP 403"; then
    echo -e "${RED}✗ Wrong endpoint or domain configuration${NC}"
    echo "  1. Pull latest git changes:"
    echo "     cd /path/to/miniprem-2025"
    echo "     git pull origin feat/add-heartbeat"
    echo "  2. Recreate container:"
    echo "     cd docker"
    echo "     sudo docker compose -f docker-compose.yml stop renny"
    echo "     sudo docker compose -f docker-compose.yml rm -f renny"
    echo "     sudo docker compose -f docker-compose.yml up -d renny"
else
    echo -e "${YELLOW}⚠ Telemetry client may not be sending requests${NC}"
    echo "  Check full logs:"
    echo "     sudo docker logs renny 2>&1 | less"
    echo "  Look for telemetry startup messages"
fi
echo ""

# Wait for next heartbeat
echo "Waiting for next automatic heartbeat (checking for 60 seconds)..."
echo "Press Ctrl+C to stop monitoring"
echo ""

for i in {1..12}; do
    sleep 5
    LATEST_LOG=$(sudo docker logs renny 2>&1 | grep -i "heartbeat\|installation" | tail -1)
    if echo "$LATEST_LOG" | grep -q "HTTP 200"; then
        echo -e "${GREEN}✓ SUCCESS!${NC} New heartbeat detected:"
        echo "$LATEST_LOG"
        break
    elif echo "$LATEST_LOG" | grep -q "HTTP"; then
        echo -e "${YELLOW}⚠${NC} Heartbeat attempt detected:"
        echo "$LATEST_LOG"
    fi
done

echo ""
echo "Verification complete!"
