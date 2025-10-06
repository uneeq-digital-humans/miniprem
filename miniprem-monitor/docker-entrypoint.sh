#!/bin/bash
set -e

echo "=========================================="
echo "Starting MiniPrem Monitor"
echo "=========================================="
echo ""
echo "Backend:  http://localhost:8000 (internal)"
echo "Frontend: http://localhost:3001 (external)"
echo ""
echo "Docker Socket: /var/run/docker.sock"
echo "Kubernetes: ${KUBE_CONFIG:-~/.kube/config}"
echo ""
echo "=========================================="

# Check if Docker socket is accessible
if [ -S /var/run/docker.sock ]; then
    echo "✓ Docker socket mounted successfully"
else
    echo "⚠ Warning: Docker socket not found at /var/run/docker.sock"
    echo "  Container monitoring will not work"
fi

# Check if kubectl config exists (optional)
if [ -f ~/.kube/config ] || [ -f /root/.kube/config ]; then
    echo "✓ Kubernetes config found"
else
    echo "ℹ Kubernetes config not found (optional)"
    echo "  K8s monitoring will be disabled"
fi

echo ""
echo "Starting services via supervisord..."
echo "=========================================="

# Start supervisord which manages both backend and frontend
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
