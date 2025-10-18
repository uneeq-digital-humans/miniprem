# Cluster Management API - curl Examples

Quick reference for testing the cluster management endpoints.

## Base URL
```bash
export BASE_URL="http://localhost:8000"
```

---

## 1. List All Clusters

**Simple:**
```bash
curl -X GET "${BASE_URL}/api/kubernetes/clusters/list"
```

**Pretty Print (with jq):**
```bash
curl -s -X GET "${BASE_URL}/api/kubernetes/clusters/list" | jq '.'
```

**Extract Specific Fields:**
```bash
# Get all cluster names
curl -s -X GET "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters[].cluster_name'

# Get current context
curl -s -X GET "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.current_context'

# Get accessible clusters only
curl -s -X GET "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.accessible == true) | {cluster_name, provider, region, node_count, pod_count}'

# Count clusters by provider
curl -s -X GET "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters | group_by(.provider) | map({provider: .[0].provider, count: length})'
```

---

## 2. Switch Context

**Basic Switch:**
```bash
curl -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "renny-aks-eastus"}'
```

**Pretty Print:**
```bash
curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "renny-aks-eastus"}' | jq '.'
```

**Switch to First Non-Current Context (Automated):**
```bash
# Get first non-current context
CONTEXT=$(curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters[] | select(.is_current == false) | .context_name' | head -1)

# Switch to it
curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d "{\"context_name\": \"${CONTEXT}\"}" | jq '.'
```

**Extract Cluster Info After Switch:**
```bash
curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "renny-aks-eastus"}' | \
  jq '{new_context, provider: .cluster_info.provider, region: .cluster_info.region, nodes: .cluster_info.node_count, pods: .cluster_info.pod_count}'
```

---

## 3. Error Testing

**Test Invalid Context:**
```bash
curl -s -w "\nHTTP Status: %{http_code}\n" \
  -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": "invalid-cluster-name"}' | jq '.'
```

**Test Empty Context Name:**
```bash
curl -s -w "\nHTTP Status: %{http_code}\n" \
  -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{"context_name": ""}' | jq '.'
```

**Test Missing Context Name:**
```bash
curl -s -w "\nHTTP Status: %{http_code}\n" \
  -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.'
```

---

## 4. Provider-Specific Queries

**List Only EKS Clusters:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.provider == "eks") | {cluster_name, region, accessible, node_count, pod_count}'
```

**List Only AKS Clusters:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.provider == "aks") | {cluster_name, region, accessible, node_count, pod_count}'
```

**List Only GKE Clusters:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.provider == "gke") | {cluster_name, region, accessible, node_count, pod_count}'
```

**List Clusters by Region:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.region == "us-east-1") | {cluster_name, provider, node_count, pod_count}'
```

---

## 5. Monitoring Queries

**Total Resource Count Across All Clusters:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '{total_nodes: ([.clusters[].node_count] | add), total_pods: ([.clusters[].pod_count] | add)}'
```

**Accessible vs Inaccessible:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '{accessible: .accessible_count, total: .total_count, percentage: ((.accessible_count / .total_count) * 100 | round)}'
```

**Cluster Summary Table:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters[] | "\(.cluster_name) | \(.provider) | \(.region) | \(if .accessible then "✓" else "✗" end) | \(.node_count) nodes | \(.pod_count) pods"'
```

---

## 6. Complete Workflow Example

```bash
#!/bin/bash
# Complete cluster management workflow

BASE_URL="http://localhost:8000"

echo "=== Step 1: List all clusters ==="
CLUSTERS=$(curl -s "${BASE_URL}/api/kubernetes/clusters/list")
echo "$CLUSTERS" | jq '{total_count, accessible_count, current_context}'

echo ""
echo "=== Step 2: Show cluster details ==="
echo "$CLUSTERS" | jq -r '.clusters[] | "\(.cluster_name): \(.provider) in \(.region) - \(if .accessible then "Accessible" else "Not Accessible" end)"'

echo ""
echo "=== Step 3: Get current context ==="
CURRENT=$(echo "$CLUSTERS" | jq -r '.current_context')
echo "Current: $CURRENT"

echo ""
echo "=== Step 4: Find an alternative context ==="
ALTERNATIVE=$(echo "$CLUSTERS" | jq -r '.clusters[] | select(.is_current == false) | .context_name' | head -1)

if [ -n "$ALTERNATIVE" ]; then
    echo "Alternative found: $ALTERNATIVE"

    echo ""
    echo "=== Step 5: Switch to alternative context ==="
    SWITCH_RESULT=$(curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
      -H "Content-Type: application/json" \
      -d "{\"context_name\": \"${ALTERNATIVE}\"}")

    echo "$SWITCH_RESULT" | jq '{success, new_context, cluster_info}'

    echo ""
    echo "=== Step 6: Switch back to original context ==="
    curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
      -H "Content-Type: application/json" \
      -d "{\"context_name\": \"${CURRENT}\"}" | jq '{success, new_context}'
else
    echo "No alternative context available"
fi
```

---

## 7. Performance Testing

**Measure Response Time:**
```bash
curl -w "\nTotal time: %{time_total}s\n" -o /dev/null -s \
  "${BASE_URL}/api/kubernetes/clusters/list"
```

**Concurrent Requests (Load Test):**
```bash
# Send 10 concurrent requests
for i in {1..10}; do
  curl -s "${BASE_URL}/api/kubernetes/clusters/list" > /dev/null &
done
wait
echo "All requests completed"
```

---

## 8. Integration Testing

**Test Full Workflow:**
```bash
# Save original context
ORIGINAL=$(curl -s "${BASE_URL}/api/kubernetes/clusters/list" | jq -r '.current_context')

# Get alternative context
ALTERNATIVE=$(curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters[] | select(.is_current == false) | .context_name' | head -1)

# Switch to alternative
curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d "{\"context_name\": \"${ALTERNATIVE}\"}" | jq '.success'

# Verify switch
NEW_CURRENT=$(curl -s "${BASE_URL}/api/kubernetes/clusters/list" | jq -r '.current_context')
echo "Expected: $ALTERNATIVE"
echo "Actual: $NEW_CURRENT"

if [ "$ALTERNATIVE" == "$NEW_CURRENT" ]; then
  echo "✓ Switch successful"
else
  echo "✗ Switch failed"
fi

# Restore original
curl -s -X POST "${BASE_URL}/api/kubernetes/context/switch" \
  -H "Content-Type: application/json" \
  -d "{\"context_name\": \"${ORIGINAL}\"}" > /dev/null

echo "✓ Restored original context: $ORIGINAL"
```

---

## 9. Debugging

**Verbose Output:**
```bash
curl -v -X GET "${BASE_URL}/api/kubernetes/clusters/list"
```

**Include HTTP Headers:**
```bash
curl -i -X GET "${BASE_URL}/api/kubernetes/clusters/list"
```

**Check API Health:**
```bash
curl -s "${BASE_URL}/health" | jq '.'
```

---

## 10. JSON Parsing Tips

**Extract Nested Fields:**
```bash
# Get server URLs
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '.clusters[] | "\(.cluster_name): \(.server_url)"'

# Get only accessible clusters with full details
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters[] | select(.accessible == true)'

# Count clusters by provider and region
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq '.clusters | group_by(.provider) | map({provider: .[0].provider, regions: (map(.region) | unique), count: length})'
```

**Format as Table:**
```bash
curl -s "${BASE_URL}/api/kubernetes/clusters/list" | \
  jq -r '["CLUSTER","PROVIDER","REGION","STATUS","NODES","PODS"],
  (.clusters[] | [.cluster_name, .provider, .region, (if .accessible then "✓" else "✗" end), .node_count, .pod_count]) |
  @tsv' | column -t
```

---

## Notes

- Replace `${BASE_URL}` with your actual API base URL
- Install `jq` for JSON parsing: `brew install jq` (macOS) or `apt install jq` (Ubuntu)
- For Windows, use Git Bash or WSL for curl commands
- Add `-k` flag for self-signed certificates: `curl -k ...`
