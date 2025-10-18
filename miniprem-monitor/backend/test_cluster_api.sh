#!/bin/bash
#
# Test Script for Cluster Management API Endpoints
#
# Usage: ./test_cluster_api.sh [BASE_URL]
# Default BASE_URL: http://localhost:8000
#
# Author: MiniPrem Monitor Backend
# Date: 2025-10-16

set -e

BASE_URL="${1:-http://localhost:8000}"
API_PREFIX="/api/kubernetes"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Cluster Management API Testing${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Base URL: ${YELLOW}${BASE_URL}${NC}"
echo ""

# Test 1: List all clusters
echo -e "${GREEN}Test 1: GET ${API_PREFIX}/clusters/list${NC}"
echo -e "${BLUE}Description: List all available kubectl contexts${NC}"
echo ""
echo -e "${YELLOW}Request:${NC}"
echo "curl -X GET \"${BASE_URL}${API_PREFIX}/clusters/list\""
echo ""
echo -e "${YELLOW}Response:${NC}"
RESPONSE=$(curl -s -X GET "${BASE_URL}${API_PREFIX}/clusters/list")
echo "$RESPONSE" | jq '.'
echo ""

# Extract current context for next test
CURRENT_CONTEXT=$(echo "$RESPONSE" | jq -r '.current_context // empty')
TOTAL_CLUSTERS=$(echo "$RESPONSE" | jq -r '.total_count // 0')
ACCESSIBLE_CLUSTERS=$(echo "$RESPONSE" | jq -r '.accessible_count // 0')

echo -e "${GREEN}Summary:${NC}"
echo "  - Total clusters: $TOTAL_CLUSTERS"
echo "  - Accessible clusters: $ACCESSIBLE_CLUSTERS"
echo "  - Current context: $CURRENT_CONTEXT"
echo ""
echo -e "${BLUE}--------------------------------------------${NC}"
echo ""

# Test 2: Switch context (if multiple contexts exist)
if [ "$TOTAL_CLUSTERS" -gt 1 ]; then
    # Get first non-current context
    TARGET_CONTEXT=$(echo "$RESPONSE" | jq -r '.clusters[] | select(.is_current == false) | .context_name' | head -1)

    if [ -n "$TARGET_CONTEXT" ]; then
        echo -e "${GREEN}Test 2: POST ${API_PREFIX}/context/switch${NC}"
        echo -e "${BLUE}Description: Switch to a different kubectl context${NC}"
        echo ""
        echo -e "${YELLOW}Request:${NC}"
        echo "curl -X POST \"${BASE_URL}${API_PREFIX}/context/switch\" \\"
        echo "  -H \"Content-Type: application/json\" \\"
        echo "  -d '{\"context_name\": \"${TARGET_CONTEXT}\"}'"
        echo ""
        echo -e "${YELLOW}Response:${NC}"
        SWITCH_RESPONSE=$(curl -s -X POST "${BASE_URL}${API_PREFIX}/context/switch" \
            -H "Content-Type: application/json" \
            -d "{\"context_name\": \"${TARGET_CONTEXT}\"}")
        echo "$SWITCH_RESPONSE" | jq '.'
        echo ""

        NEW_CONTEXT=$(echo "$SWITCH_RESPONSE" | jq -r '.new_context // empty')
        PREVIOUS_CONTEXT=$(echo "$SWITCH_RESPONSE" | jq -r '.previous_context // empty')
        CLUSTER_NAME=$(echo "$SWITCH_RESPONSE" | jq -r '.cluster_info.cluster_name // "N/A"')
        PROVIDER=$(echo "$SWITCH_RESPONSE" | jq -r '.cluster_info.provider // "N/A"')
        REGION=$(echo "$SWITCH_RESPONSE" | jq -r '.cluster_info.region // "N/A"')
        NODE_COUNT=$(echo "$SWITCH_RESPONSE" | jq -r '.cluster_info.node_count // 0')
        POD_COUNT=$(echo "$SWITCH_RESPONSE" | jq -r '.cluster_info.pod_count // 0')

        echo -e "${GREEN}Summary:${NC}"
        echo "  - Previous context: $PREVIOUS_CONTEXT"
        echo "  - New context: $NEW_CONTEXT"
        echo "  - Cluster name: $CLUSTER_NAME"
        echo "  - Provider: $PROVIDER"
        echo "  - Region: $REGION"
        echo "  - Nodes: $NODE_COUNT"
        echo "  - Pods: $POD_COUNT"
        echo ""

        # Switch back to original context
        if [ -n "$CURRENT_CONTEXT" ]; then
            echo -e "${YELLOW}Switching back to original context...${NC}"
            curl -s -X POST "${BASE_URL}${API_PREFIX}/context/switch" \
                -H "Content-Type: application/json" \
                -d "{\"context_name\": \"${CURRENT_CONTEXT}\"}" > /dev/null
            echo -e "${GREEN}✓ Restored original context${NC}"
            echo ""
        fi
    else
        echo -e "${YELLOW}Test 2: Skipped (only one accessible context)${NC}"
        echo ""
    fi
else
    echo -e "${YELLOW}Test 2: Skipped (only one cluster found)${NC}"
    echo ""
fi

echo -e "${BLUE}--------------------------------------------${NC}"
echo ""

# Test 3: Error handling - invalid context
echo -e "${GREEN}Test 3: POST ${API_PREFIX}/context/switch (Error Case)${NC}"
echo -e "${BLUE}Description: Attempt to switch to non-existent context${NC}"
echo ""
echo -e "${YELLOW}Request:${NC}"
echo "curl -X POST \"${BASE_URL}${API_PREFIX}/context/switch\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"context_name\": \"invalid-cluster-context\"}'"
echo ""
echo -e "${YELLOW}Response:${NC}"
ERROR_RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${BASE_URL}${API_PREFIX}/context/switch" \
    -H "Content-Type: application/json" \
    -d '{"context_name": "invalid-cluster-context"}')

HTTP_STATUS=$(echo "$ERROR_RESPONSE" | grep "HTTP_STATUS" | cut -d':' -f2)
ERROR_BODY=$(echo "$ERROR_RESPONSE" | sed '/HTTP_STATUS/d')

echo "$ERROR_BODY" | jq '.'
echo ""
echo -e "${GREEN}Summary:${NC}"
echo "  - HTTP Status: $HTTP_STATUS"
echo "  - Expected: 404 (Not Found)"
if [ "$HTTP_STATUS" == "404" ]; then
    echo -e "  - ${GREEN}✓ Correct error handling${NC}"
else
    echo -e "  - ${RED}✗ Unexpected status code${NC}"
fi
echo ""

echo -e "${BLUE}--------------------------------------------${NC}"
echo ""

# Test 4: Provider detection validation
echo -e "${GREEN}Test 4: Provider Detection Validation${NC}"
echo -e "${BLUE}Description: Verify provider detection for all clusters${NC}"
echo ""

EKS_COUNT=$(echo "$RESPONSE" | jq -r '[.clusters[] | select(.provider == "eks")] | length')
AKS_COUNT=$(echo "$RESPONSE" | jq -r '[.clusters[] | select(.provider == "aks")] | length')
GKE_COUNT=$(echo "$RESPONSE" | jq -r '[.clusters[] | select(.provider == "gke")] | length')
LOCAL_COUNT=$(echo "$RESPONSE" | jq -r '[.clusters[] | select(.provider == "local")] | length')
UNKNOWN_COUNT=$(echo "$RESPONSE" | jq -r '[.clusters[] | select(.provider == "unknown")] | length')

echo -e "${GREEN}Provider Distribution:${NC}"
echo "  - EKS (AWS): $EKS_COUNT"
echo "  - AKS (Azure): $AKS_COUNT"
echo "  - GKE (Google): $GKE_COUNT"
echo "  - Local: $LOCAL_COUNT"
echo "  - Unknown: $UNKNOWN_COUNT"
echo ""

if [ "$EKS_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}EKS Clusters:${NC}"
    echo "$RESPONSE" | jq -r '.clusters[] | select(.provider == "eks") | "  - \(.cluster_name) (\(.region))"'
    echo ""
fi

if [ "$AKS_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}AKS Clusters:${NC}"
    echo "$RESPONSE" | jq -r '.clusters[] | select(.provider == "aks") | "  - \(.cluster_name) (\(.region))"'
    echo ""
fi

if [ "$GKE_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}GKE Clusters:${NC}"
    echo "$RESPONSE" | jq -r '.clusters[] | select(.provider == "gke") | "  - \(.cluster_name) (\(.region))"'
    echo ""
fi

echo -e "${BLUE}--------------------------------------------${NC}"
echo ""

# Test 5: Accessibility check
echo -e "${GREEN}Test 5: Cluster Accessibility Check${NC}"
echo -e "${BLUE}Description: Verify accessibility status for all clusters${NC}"
echo ""

echo "$RESPONSE" | jq -r '.clusters[] | "\(.cluster_name): \(if .accessible then "✓ Accessible" else "✗ Not Accessible" end) (\(.node_count) nodes, \(.pod_count) pods)"'
echo ""

echo -e "${BLUE}============================================${NC}"
echo -e "${GREEN}All tests completed!${NC}"
echo -e "${BLUE}============================================${NC}"
