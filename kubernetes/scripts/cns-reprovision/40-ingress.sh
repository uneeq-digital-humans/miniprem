#!/usr/bin/env bash
# Phase 4 — ingress-nginx (hostNetwork :80/:443) so the on-box Chrome can reach the
# kiosk + adapter via the *.miniprem ingress hosts, + /etc/hosts entries resolving
# those names to localhost. Public images (no creds needed).
set -euo pipefail
log() { printf '\033[1;36m[ingress]\033[0m %s\n' "$*"; }
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

log "Installing ingress-nginx (hostNetwork)"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1 || \
  log "WARNING: helm repo update failed (github.io unreachable?) — falling back to the cached chart index"
# Fail fast with a real error if the chart is resolvable neither from the
# network nor the local helm cache — otherwise the install below dies cryptically.
helm show chart ingress-nginx/ingress-nginx >/dev/null 2>&1 || {
  echo "FATAL: chart ingress-nginx/ingress-nginx not resolvable (network down AND no cached index)" >&2
  exit 1
}
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.hostNetwork=true \
  --set controller.kind=DaemonSet \
  --set controller.service.type=ClusterIP \
  --set controller.ingressClassResource.default=true \
  --set controller.allowSnippetAnnotations=true \
  --set controller.config.annotations-risk-level=Critical

log "Adding /etc/hosts entries for the *.miniprem kiosk hosts -> 127.0.0.1"
for h in digitalhuman.miniprem digitalhuman-api.miniprem digitalhuman-asr.miniprem; do
  grep -q "$h" /etc/hosts || echo "127.0.0.1 $h" | sudo tee -a /etc/hosts >/dev/null
done

log "Phase 4 complete."
kubectl -n ingress-nginx get pods 2>/dev/null | tail -5 || true
