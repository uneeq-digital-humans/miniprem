#!/usr/bin/env python3
"""
Test script for AKS metrics endpoint.

This script tests the AKS metrics collection locally without requiring
a running FastAPI server.
"""

import asyncio
import json
import sys
from pathlib import Path

# Add app directory to Python path
sys.path.insert(0, str(Path(__file__).parent))

from app.routes.aks_metrics import aks_metrics_service


async def test_tools_availability():
    """Test Azure CLI and kubectl availability."""
    print("=" * 60)
    print("Testing Tools Availability")
    print("=" * 60)

    # Test Azure CLI
    print("\nChecking Azure CLI (az)...")
    az_available = await aks_metrics_service.check_az_availability()
    print(f"Azure CLI available: {az_available}")

    # Test kubectl
    print("\nChecking kubectl...")
    kubectl_available = await aks_metrics_service.check_kubectl_availability()
    print(f"kubectl available: {kubectl_available}")

    if not az_available:
        print("\n⚠️  Azure CLI not available. Install with: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli")
        print("    Then authenticate with: az login")

    if not kubectl_available:
        print("\n⚠️  kubectl not available. Install with: https://kubernetes.io/docs/tasks/tools/")

    return az_available and kubectl_available


async def test_cluster_detection():
    """Test AKS cluster detection."""
    print("\n" + "=" * 60)
    print("Testing Cluster Detection")
    print("=" * 60)

    try:
        cluster_info = await aks_metrics_service.detect_aks_cluster()
        print(f"\nDetected cluster info:")
        print(json.dumps(cluster_info, indent=2))

        if cluster_info['provider'] != 'aks':
            print(f"\n⚠️  Current cluster is {cluster_info['provider']}, not AKS")
            print("    Switch to an AKS cluster context with: kubectl config use-context <aks-context-name>")
            return False

        return True

    except Exception as e:
        print(f"\n❌ Error detecting cluster: {str(e)}")
        return False


async def test_full_metrics():
    """Test full AKS metrics collection."""
    print("\n" + "=" * 60)
    print("Testing Full AKS Metrics Collection")
    print("=" * 60)

    try:
        metrics = await aks_metrics_service.get_aks_metrics()

        print("\n✅ Successfully collected AKS metrics!")
        print("\n" + "-" * 60)
        print("Cluster Information")
        print("-" * 60)
        print(f"Cluster Name: {metrics.get('cluster_name')}")
        print(f"Resource Group: {metrics.get('resource_group')}")
        print(f"Location: {metrics.get('location')}")
        print(f"Kubernetes Version: {metrics.get('kubernetes_version')}")
        print(f"Provisioning State: {metrics.get('provisioning_state')}")

        print("\n" + "-" * 60)
        print("Node Pools")
        print("-" * 60)
        for np in metrics.get('node_pools', []):
            print(f"\nNode Pool: {np['name']}")
            print(f"  VM Size: {np['vm_size']}")
            print(f"  Current Count: {np['current_count']}")
            if np['auto_scaling_enabled']:
                print(f"  Min Count: {np['min_count']}")
                print(f"  Max Count: {np['max_count']}")
                print(f"  Auto-Scaling: Enabled")
            else:
                print(f"  Auto-Scaling: Disabled")
            print(f"  Health: {np['health_status']}")
            print(f"  Ready Nodes: {np['ready_nodes']}/{np['current_count']}")
            print(f"  Provisioning State: {np['provisioning_state']}")

        print("\n" + "-" * 60)
        print("Cluster Totals")
        print("-" * 60)
        totals = metrics.get('cluster_totals', {})
        print(f"Total Nodes: {totals.get('total_nodes')}")
        print(f"Ready Nodes: {totals.get('ready_nodes')}")
        print(f"Not Ready Nodes: {totals.get('not_ready_nodes')}")
        print(f"Total Pods: {totals.get('total_pods')}")
        print(f"  Running: {totals.get('running_pods')}")
        print(f"  Pending: {totals.get('pending_pods')}")
        print(f"  Failed: {totals.get('failed_pods')}")
        print(f"  Succeeded: {totals.get('succeeded_pods')}")
        print(f"Namespaces: {totals.get('namespace_count')}")

        print("\n" + "-" * 60)
        print("Cost Estimate")
        print("-" * 60)
        cost = metrics.get('cost_estimate', {})
        print(f"Hourly: ${cost.get('hourly_usd')}")
        print(f"Daily: ${cost.get('daily_usd')}")
        print(f"Monthly: ${cost.get('monthly_usd')}")

        print("\nCost Breakdown:")
        for item in cost.get('breakdown', []):
            print(f"  {item['node_pool']} ({item['vm_size']}): "
                  f"{item['node_count']} nodes × ${item['hourly_per_node']}/hr = "
                  f"${item['monthly_total']}/month")

        print(f"\nNote: {cost.get('note')}")

        print("\n" + "-" * 60)
        print("Full JSON Response")
        print("-" * 60)
        print(json.dumps(metrics, indent=2, default=str))

        return True

    except Exception as e:
        print(f"\n❌ Error collecting metrics: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


async def main():
    """Run all tests."""
    print("\n🚀 AKS Metrics Endpoint Test Suite")
    print("=" * 60)

    # Test 1: Tools availability
    tools_ok = await test_tools_availability()

    if not tools_ok:
        print("\n❌ Tools not available. Please install and configure required tools.")
        return 1

    # Test 2: Cluster detection
    cluster_ok = await test_cluster_detection()

    if not cluster_ok:
        print("\n❌ Cluster detection failed. Please ensure you're connected to an AKS cluster.")
        return 1

    # Test 3: Full metrics collection
    metrics_ok = await test_full_metrics()

    if not metrics_ok:
        print("\n❌ Metrics collection failed.")
        return 1

    print("\n" + "=" * 60)
    print("✅ All tests passed!")
    print("=" * 60)

    print("\nTo test the API endpoint, run:")
    print("  curl http://localhost:8000/api/kubernetes/metrics/aks | jq")

    return 0


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    sys.exit(exit_code)
