# AKS Renny Helm Values Guide

This guide explains how to deploy Renny on Azure Kubernetes Service (AKS) using the AKS-specific Helm values override.

## Overview

The `renny-values-aks.yaml` file provides AKS-specific configuration overrides optimized for:
- **NC16as_T4_v3** GPU nodes (16 vCPUs, 110GB RAM, 1x NVIDIA T4 16GB)
- 4 Renny pods per node (no GPU time-slicing needed)
- 10 nodes = 40 total Renny instances

## Quick Start

### 1. Verify Prerequisites

Ensure you have:
- AKS cluster with GPU node pool (NC16as_T4_v3)
- GPU operator installed and running
- kubectl configured to access the cluster
- Helm 3.x installed

### 2. Deploy Renny

Deploy using both base and AKS-specific values:

```bash
helm install renny ./renny-chart \
  -f renny-values.yaml \
  -f renny-values-aks.yaml \
  --namespace uneeq-renderer \
  --create-namespace
```

### 3. Verify Deployment

Check pod status:

```bash
# View all Renny pods
kubectl get pods -n uneeq-renderer -l app=renny

# Check GPU allocation
kubectl describe pods -n uneeq-renderer -l app=renny | grep nvidia.com/gpu

# View pod distribution across nodes
kubectl get pods -n uneeq-renderer -o wide
```

Expected output:
```
NAME         READY   STATUS    RESTARTS   AGE   NODE
renny-0      1/1     Running   0          2m    aks-gpupool-12345678-vmss000000
renny-1      1/1     Running   0          2m    aks-gpupool-12345678-vmss000000
renny-2      1/1     Running   0          2m    aks-gpupool-12345678-vmss000000
renny-3      1/1     Running   0          2m    aks-gpupool-12345678-vmss000000
...
```

## Configuration Details

### Resource Allocation

Each Renny pod requests:
- **CPU**: 3 cores (leaves headroom for system pods)
- **Memory**: 6GB (leaves headroom for OS and GPU drivers)
- **GPU**: 1 full T4 GPU (16GB VRAM, no time-slicing)

**Node capacity:**
- NC16as_T4_v3: 16 vCPUs, 110GB RAM, 1x T4 GPU
- 4 pods per node = 12 vCPUs used, 24GB RAM used

### GPU Time-Slicing Configuration

```yaml
gpuTimeSlicing:
  replicasPerGpu: 1  # No time-slicing (full GPU per pod)
```

**Why no time-slicing?**
- T4 has 16GB VRAM (sufficient for single Renny instance)
- No GPU sharing needed (unlike EKS with A10G where 2-4 pods share 1 GPU)
- Simpler configuration and better performance isolation

### Scaling Configuration

```yaml
deployment:
  totalReplicas: 40  # 10 nodes × 4 pods
```

**To change replica count:**

1. Edit `renny-values-aks.yaml`:
   ```yaml
   deployment:
     totalReplicas: 80  # 20 nodes × 4 pods
   ```

2. Apply changes:
   ```bash
   helm upgrade renny ./renny-chart \
     -f renny-values.yaml \
     -f renny-values-aks.yaml \
     --namespace uneeq-renderer
   ```

3. Verify scaling:
   ```bash
   kubectl get pods -n uneeq-renderer --watch
   ```

### Node Affinity and Tolerations

Ensures pods only run on GPU nodes:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: workload-type
          operator: In
          values:
          - gpu

tolerations:
- key: nvidia.com/gpu
  operator: Equal
  value: "true"
  effect: NoSchedule
```

**Verify node labels:**

```bash
kubectl get nodes -L workload-type,uneeq.io/node-type
```

### Health Checks

Liveness and readiness probes configured for Renny:

```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8081
  initialDelaySeconds: 60
  periodSeconds: 30

readinessProbe:
  httpGet:
    path: /health
    port: 8081
  initialDelaySeconds: 30
  periodSeconds: 10
```

**Check probe status:**

```bash
kubectl describe pods -n uneeq-renderer -l app=renny | grep -A 10 "Liveness:\|Readiness:"
```

### Pod Disruption Budget

Ensures high availability during node upgrades:

```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 35  # 35/40 pods must remain available
```

**View PDB status:**

```bash
kubectl get pdb -n uneeq-renderer
kubectl describe pdb -n uneeq-renderer
```

## Customization Examples

### Example 1: Change Pod Density (2 Pods per Node)

If you want fewer pods per node for better performance:

```yaml
# renny-values-aks-custom.yaml
resources:
  requests:
    cpu: "7"        # More CPU per pod
    memory: "12Gi"  # More RAM per pod
    nvidia.com/gpu: 1

deployment:
  totalReplicas: 20  # 10 nodes × 2 pods
```

Deploy:
```bash
helm upgrade renny ./renny-chart \
  -f renny-values.yaml \
  -f renny-values-aks.yaml \
  -f renny-values-aks-custom.yaml \
  --namespace uneeq-renderer
```

### Example 2: Enable Horizontal Pod Autoscaler

For dynamic scaling based on CPU/memory usage:

```yaml
# renny-values-aks-custom.yaml
autoscaling:
  enabled: true
  minReplicas: 20
  maxReplicas: 40
  targetCPUUtilizationPercentage: 70
```

**Monitor HPA:**

```bash
kubectl get hpa -n uneeq-renderer
kubectl describe hpa -n uneeq-renderer
```

### Example 3: Enable Azure Monitor Integration

For production monitoring:

```yaml
# renny-values-aks-custom.yaml
monitoring:
  enabled: true
  prometheusOperator: true
  serviceMonitor:
    enabled: true
    interval: 30s
```

**View metrics:**

```bash
kubectl get servicemonitor -n uneeq-renderer
kubectl get prometheus -A
```

## Troubleshooting

### Pods Stuck in Pending State

Check GPU availability:

```bash
# View GPU nodes
kubectl get nodes -l workload-type=gpu

# Check GPU capacity
kubectl describe nodes -l workload-type=gpu | grep -A 5 "Allocatable:"

# View pending pod events
kubectl describe pods -n uneeq-renderer | grep -A 10 "Events:"
```

Common issues:
- **Insufficient GPU nodes**: Scale up node pool
- **GPU not detected**: Check GPU operator installation
- **Node affinity mismatch**: Verify node labels

### Pods Failing Health Checks

View pod logs:

```bash
kubectl logs -n uneeq-renderer <pod-name> --tail=50
kubectl logs -n uneeq-renderer <pod-name> --previous  # Previous container
```

Common issues:
- **Slow startup**: Increase `initialDelaySeconds` in health probes
- **Port conflicts**: Verify port 8081 is not in use
- **GPU driver issues**: Check NVIDIA GPU operator logs

### High CPU/Memory Usage

Check resource utilization:

```bash
# Top pods by CPU/memory
kubectl top pods -n uneeq-renderer

# Detailed node metrics
kubectl describe nodes -l workload-type=gpu
```

Solutions:
- **Increase resource requests**: Edit `renny-values-aks.yaml`
- **Reduce pod density**: Deploy 2-3 pods per node instead of 4
- **Add more nodes**: Scale up node pool

### GPU Sharing Issues

Even with `replicasPerGpu: 1`, verify no GPU sharing:

```bash
# Check GPU allocation per pod
kubectl describe pods -n uneeq-renderer -l app=renny | grep -A 2 "nvidia.com/gpu"

# Verify NVIDIA time-slicing config
kubectl get configmap -n gpu-operator
```

Expected: Each pod should have dedicated GPU access.

## Testing the Deployment

### 1. Test Individual Pods

Execute health check on each pod:

```bash
kubectl exec -n uneeq-renderer renny-0 -- curl -s http://localhost:8081/health
```

Expected response:
```json
{"status": "healthy"}
```

### 2. Test GPU Access

Verify NVIDIA GPU is accessible:

```bash
kubectl exec -n uneeq-renderer renny-0 -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv
```

Expected output:
```
name, driver_version, memory.total [MiB]
Tesla T4, 535.183.01, 16384 MiB
```

### 3. Test Network Connectivity

Check service endpoints:

```bash
kubectl get svc -n uneeq-renderer
kubectl get endpoints -n uneeq-renderer
```

Test service access:

```bash
kubectl run test-pod --rm -it --image=nicolaka/netshoot --restart=Never -- \
  curl http://renny-service.uneeq-renderer.svc.cluster.local:8081/health
```

### 4. Load Testing

Deploy test workload:

```bash
kubectl run load-test --rm -it --image=williamyeh/hey --restart=Never -- \
  /hey -z 60s -c 10 http://renny-service.uneeq-renderer.svc.cluster.local:8081/health
```

Monitor during load test:

```bash
kubectl top pods -n uneeq-renderer --watch
```

## Monitoring and Metrics

### Pod Metrics

View real-time metrics:

```bash
# CPU/Memory usage
kubectl top pods -n uneeq-renderer

# GPU utilization (if GPU metrics enabled)
kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/uneeq-renderer/pods | jq .
```

### Node Metrics

Check node health:

```bash
# Node resource usage
kubectl top nodes -l workload-type=gpu

# Detailed node information
kubectl describe nodes -l workload-type=gpu
```

### Azure Monitor Integration

If Azure Monitor is enabled:

```bash
# View Container Insights
az aks show -g <resource-group> -n <cluster-name> --query "addonProfiles.omsagent"

# Query logs with KQL
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "ContainerLog | where Namespace == 'uneeq-renderer' | top 100 by TimeGenerated"
```

## Cleanup

### Remove Renny Deployment

```bash
helm uninstall renny --namespace uneeq-renderer
```

### Delete Namespace

```bash
kubectl delete namespace uneeq-renderer
```

### Verify Cleanup

```bash
kubectl get pods -n uneeq-renderer
kubectl get pvc -n uneeq-renderer
kubectl get svc -n uneeq-renderer
```

## Best Practices

1. **Always use both value files**: Base + AKS override
   ```bash
   helm install -f renny-values.yaml -f renny-values-aks.yaml
   ```

2. **Test changes in staging**: Use separate namespace for testing
   ```bash
   helm install renny-test -f renny-values.yaml -f renny-values-aks.yaml --namespace uneeq-renderer-test
   ```

3. **Monitor resource usage**: Adjust requests/limits based on actual usage
   ```bash
   kubectl top pods -n uneeq-renderer --watch
   ```

4. **Enable pod disruption budget**: Ensures availability during updates
   ```yaml
   podDisruptionBudget:
     enabled: true
     minAvailable: 35
   ```

5. **Use Azure Monitor**: Enable monitoring for production clusters
   ```yaml
   monitoring:
     enabled: true
   ```

## References

- [AKS GPU Node Pools](https://learn.microsoft.com/en-us/azure/aks/gpu-cluster)
- [NVIDIA GPU Operator on AKS](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/microsoft-aks.html)
- [Helm Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
