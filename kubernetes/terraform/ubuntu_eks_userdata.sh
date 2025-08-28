#!/bin/bash

# Ubuntu EKS node bootstrap script using official EKS bootstrap.sh
# This matches the production infra approach and uses public Ubuntu EKS AMIs

set -o xtrace
set -e

# Enhanced logging
exec > >(tee -a /var/log/bootstrap.log)
exec 2>&1

echo "=== Ubuntu EKS Bootstrap Started: $(date) ==="

# Variables from Terraform template
CLUSTER_NAME="${cluster_name}"
CLUSTER_ENDPOINT="${cluster_endpoint}"
CLUSTER_CA="${cluster_ca}"
NODE_LABELS="${node_labels}"
CLUSTER_DNS_IP="${cluster_dns_ip}"

echo "Cluster: $CLUSTER_NAME"
echo "Endpoint: $CLUSTER_ENDPOINT"
echo "DNS IP: $CLUSTER_DNS_IP"
echo "Node Labels: $NODE_LABELS"

# Use official EKS bootstrap script (included in Ubuntu EKS AMIs)
echo "=== Starting EKS bootstrap script ==="
/etc/eks/bootstrap.sh \
    --apiserver-endpoint "$CLUSTER_ENDPOINT" \
    --b64-cluster-ca "$CLUSTER_CA" \
    --dns-cluster-ip "$CLUSTER_DNS_IP" \
    --kubelet-extra-args "--node-labels=$NODE_LABELS" \
    "$CLUSTER_NAME"

# Verify kubelet is running
echo "=== Verifying kubelet status ==="
if systemctl is-active --quiet kubelet; then
    echo "✅ Kubelet is running successfully"
    systemctl status kubelet --no-pager -l | head -10
else
    echo "❌ Kubelet failed to start"
    systemctl status kubelet --no-pager -l
    journalctl -u kubelet --no-pager -l --since "5 minutes ago"
    exit 1
fi

echo "=== Ubuntu EKS Bootstrap Completed: $(date) ==="
echo "✅ Node should join cluster within 2-3 minutes"
echo "GPU drivers will be installed via NVIDIA GPU Operator after deployment"