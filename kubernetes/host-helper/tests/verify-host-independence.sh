#!/usr/bin/env bash
# Automated guarantee that the DEFAULT install cannot depend on appliance host
# state (the Dell ref-arch field failure: kubelet FailedMount on strict-typed
# hostPaths for GDM/nerdctl that generic nodes don't have).
#
#   Usage: tests/verify-host-independence.sh [--kind]
#
# Layer 1 (always): render contract —
#   * default template contains ZERO hostPath volumes and no privileged
#     securityContext: nothing references the host, so no host can fail the
#     mount type-check;
#   * the appliance overlay restores exactly the five host mounts.
# Layer 2 (--kind, or in CI): default-values install on a kind cluster — a
#   REAL second host type with no GDM session and no nerdctl (the validator's
#   exact failure class) — must reach Ready and answer HTTP on :8086.
set -euo pipefail
CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$CHART_DIR/../values/host-helper-values-cns.yaml"

helm lint "$CHART_DIR"

R=$(helm template hh "$CHART_DIR")
echo "$R" | grep -q 'hostPath: {' && { echo 'FAIL: default render contains hostPath volumes'; exit 1; }
echo "$R" | grep -q 'privileged: true' && { echo 'FAIL: default render contains privileged securityContext'; exit 1; }
echo 'OK: default pod spec references no host state'

R=$(helm template hh "$CHART_DIR" -f "$OVERLAY")
N=$(echo "$R" | grep -c 'hostPath: {')
[ "$N" -eq 5 ] || { echo "FAIL: appliance overlay expected 5 hostPath volumes, got $N"; exit 1; }
echo "$R" | grep -q 'privileged: true' || { echo 'FAIL: appliance overlay lost privileged'; exit 1; }
echo 'OK: appliance mode intact'

if [ "${1:-}" = "--kind" ]; then
  kubectl create ns uneeq --dry-run=client -o yaml | kubectl apply -f -
  # gpu=false: kind has no GPUs; the GPU request is orthogonal to the
  # host-mount contract under test. Startup installs apt/pip deps: allow 10m.
  helm upgrade --install host-helper "$CHART_DIR" -n uneeq --set gpu=false
  kubectl -n uneeq rollout status deploy/host-helper --timeout=600s
  sleep 15
  PHASE=$(kubectl -n uneeq get pod -l app=host-helper -o jsonpath='{.items[0].status.phase}')
  [ "$PHASE" = "Running" ] || { kubectl -n uneeq describe pod -l app=host-helper | tail -30; exit 1; }
  # the container installs curl at startup; exec avoids kubectl-run log noise
  CODE=$(kubectl -n uneeq exec deploy/host-helper -- \
    curl -s -o /dev/null -w '%{http_code}' --max-time 15 http://localhost:8086/gpu)
  echo "GET /gpu -> HTTP $CODE"
  echo "$CODE" | grep -Eq '^[0-9]{3}$'   # any HTTP status = uvicorn serving
  echo 'OK: default install runs on a host with no appliance paths'
fi
