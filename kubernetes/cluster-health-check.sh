#!/bin/bash
# Cluster Health Check Script
# Usage: ./cluster-health-check.sh

set -e
# Use existing AWS_PROFILE or default AWS credentials

echo "🔍 KUBERNETES CLUSTER HEALTH CHECK"
echo "=================================="
echo

# 1. Node Status Overview
echo "📊 NODE OVERVIEW:"
echo "Desired State: 2 control + 2 renny + 2 a2f = 6 nodes total"
kubectl get nodes -L uneeq.io/node-type,eks.amazonaws.com/sourceLaunchTemplateVersion --no-headers | \
awk '{print $6 ": " $1 " (v" $7 ")"} END {print "Total: " NR " nodes"}'
echo

# 2. ASG vs Actual Instance Count
echo "🏗️  AUTO SCALING GROUP STATUS:"
aws autoscaling describe-auto-scaling-groups \
    --query "AutoScalingGroups[?contains(AutoScalingGroupName, 'renny-production')].{Type:AutoScalingGroupName,Desired:DesiredCapacity,Actual:length(Instances)}" \
    --output table | grep -E "Type|a2f|renny|control"
echo

# 3. GPU Driver Status
echo "🎮 GPU DRIVER STATUS:"
echo "Expected: 4 running driver pods (2 renny + 2 a2f)"
kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --no-headers | \
awk '{running += ($2 == "1/1" && $3 == "Running"); total++} END {print "Running: " running "/" total}'

if kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --no-headers | grep -E "(Init|Pending|Error|CrashLoop)" > /dev/null; then
    echo "⚠️  Issues detected:"
    kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --no-headers | grep -E "(Init|Pending|Error|CrashLoop)" | awk '{print "  " $1 ": " $3}'
fi
echo

# 4. Application Pod Status  
echo "🚀 APPLICATION PODS:"
kubectl get pods -n uneeq-renderer --no-headers | \
awk '{running += ($2 ~ /1\/1/ && $3 == "Running"); total++} END {print "Running: " running "/" total " pods"}'

kubectl get pods -n uneeq-renderer --no-headers | grep -v Running | while read line; do
    echo "  Issue: $line"
done
echo

# 5. Launch Template Version Check
echo "🔧 LAUNCH TEMPLATE VERSIONS:"
echo "Expected: control=v1, renny=v4, a2f=v4"
kubectl get nodes --no-headers -L uneeq.io/node-type,eks.amazonaws.com/sourceLaunchTemplateVersion | \
awk '{
    if ($6 != "" && $7 != "") {
        key = $6 ":" $7
        versions[key]++
        types[$6] = 1
    }
} END {
    for (type in types) {
        printf "%s: ", type
        for (key in versions) {
            split(key, parts, ":")
            if (parts[1] == type) {
                printf "v%s(%d) ", parts[2], versions[key]
            }
        }
        printf "\n"
    }
}'
echo

# 6. GPU Hardware Verification
echo "🔧 GPU HARDWARE VERIFICATION:"
echo "Expected: Renny nodes should have 2 GPUs (time-sliced), A2F nodes should have 2 GPUs"
kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."uneeq.io/node-type" | . == "renny" or . == "a2f") | "\(.metadata.name): \(.status.allocatable."nvidia.com/gpu" // "0") GPU(s)"' | while read line; do
    echo "  $line"
done

# 6b. Time-Slicing Configuration Verification
echo
echo "⚡ TIME-SLICING CONFIGURATION:"
if kubectl get configmap renny-time-slicing-config -n gpu-operator >/dev/null 2>&1; then
    echo "✓ GPU time-slicing ConfigMap exists"
    
    # Check if ClusterPolicy is using the time-slicing config
    config_name=$(kubectl get clusterpolicy cluster-policy -o jsonpath='{.spec.devicePlugin.config.name}' 2>/dev/null || echo "")
    if [ "$config_name" = "renny-time-slicing-config" ]; then
        echo "✓ ClusterPolicy configured for time-slicing"
        
        # Verify actual vs expected GPU capacity
        renny_total_gpus=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."uneeq.io/node-type" == "renny") | .status.allocatable."nvidia.com/gpu" // "0"' | awk '{sum += $1} END {print sum+0}')
        renny_nodes=$(kubectl get nodes -l uneeq.io/node-type=renny --no-headers | wc -l)
        expected_gpus=$((renny_nodes * 2))
        
        if [ "$renny_total_gpus" -eq "$expected_gpus" ]; then
            echo "✓ Time-slicing working: $renny_nodes Renny nodes × 2 = $renny_total_gpus virtual GPUs"
        else
            echo "⚠️  Time-slicing issue: Expected $expected_gpus GPUs, got $renny_total_gpus"
        fi
    else
        echo "⚠️  ClusterPolicy not configured for time-slicing (config: ${config_name:-none})"
    fi
else
    echo "⚠️  GPU time-slicing ConfigMap not found"
fi

# Test GPU functionality via existing application pods
echo
echo "🎮 GPU FUNCTIONALITY TEST:"
renderer_pod=$(kubectl get pods -n uneeq-renderer -l app=renderer --no-headers -o custom-columns=":metadata.name" | head -1)
a2f_pod=$(kubectl get pods -n uneeq-renderer -l app=a2f --no-headers -o custom-columns=":metadata.name" | head -1)

if [ -n "$renderer_pod" ]; then
    echo "Testing GPU on Renny node via $renderer_pod:"
    gpu_info=$(kubectl exec $renderer_pod -n uneeq-renderer -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "GPU test failed")
    echo "  $gpu_info"
else
    echo "  No Renny pods available for GPU testing"
fi

if [ -n "$a2f_pod" ]; then
    echo "Testing GPU on A2F node via $a2f_pod:"
    gpu_info=$(kubectl exec $a2f_pod -n uneeq-renderer -- nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader,nounits 2>/dev/null || echo "GPU test failed")
    echo "  $gpu_info"
else
    echo "  No A2F pods available for GPU testing"
fi
echo

# 7. Quick Health Summary
echo "✅ HEALTH SUMMARY:"
total_nodes=$(kubectl get nodes --no-headers | wc -l)
ready_nodes=$(kubectl get nodes --no-headers | grep -c Ready)
gpu_ready=$(kubectl get pods -n gpu-operator -l app=nvidia-driver-daemonset --no-headers | grep -c "1/1.*Running" || echo 0)
app_ready=$(kubectl get pods -n uneeq-renderer --no-headers | grep -c "Running" || echo 0)

echo "Nodes: $ready_nodes/$total_nodes ready"
echo "GPU Drivers: $gpu_ready/4 running"  
echo "Applications: $app_ready pods running"

if [ $ready_nodes -eq 6 ] && [ $gpu_ready -eq 4 ] && [ $app_ready -gt 2 ]; then
    echo "🎉 Cluster Status: HEALTHY"
else
    echo "⚠️  Cluster Status: NEEDS ATTENTION"
fi