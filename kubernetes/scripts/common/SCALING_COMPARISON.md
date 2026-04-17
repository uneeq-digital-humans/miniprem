# Multi-Cloud Scaling Scripts Comparison

## Overview

MiniPrem now supports comprehensive node pool scaling for both AWS EKS and Azure AKS clusters with full feature parity. Both scripts provide identical user experiences and capabilities tailored to their respective cloud platforms.

## Script Locations

- **AWS EKS**: `/kubernetes/scripts/scale-aws.sh` (222 lines)
- **Azure AKS**: `/kubernetes/scripts/scale-azure.sh` (575 lines)

## Feature Parity Matrix

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Core Functionality** | | | |
| Node count scaling | ✅ | ✅ | Primary scaling operation |
| Pre-flight validation | ✅ | ✅ | CLI tools, auth, cluster existence |
| Current state display | ✅ | ✅ | Shows existing node count |
| Scaling bounds validation | ✅ | ✅ | Min/max from terraform.tfvars |
| Interactive confirmation | ✅ | ✅ | User approval before scaling |
| Progress monitoring | ✅ | ✅ | Real-time scaling status |
| Post-scale verification | ✅ | ✅ | Validates final state |
| | | | |
| **Cloud-Specific Operations** | | | |
| Node group/pool scaling | `update-nodegroup-config` | `nodepool scale` | Different CLI commands |
| Autoscaler detection | ❌ | ✅ | Azure warns if autoscaler enabled |
| Time-slicing awareness | ✅ | ✅ | Scales pods accordingly |
| | | | |
| **Cost Management** | | | |
| Cost per node display | ✅ | ✅ | $1.20/hr (g5.4xlarge) vs $1.50/hr (NC16as_T4_v3) |
| Hourly cost calculation | ✅ | ✅ | Real-time cost impact |
| Monthly cost projection | ✅ | ✅ | 730 hours/month estimate |
| Cost change comparison | ✅ | ✅ | Shows increase/decrease |
| | | | |
| **Configuration Management** | | | |
| Reads terraform.tfvars | ✅ | ✅ | Single source of truth |
| Loads deployment ID | ✅ | ✅ | Multi-deployment support |
| Validates node pool name | ✅ | ✅ | Prevents typos |
| Region awareness | ✅ | ✅ | Uses configured region |
| | | | |
| **Monitoring & Validation** | | | |
| Kubectl node verification | ✅ | ✅ | Confirms node availability |
| Pod status display | ✅ | ✅ | Shows application health |
| Progress bar/indicator | ✅ | ✅ | Visual feedback |
| Timeout handling | ✅ | ✅ | 15-minute max wait |
| | | | |
| **User Experience** | | | |
| Color-coded output | ✅ | ✅ | Green/red/yellow/cyan |
| Help documentation | ✅ | ✅ | `--help` flag |
| Debug mode | ❌ | ✅ | Azure has `--debug` flag |
| Error messages | ✅ | ✅ | Clear troubleshooting |
| Usage examples | ✅ | ✅ | In help text |
| | | | |
| **Deployment Integration** | | | |
| Scales Renny pods | ✅ | ✅ | Matches node count |
| GPU time-slicing support | ✅ | ✅ | Reads renny-values.yaml |
| Namespace awareness | ✅ | ✅ | Uses uneeq-renderer |
| Label-based node selection | ✅ | ✅ | `uneeq.io/node-type=renny` |

## Usage Comparison

### AWS EKS Scaling

```bash
cd kubernetes/
./scripts/scale-aws.sh 15                    # Scale to 15 nodes
./scripts/scale-aws.sh --profile prod 12     # With AWS profile
./scripts/scale-aws.sh --help                # Show help
```

**Configuration Source**: `kubernetes/terraform/eks/terraform.tfvars`

**Node Group Name Pattern**: `{cluster-name}-renny-gpu-v4`

**Scaling Command**:
```bash
aws eks update-nodegroup-config \
    --cluster-name <cluster> \
    --nodegroup-name <nodegroup> \
    --scaling-config minSize=X,maxSize=Y,desiredSize=Z \
    --region <region>
```

### Azure AKS Scaling

```bash
cd kubernetes/
./scripts/scale-azure.sh 15              # Scale to 15 nodes
./scripts/scale-azure.sh --debug 12      # With debug output
./scripts/scale-azure.sh --help          # Show help
```

**Configuration Source**: `kubernetes/terraform/aks/terraform.tfvars`

**Node Pool Name**: `rennygpu`

**Scaling Command**:
```bash
az aks nodepool scale \
    --name <pool> \
    --node-count <N> \
    --resource-group <rg> \
    --cluster-name <cluster> \
    --no-wait
```

## Key Differences

### 1. Debug Mode

- **AWS**: No dedicated debug mode (uses standard output)
- **Azure**: `--debug` flag for verbose logging and troubleshooting

### 2. Autoscaler Detection

- **AWS**: Autoscaler managed separately, no in-script detection
- **Azure**: Detects if autoscaler is enabled and warns user

### 3. Authentication

- **AWS**: AWS profile support via `--profile` flag
- **Azure**: Uses active Azure CLI authentication (no profile flag)

### 4. Node Pool Naming

- **AWS**: Dynamic naming based on cluster name: `{cluster}-renny-gpu-v4`
- **Azure**: Fixed naming: `rennygpu`

### 5. Progress Monitoring

- **AWS**: Basic status display with kubectl commands
- **Azure**: Real-time progress with provisioning state monitoring

### 6. Cost Calculations

- **AWS**: g5.4xlarge @ $1.20/hour (NVIDIA A10G)
- **Azure**: Standard_NC16as_T4_v3 @ $1.50/hour (NVIDIA T4)

## Cost Examples

### Scaling to 10 Nodes

**AWS (g5.4xlarge)**:
- Hourly: $12.00
- Daily: $288.00
- Monthly: $8,760.00

**Azure (Standard_NC16as_T4_v3)**:
- Hourly: $15.00
- Daily: $360.00
- Monthly: $10,950.00

### Scaling to 20 Nodes

**AWS (g5.4xlarge)**:
- Hourly: $24.00
- Daily: $576.00
- Monthly: $17,520.00

**Azure (Standard_NC16as_T4_v3)**:
- Hourly: $30.00
- Daily: $720.00
- Monthly: $21,900.00

## Error Handling

Both scripts provide comprehensive error handling for:

- ✅ Missing CLI tools (aws/az, kubectl)
- ✅ Authentication failures
- ✅ Cluster not found
- ✅ Node pool/group not found
- ✅ Invalid scaling bounds (min/max)
- ✅ Invalid input (non-numeric)
- ✅ Terraform configuration issues
- ✅ Timeout during scaling operation

## Post-Scaling Verification

Both scripts verify:

1. **Node Pool State**: Checks cloud provider API
2. **Kubernetes Nodes**: Counts ready nodes via kubectl
3. **Pod Deployment**: Shows Renny pod status
4. **Cost Impact**: Displays final cost comparison

## Integration with Deployment

Both scripts integrate with their respective deployment workflows:

- Read configuration from `terraform.tfvars`
- Support deployment IDs for multi-deployment scenarios
- Scale Renny pods to match node count (with time-slicing)
- Use consistent label selectors (`uneeq.io/node-type=renny`)

## Future Enhancements

Potential improvements for both scripts:

- [ ] GCP GKE scaling script (complete the multi-cloud trio)
- [ ] Automatic cost threshold warnings
- [ ] Node pool health checks before scaling
- [ ] Slack/webhook notifications on scale completion
- [ ] Rollback capability on failure
- [ ] Dry-run mode (show changes without executing)
- [ ] JSON output mode for CI/CD integration

## Testing Recommendations

### Before Production Use

1. **Test in Development**: Scale between 2-4 nodes
2. **Verify Cost Calculation**: Compare with cloud provider billing
3. **Test Failure Scenarios**: Invalid counts, missing credentials
4. **Monitor Application**: Ensure pods reschedule correctly
5. **Check Time-Slicing**: Verify GPU sharing works after scale

### Monitoring After Scaling

```bash
# Watch nodes become ready
kubectl get nodes -l uneeq.io/node-type=renny -w

# Watch pods reschedule
kubectl get pods -n uneeq-renderer -l app=renny -w

# Check GPU availability
kubectl get nodes -L nvidia.com/gpu

# View application logs
kubectl logs -n uneeq-renderer -l app=renny --tail=50 -f
```

## Conclusion

Both AWS and Azure scaling scripts provide production-ready, feature-complete scaling capabilities with:

- **Identical user experience** across clouds
- **Comprehensive error handling** and validation
- **Real-time progress monitoring**
- **Cost impact visibility**
- **GPU time-slicing awareness**
- **Integration with deployment workflows**

The Azure implementation adds enhanced debug mode and autoscaler detection, while maintaining full feature parity with the AWS implementation.
