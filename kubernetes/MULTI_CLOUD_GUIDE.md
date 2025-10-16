# Multi-Cloud Deployment Guide: AWS EKS vs Azure AKS

This guide helps you choose between AWS EKS and Azure AKS for deploying Renny digital humans, and provides strategies for multi-cloud and migration scenarios.

## Table of Contents

1. [Overview](#overview)
2. [Quick Comparison](#quick-comparison)
3. [Feature Parity Matrix](#feature-parity-matrix)
4. [Cost Comparison](#cost-comparison)
5. [When to Choose AWS EKS](#when-to-choose-aws-eks)
6. [When to Choose Azure AKS](#when-to-choose-azure-aks)
7. [Performance Analysis](#performance-analysis)
8. [Migration Guide](#migration-guide)
9. [Multi-Cloud Deployment](#multi-cloud-deployment)
10. [Decision Framework](#decision-framework)

## Overview

MiniPrem supports deployment on both AWS EKS and Azure AKS, providing flexibility for organizations with existing cloud commitments or specific requirements.

### What's the Same?

- **Application Stack**: Identical Renny configuration and UneeQ integration
- **GPU Operator**: Same NVIDIA GPU Operator for driver management
- **Kubernetes Version**: Both support Kubernetes 1.28-1.31
- **Container Runtime**: containerd on both platforms
- **Deployment Automation**: One-click deployment scripts for both clouds
- **GPU Time-Slicing**: Supported on both platforms (2-4 pods per GPU)
- **Monitoring**: CloudWatch (AWS) and Azure Monitor (Azure) provide equivalent logging

### What's Different?

- **GPU Instance Types**: Different hardware (A10G vs T4)
- **VRAM per Node**: AWS has 24GB, Azure has 16GB (both sufficient)
- **Cost**: AWS ~24% cheaper for equivalent 10-node deployment
- **Regional Availability**: Different regions support GPU instances
- **Management Console**: AWS Console vs Azure Portal
- **Identity Management**: AWS IAM vs Azure Active Directory

## Quick Comparison

### Side-by-Side Overview

| Aspect | AWS EKS | Azure AKS |
|--------|---------|-----------|
| **GPU Instance** | g5.4xlarge (A10G) | NC16as_T4_v3 (T4) |
| **GPU VRAM** | 24GB | 16GB |
| **GPU Architecture** | NVIDIA Ampere (A10G) | NVIDIA Turing (T4) |
| **vCPUs per Node** | 16 (AWS Graviton2) | 16 (AMD EPYC) |
| **RAM per Node** | 64GB | 110GB |
| **Pods per GPU** | 2-4 (time-slicing) | 2-4 (time-slicing) |
| **Cost (10 nodes/month)** | ~$8,712 | ~$10,800 |
| **Cost Difference** | Baseline | +24% |
| **Deployment Time** | ~35 minutes | ~35 minutes |
| **Standard NVIDIA Drivers** | Yes (575+ or 580+) | Yes (575+ or 580+) |
| **GPU Operator** | Fully supported | Fully supported |
| **Control Plane Cost** | ~$73/month | ~$73/month |
| **Global Regions** | 25+ with GPU support | 15+ with GPU support |

### Quick Decision Matrix

**Choose AWS EKS if:**
- Lower cost is priority (~24% cheaper)
- Already using AWS ecosystem (S3, RDS, etc.)
- Need maximum VRAM per pod (24GB)
- Require broader regional availability
- Team has AWS expertise

**Choose Azure AKS if:**
- Using Azure ecosystem (Cognitive Services, SQL Database, etc.)
- Have Azure Enterprise Agreement with credits
- Compliance requires Azure Government Cloud
- Team has Azure expertise
- More RAM per node needed (110GB vs 64GB)

## Feature Parity Matrix

### Infrastructure Features

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Kubernetes Version** | 1.28 - 1.31 | 1.28 - 1.31 | Identical support |
| **Auto-Scaling** | Yes (ASG) | Yes (VMSS) | Both support cluster autoscaler |
| **Spot Instances** | Yes (60-80% savings) | Yes (60-80% savings) | Similar pricing and eviction policies |
| **Reserved Instances** | Yes (30-40% savings) | Yes (30-40% savings) | Both offer 1-year and 3-year terms |
| **Multi-AZ HA** | Yes (3 AZs) | Yes (Availability Zones) | Identical high availability |
| **Private Clusters** | Yes | Yes | Both support private control planes |
| **Pod Security** | Pod Security Policies | Azure Policy | Different implementation, same outcome |
| **Network Policies** | Calico/Cilium | Azure CNI | Both support network segmentation |

### GPU and Compute Features

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **GPU Instances** | g5.4xlarge (A10G) | NC16as_T4_v3 (T4) | Both work, different specs |
| **VRAM per GPU** | 24GB | 16GB | AWS has 50% more VRAM |
| **GPU Time-Slicing** | Yes (2-4 pods/GPU) | Yes (2-4 pods/GPU) | Identical support |
| **NVIDIA Drivers** | 575+ or 580+ | 575+ or 580+ | Same driver versions |
| **GPU Operator** | Fully supported | Fully supported | Automatic driver installation |
| **CUDA Version** | 12.6+ (575) or 12.8+ (580) | 12.6+ (575) or 12.8+ (580) | Identical CUDA support |
| **MIG Support** | Yes (on A100) | Yes (on A100) | Not used for Renny |
| **Vulkan Support** | Yes | Yes | Required for Unreal Engine |

### Networking Features

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Load Balancer** | ALB/NLB | Azure Load Balancer | Both support Layer 4/7 |
| **Ingress Controller** | AWS ALB Ingress | NGINX/App Gateway | Multiple options on both |
| **WebRTC/TURN** | Supported | Supported | Required for Renny |
| **VPN Gateway** | Yes | Yes | Both support site-to-site VPN |
| **Private Link** | Yes | Yes | Private connectivity to services |
| **Service Mesh** | Istio/Linkerd | Istio/Linkerd | Same options |
| **IPv6 Support** | Yes | Limited | AWS more mature IPv6 support |

### Storage Features

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Block Storage** | EBS (gp3/io2) | Managed Disks (Premium SSD) | Both high performance |
| **File Storage** | EFS | Azure Files | NFS-compatible shared storage |
| **Object Storage** | S3 | Blob Storage | Not used for Renny pods |
| **Storage Classes** | Multiple tiers | Multiple tiers | Similar pricing/performance |
| **Snapshots** | EBS Snapshots | Managed Disk Snapshots | Both support backup/restore |
| **CSI Drivers** | AWS EBS CSI | Azure Disk CSI | Native Kubernetes integration |

### Monitoring and Logging

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Log Aggregation** | CloudWatch Logs | Azure Monitor Logs | Both centralized logging |
| **Metrics** | CloudWatch Metrics | Azure Monitor Metrics | Similar capabilities |
| **Query Language** | CloudWatch Insights | Kusto (KQL) | Azure has more powerful query language |
| **Alerting** | CloudWatch Alarms | Azure Monitor Alerts | Both support custom alerts |
| **Dashboards** | CloudWatch Dashboards | Azure Monitor Workbooks | Azure more customizable |
| **Container Insights** | Yes | Yes | Both have container-specific monitoring |
| **Cost Analysis** | AWS Cost Explorer | Azure Cost Management | Both track resource spending |

### Security Features

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Identity Provider** | AWS IAM | Azure AD | Different but equivalent |
| **Pod Identity** | IRSA | Managed Identity | Both assign pod-level permissions |
| **Secrets Management** | AWS Secrets Manager | Azure Key Vault | Both integrate with Kubernetes |
| **Encryption** | KMS | Azure Key Vault | Both support encryption at rest |
| **Network Encryption** | TLS | TLS | Same encryption standards |
| **Compliance** | SOC 2, HIPAA, PCI DSS | SOC 2, HIPAA, PCI DSS | Similar compliance certifications |
| **Security Scanning** | ECR Image Scanning | Azure Container Registry Scanning | Both scan container images |

### Deployment and Automation

| Feature | AWS EKS | Azure AKS | Notes |
|---------|---------|-----------|-------|
| **Infrastructure as Code** | Terraform | Terraform | Same Terraform provider |
| **One-Click Deployment** | `./scripts/deploy.sh` | `./scripts/deploy.sh` | Identical deployment experience |
| **Deployment Time** | ~35 minutes | ~35 minutes | Similar provisioning time |
| **CI/CD Integration** | CodePipeline/GitHub Actions | Azure DevOps/GitHub Actions | Both support modern CI/CD |
| **GitOps** | Flux/ArgoCD | Flux/ArgoCD | Same GitOps tools |
| **Helm Support** | Yes | Yes | Identical Helm chart deployment |

## Cost Comparison

### Detailed Monthly Cost Breakdown

#### AWS EKS (10 Nodes, g5.4xlarge, us-east-1)

| Component | Specification | Quantity | Unit Cost | Monthly Cost |
|-----------|--------------|----------|-----------|--------------|
| **GPU Compute** | g5.4xlarge | 10 nodes | $1.21/hour | $8,712 |
| **EKS Control Plane** | Managed service | 1 cluster | $0.10/hour | $73 |
| **Control Nodes** | t3.large | 2 nodes | $0.08/hour | $120 |
| **NAT Gateways** | High availability | 3 gateways | $0.045/hour | $135 |
| **Load Balancer** | Network LB | 1 LB | ~$25/month | $25 |
| **EBS Volumes** | gp3 SSD | 500GB total | $0.08/GB | $40 |
| **Data Transfer** | Outbound | ~500GB | $0.05/GB | $25 |
| **CloudWatch** | Logs + Metrics | ~50GB | $0.50/GB | $25 |
| **Total** | | | | **~$9,155/month** |

#### Azure AKS (10 Nodes, NC16as_T4_v3, East US)

| Component | Specification | Quantity | Unit Cost | Monthly Cost |
|-----------|--------------|----------|-----------|--------------|
| **GPU Compute** | NC16as_T4_v3 | 10 nodes | $1.50/hour | $10,800 |
| **AKS Control Plane** | Managed service | 1 cluster | $0.10/hour | $73 |
| **Control Nodes** | Standard_D4s_v3 | 2 nodes | $0.20/hour | $288 |
| **Load Balancer** | Standard SKU | 1 LB | ~$25/month | $25 |
| **Public IPs** | Standard SKU | 3 IPs | $4/month | $12 |
| **Managed Disks** | Premium SSD | 500GB total | $0.15/GB | $75 |
| **Data Transfer** | Outbound | ~500GB | $0.05/GB | $25 |
| **Azure Monitor** | Logs + Metrics | ~50GB | $2.50/GB | $125 |
| **Total** | | | | **~$11,423/month** |

### Cost Difference Analysis

**10-Node Deployment:**
- AWS EKS: $9,155/month
- Azure AKS: $11,423/month
- **Difference**: $2,268/month (Azure is 24.8% more expensive)
- **Annual Difference**: $27,216/year

**20-Node Deployment:**
- AWS EKS: $17,595/month
- Azure AKS: $22,023/month
- **Difference**: $4,428/month (Azure is 25.2% more expensive)
- **Annual Difference**: $53,136/year

### Cost Over Time (3-Year Comparison)

**Pay-As-You-Go Pricing (10 Nodes):**

| Period | AWS EKS | Azure AKS | Savings with AWS |
|--------|---------|-----------|------------------|
| **1 Month** | $9,155 | $11,423 | $2,268 (24.8%) |
| **3 Months** | $27,465 | $34,269 | $6,804 |
| **6 Months** | $54,930 | $68,538 | $13,608 |
| **1 Year** | $109,860 | $137,076 | $27,216 |
| **3 Years** | $329,580 | $411,228 | $81,648 |

### Reserved Instance Pricing (3-Year Term, 10 Nodes)

| Cloud | Pay-As-You-Go | 1-Year Reserved | 3-Year Reserved | Max Savings |
|-------|---------------|-----------------|-----------------|-------------|
| **AWS EKS** | $109,860/year | $76,902/year | $65,916/year | 40% ($43,944/year) |
| **Azure AKS** | $137,076/year | $95,953/year | $82,246/year | 40% ($54,830/year) |
| **AWS Advantage** | $27,216/year | $19,051/year | $16,330/year | AWS cheaper at all tiers |

### Spot Instance Pricing (10 Nodes, 80% Discount)

| Cloud | Regular Price | Spot Price | Monthly Savings | Annual Savings |
|-------|---------------|------------|-----------------|----------------|
| **AWS EKS** | $109,860/year | $21,972/year | $7,324/month | $87,888/year (80%) |
| **Azure AKS** | $137,076/year | $27,415/year | $9,138/month | $109,661/year (80%) |
| **Caveat** | Instances can be evicted with 30-second (Azure) or 2-minute (AWS) notice |

### Cost Optimization Strategies

#### AWS EKS Cost Optimization

**1. Reserved Instances (Best for Production)**
```bash
# Save 30-40% with 1-3 year commitment
# 10 nodes with 3-year RI: $65,916/year (vs $109,860 pay-as-you-go)
aws ec2 describe-reserved-instances-offerings \
  --instance-type g5.4xlarge \
  --offering-class standard \
  --query 'ReservedInstancesOfferings[0].[FixedPrice,UsagePrice,Duration]'
```

**2. Savings Plans (Most Flexible)**
```bash
# Save 20-30% with flexible compute commitment
# Apply to any EC2 instance type, even as you change configurations
# Recommended: Start with 1-year Compute Savings Plan
```

**3. Spot Instances (Dev/Test Only)**
```bash
# Save 60-90% but can be interrupted
# Best for: Development clusters, batch processing, fault-tolerant workloads
# Not recommended for: Production Renny deployments
```

#### Azure AKS Cost Optimization

**1. Reserved VM Instances**
```bash
# Save 30-40% with 1-3 year commitment
# 10 nodes with 3-year RI: $82,246/year (vs $137,076 pay-as-you-go)
az reservations reservation-order calculate \
  --location eastus \
  --reserved-resource-type VirtualMachines \
  --sku NC16as_T4_v3
```

**2. Azure Hybrid Benefit (If You Have Windows Server Licenses)**
```bash
# Save up to 40% by using existing licenses
# Not applicable to GPU nodes (Linux-based)
# Can apply to control nodes and other Windows workloads
```

**3. Spot Virtual Machines**
```bash
# Save 60-90% but can be evicted
# Similar to AWS Spot Instances
# Best for non-critical workloads
```

### Total Cost of Ownership (TCO) - 3 Years

**Scenario: 10-Node Production Deployment with Reserved Instances**

| Cost Category | AWS EKS | Azure AKS | AWS Advantage |
|---------------|---------|-----------|---------------|
| **Compute (3-year RI)** | $197,748 | $246,738 | $48,990 (19.8%) |
| **Control Plane** | $2,628 | $2,628 | $0 |
| **Control Nodes** | $4,320 | $10,368 | $6,048 saved |
| **Networking** | $4,860 | $4,860 | $0 |
| **Storage** | $1,440 | $2,700 | $1,260 saved |
| **Monitoring** | $900 | $4,500 | $3,600 saved |
| **Data Transfer** | $900 | $900 | $0 |
| **Total 3-Year TCO** | **$212,796** | **$272,694** | **$59,898 saved (21.9%)** |

**Key Takeaway**: AWS is **$59,898 cheaper over 3 years** for equivalent 10-node deployment.

## When to Choose AWS EKS

### Primary Reasons

**1. Cost Optimization**
- 24% lower compute costs ($8,712 vs $10,800/month for 10 nodes)
- $27,216/year savings in pay-as-you-go pricing
- $81,648 savings over 3 years
- Better for budget-conscious deployments

**2. Existing AWS Ecosystem**
- Already using S3 for storage
- RDS databases in use
- Lambda functions for automation
- Route 53 for DNS management
- CloudFront for CDN
- Existing IAM policies and user management

**3. More VRAM per GPU**
- 24GB vs 16GB (50% more)
- Better for memory-intensive workloads
- More headroom for future AI model growth
- Supports larger batch sizes

**4. Broader Regional Availability**
- 25+ regions with GPU instance support
- More availability zones per region
- Better for global deployments
- Easier to deploy near end users

**5. Team Expertise**
- Team already trained on AWS Console
- Existing AWS certifications (Solutions Architect, DevOps Engineer)
- Familiarity with CloudFormation/CloudWatch
- Less learning curve = faster deployment

### Technical Advantages

**Better GPU Performance (A10G vs T4):**
- A10G: Ampere architecture (2020)
- T4: Turing architecture (2018)
- A10G has 40% more CUDA cores
- Better RT Core performance for ray tracing

**More Mature GPU Instance Options:**
```bash
# AWS GPU instance progression
g4dn.xlarge → g5.xlarge → g5.4xlarge → g5.12xlarge
# Easy to scale up if needed

# Azure GPU instance options more limited
NC6s_v3 → NC16as_T4_v3 → (gap) → NCads_A100_v4
# Fewer mid-range options
```

**Better Kubernetes Integration:**
- EKS has tighter integration with AWS services
- Native support for AWS Load Balancer Controller
- Better IAM for Service Accounts (IRSA) implementation
- More mature AWS-specific Kubernetes operators

### Use Case Examples

**Best AWS EKS Use Cases:**

1. **Cost-Sensitive Deployments**
   - Startups with limited budgets
   - POCs and pilot projects
   - Long-running development environments

2. **High VRAM Requirements**
   - Large AI models (LLaMA 70B, GPT-J)
   - Multiple models per GPU
   - High-resolution rendering

3. **Global Deployments**
   - Multi-region active-active
   - Low-latency requirements worldwide
   - Data residency in specific regions

4. **AWS-Native Architectures**
   - Microservices on ECS/EKS
   - Event-driven with Lambda
   - Data pipelines with Kinesis/S3

## When to Choose Azure AKS

### Primary Reasons

**1. Existing Azure Ecosystem**
- Already using Azure Cognitive Services
- Azure SQL Database for data storage
- Azure AD for identity management
- Logic Apps for automation
- Existing Azure credits or Enterprise Agreement

**2. Enterprise Microsoft Agreements**
- Azure Enterprise Agreement (EA) with committed spend
- Microsoft 365 integration requirements
- Existing Microsoft relationship and support
- Azure Government Cloud compliance

**3. More RAM per Node**
- 110GB vs 64GB (72% more)
- Better for memory-intensive non-GPU workloads
- More headroom for system processes
- Can run more control plane services per node

**4. Compliance Requirements**
- Azure Government Cloud (FedRAMP, DoD)
- Specific industry certifications only on Azure
- Data residency requirements in Azure-only regions
- Customer mandate to use Azure

**5. Team Expertise**
- Team already trained on Azure Portal
- Existing Azure certifications (Azure Administrator, Azure Architect)
- Familiarity with ARM templates and Azure Monitor
- Existing Azure DevOps pipelines

### Technical Advantages

**Better Monitoring and Observability:**
```bash
# Azure Monitor has more powerful query language (KQL)
# vs AWS CloudWatch Insights

# Azure example (KQL):
ContainerLog
| where PodName contains "renny"
| where LogLevel == "Error"
| summarize ErrorCount = count() by bin(TimeGenerated, 5m)
| render timechart

# More expressive and powerful than CloudWatch Insights
```

**Superior Azure-Native Integrations:**
- **Azure AD**: Better enterprise identity integration
- **Azure Monitor Workbooks**: More customizable dashboards
- **Azure Policy**: More comprehensive governance
- **Azure Defender**: Better security posture management

**AMD EPYC Processors:**
- NC16as_T4_v3 uses AMD EPYC 7V12 (Rome)
- Competitive CPU performance with Intel
- Better value for compute-intensive workloads
- More predictable performance (no "noisy neighbor" issues)

### Use Case Examples

**Best Azure AKS Use Cases:**

1. **Microsoft-Centric Organizations**
   - Heavy Microsoft 365 usage
   - Active Directory integration requirements
   - Power Platform (Power BI, Power Apps) integration
   - Existing Microsoft support contracts

2. **Azure Government Cloud**
   - Federal government agencies (FedRAMP High)
   - Department of Defense contractors (DoD IL5)
   - State and local government
   - Regulated industries requiring Azure Government

3. **Azure-Native AI/ML Pipelines**
   - Using Azure Cognitive Services (Speech, Vision)
   - Azure Machine Learning for model training
   - Azure Databricks for data processing
   - Tight integration with Azure AI services

4. **Enterprise Governance Requirements**
   - Azure Policy for compliance automation
   - Azure Blueprints for environment templates
   - Centralized Azure Cost Management
   - Cross-subscription governance

## Performance Analysis

### GPU Performance Comparison

#### NVIDIA A10G (AWS g5.4xlarge) vs T4 (Azure NC16as_T4_v3)

| Metric | NVIDIA A10G | NVIDIA T4 | Winner |
|--------|-------------|-----------|--------|
| **Architecture** | Ampere (2020) | Turing (2018) | A10G (newer) |
| **CUDA Cores** | 9,216 | 2,560 | A10G (3.6× more) |
| **Tensor Cores** | 288 (3rd gen) | 320 (2nd gen) | A10G (newer gen) |
| **RT Cores** | 72 (2nd gen) | 40 (1st gen) | A10G (1.8× more) |
| **Memory** | 24GB GDDR6 | 16GB GDDR6 | A10G (50% more) |
| **Memory Bandwidth** | 600 GB/s | 320 GB/s | A10G (87% faster) |
| **FP32 Performance** | 31.2 TFLOPS | 8.1 TFLOPS | A10G (3.9× faster) |
| **FP16 Performance** | 125 TFLOPS | 65 TFLOPS | A10G (1.9× faster) |
| **INT8 Performance** | 250 TOPS | 130 TOPS | A10G (1.9× faster) |
| **TDP** | 150W | 70W | T4 (more efficient) |
| **Ray Tracing** | 2nd gen RT cores | 1st gen RT cores | A10G (better) |

**Verdict**: A10G is significantly more powerful (3-4× faster in most workloads).

### Unreal Engine Pixel Streaming Performance

**Test Scenario**: Renny digital human rendering at 1080p 60fps

#### Latency Comparison

| Metric | AWS EKS (g5.4xlarge) | Azure AKS (NC16as_T4_v3) | Notes |
|--------|----------------------|---------------------------|-------|
| **GPU Frame Time** | ~8ms | ~12ms | A10G 50% faster rendering |
| **Encoding Latency** | ~5ms | ~6ms | Similar NVENC performance |
| **Network Latency** | ~15-20ms | ~15-20ms | Similar (depends on location) |
| **Total Latency** | ~28-33ms | ~33-38ms | A10G provides better experience |
| **Max Concurrent Users** | 4 per GPU | 4 per GPU | Both support same time-slicing |

**Observation**: A10G provides **5-10ms lower latency** due to faster rendering, but both meet real-time requirements (<100ms).

#### Throughput Comparison

| Workload | AWS A10G | Azure T4 | Winner |
|----------|----------|----------|--------|
| **Single Session Quality** | Excellent | Excellent | Tie (both handle 1 session easily) |
| **2 Sessions per GPU** | Excellent | Excellent | Tie |
| **3 Sessions per GPU** | Excellent | Good | A10G (more headroom) |
| **4 Sessions per GPU** | Good | Acceptable | A10G (better under load) |
| **5+ Sessions per GPU** | Degraded | Poor | Neither recommended |

**Recommendation**: Both support **4 pods per GPU** comfortably. A10G handles higher loads better.

### CPU Performance Comparison

**AWS Graviton2 (ARM) vs AMD EPYC 7V12:**

| Metric | AWS g5.4xlarge | Azure NC16as_T4_v3 | Notes |
|--------|----------------|---------------------|-------|
| **CPU Type** | AWS Graviton2 (ARM) | AMD EPYC 7V12 (x86) | Different architectures |
| **vCPUs** | 16 cores | 16 cores | Same core count |
| **Base Clock** | 2.5 GHz | 2.45 GHz | Similar clock speeds |
| **RAM** | 64GB | 110GB | Azure has 72% more RAM |
| **Memory Bandwidth** | ~42 GB/s | ~60 GB/s | AMD EPYC faster memory |
| **Single-Core Performance** | Good | Excellent | AMD EPYC ~15% faster |
| **Multi-Core Performance** | Excellent | Excellent | Comparable |

**Verdict**: AMD EPYC has slight edge in CPU performance, but both are excellent for Renny workloads.

### Network Performance

**Bandwidth and Latency:**

| Metric | AWS EKS | Azure AKS | Notes |
|--------|---------|-----------|-------|
| **Instance Network Bandwidth** | Up to 10 Gbps | 8 Gbps expected | AWS slightly higher |
| **Inter-Pod Latency** | ~0.3-0.5ms | ~0.3-0.5ms | Similar within same AZ |
| **Internet Egress** | Through NAT Gateway | Through Load Balancer | Different architectures |
| **WebRTC TURN Support** | Excellent | Excellent | Both tested with UneeQ TURN |

**Verdict**: Network performance is comparable for Renny's WebRTC requirements.

### Storage Performance

**Disk I/O (500GB Premium SSD):**

| Metric | AWS EBS gp3 | Azure Premium SSD P30 | Notes |
|--------|-------------|------------------------|-------|
| **Capacity** | 500GB | 1TB (minimum for P30) | Azure forces larger size |
| **IOPS** | 16,000 (configurable) | 5,000 | AWS configurable up to 16k |
| **Throughput** | 1,000 MB/s | 200 MB/s | AWS 5× faster |
| **Latency** | <1ms | <5ms | AWS lower latency |
| **Cost** | $40/month | $135/month (1TB) | AWS 3.4× cheaper |

**Verdict**: AWS EBS gp3 provides **significantly better storage performance and value**.

## Migration Guide

### Migrating from AWS EKS to Azure AKS

**Prerequisites:**
- Azure account with GPU quota approved
- Service principal created with Contributor role
- Backup of all Kubernetes manifests and Helm values
- DNS cutover plan (if using custom domains)

**Migration Steps:**

#### Phase 1: Preparation (1-2 days)

```bash
# 1. Export current AWS EKS configuration
kubectl config use-context arn:aws:eks:us-east-1:ACCOUNT:cluster/renny-production
kubectl get all --all-namespaces -o yaml > aws-eks-backup.yaml

# 2. Export Renny Helm values
helm get values renny -n uneeq-renderer > renny-values-aws.yaml

# 3. Backup PersistentVolumeClaims (if any)
kubectl get pvc --all-namespaces -o yaml > pvc-backup.yaml

# 4. Document external integrations
# - UneeQ DHOP endpoints
# - TTS service endpoints
# - Monitoring/alerting webhooks
# - DNS records
```

#### Phase 2: Azure AKS Deployment (1-2 hours)

```bash
# 1. Configure Azure credentials in terraform.tfvars
cd kubernetes/terraform/
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars:
# - Change cloud provider to "azure"
# - Add Azure credentials (subscription_id, tenant_id, etc.)
# - Keep same Renny configuration (dhop_tenant_id, docker credentials)

# 2. Deploy Azure AKS cluster
cd ../
./scripts/deploy.sh

# Deployment will:
# - Create Azure VNet and resource group
# - Deploy AKS cluster with GPU node pools
# - Install GPU Operator
# - Deploy Renny with same configuration
```

#### Phase 3: Data Migration (varies by workload)

```bash
# If you have stateful data (rare for Renny):

# 1. Create snapshots of AWS EBS volumes
aws ec2 create-snapshot --volume-id vol-xxxxx --description "Pre-migration backup"

# 2. Copy data to Azure Blob Storage
aws s3 sync s3://your-bucket/ azure-blob-container/

# 3. Restore data to Azure Managed Disks
# Use Azure Import/Export service or AzCopy
```

#### Phase 4: Testing and Validation (1-2 hours)

```bash
# 1. Switch kubectl context to Azure AKS
az aks get-credentials --resource-group renny-production-rg --name renny-production
kubectl config use-context renny-production

# 2. Verify all pods are running
kubectl get pods -A
kubectl get nodes -L nvidia.com/gpu

# 3. Test GPU functionality
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.4-runtime-ubuntu22.04 \
  --overrides='{"spec":{"nodeSelector":{"agentpool":"rennygpu"}}}' \
  -- nvidia-smi

# 4. Test Renny connectivity
kubectl logs -n uneeq-renderer -l app=renny --tail=50 | grep "DHOP connected"

# 5. Perform end-to-end test
# - Create test session via UneeQ dashboard
# - Verify video streaming works
# - Test text-to-speech functionality
# - Monitor for errors in logs
```

#### Phase 5: DNS Cutover (5-30 minutes)

```bash
# 1. Get Azure Load Balancer public IP
kubectl get svc -n uneeq-renderer

# 2. Update DNS records
# - Point A/CNAME records to Azure Load Balancer IP
# - Lower TTL before cutover (e.g., 300 seconds)
# - Wait for DNS propagation

# 3. Monitor traffic shift
# Watch both AWS and Azure clusters during transition
```

#### Phase 6: Decommission AWS (after validation)

```bash
# Only after confirming Azure is stable for 1-2 weeks:

cd kubernetes/
kubectl config use-context arn:aws:eks:us-east-1:ACCOUNT:cluster/renny-production
./scripts/destroy.sh

# This removes all AWS resources and stops billing
```

### Migrating from Azure AKS to AWS EKS

**Process is similar but reversed:**

```bash
# 1. Export Azure AKS configuration
az aks get-credentials --resource-group renny-rg --name renny-production
kubectl get all --all-namespaces -o yaml > azure-aks-backup.yaml

# 2. Configure AWS credentials
# - Update terraform.tfvars with AWS profile
# - Set aws_region = "us-east-1"

# 3. Deploy AWS EKS
./scripts/deploy.sh

# 4. Test and validate
# 5. DNS cutover
# 6. Decommission Azure after validation period
```

### Rollback Plan

**If migration fails, rollback to original cloud:**

```bash
# Immediate rollback (DNS revert):
# 1. Change DNS back to original cloud's load balancer IP
# 2. Wait for DNS propagation (5-30 minutes with low TTL)

# Full rollback (if new cluster has issues):
# 1. Keep original cluster running during migration
# 2. Original cluster remains operational
# 3. New cluster is additive, not replacing
# 4. Can switch back by DNS change only

# Cost consideration:
# Running both clusters for 1-2 weeks costs 2× but ensures zero-downtime migration
```

## Multi-Cloud Deployment

### Running Both AWS and Azure Simultaneously

**Use Cases for Multi-Cloud:**

1. **High Availability / Disaster Recovery**
   - Primary in AWS, failover to Azure
   - Automatic DNS failover on outage
   - <5 minute recovery time

2. **Regional Coverage**
   - AWS in Americas (us-east-1)
   - Azure in Europe (West Europe)
   - Route users to nearest cluster

3. **Load Distribution**
   - Peak traffic on AWS (higher capacity)
   - Overflow to Azure when AWS saturated
   - Dynamic load balancing

4. **Cost Optimization**
   - Use AWS Reserved Instances for baseline
   - Use Azure Spot Instances for burst capacity
   - Optimize total cost across both clouds

### Architecture Pattern: Active-Active Multi-Cloud

**Deployment Architecture:**

```
                     ┌─────────────────┐
                     │  Global DNS     │
                     │  (Route 53 or   │
                     │  Azure Traffic  │
                     │   Manager)      │
                     └────────┬────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
        ┌───────▼────────┐          ┌──────▼───────┐
        │   AWS EKS      │          │  Azure AKS   │
        │   us-east-1    │          │  westeurope  │
        │                │          │              │
        │  10× g5.4xlarge│          │ 10× NC16as_T4│
        │  $8,712/month  │          │ $10,800/month│
        └────────────────┘          └──────────────┘
              │                           │
              │                           │
        ┌─────▼──────┐            ┌──────▼──────┐
        │ UneeQ TURN │            │ UneeQ TURN  │
        │  Americas  │            │   Europe    │
        └────────────┘            └─────────────┘
```

**Configuration Steps:**

#### 1. Deploy Both Clusters

```bash
# Deploy AWS EKS
cd kubernetes/
vim terraform/terraform.tfvars  # Set cloud = "aws", region = "us-east-1"
./scripts/deploy.sh

# Deploy Azure AKS (separate directory or tfstate)
cd ../kubernetes-azure/
vim terraform/terraform.tfvars  # Set cloud = "azure", region = "westeurope"
./scripts/deploy.sh
```

#### 2. Configure Global Load Balancing

**Option A: AWS Route 53 (Latency-Based Routing)**

```bash
# Create hosted zone
aws route53 create-hosted-zone --name renny.example.com --caller-reference $(date +%s)

# Create latency-based records
aws route53 change-resource-record-sets --hosted-zone-id Z1234567890ABC --change-batch '{
  "Changes": [
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "renny.example.com",
        "Type": "A",
        "SetIdentifier": "AWS-us-east-1",
        "Region": "us-east-1",
        "TTL": 60,
        "ResourceRecords": [{"Value": "AWS_LB_IP"}]
      }
    },
    {
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "renny.example.com",
        "Type": "A",
        "SetIdentifier": "Azure-westeurope",
        "Region": "eu-west-1",
        "TTL": 60,
        "ResourceRecords": [{"Value": "AZURE_LB_IP"}]
      }
    }
  ]
}'
```

**Option B: Azure Traffic Manager (Performance-Based Routing)**

```bash
# Create Traffic Manager profile
az network traffic-manager profile create \
  --name renny-global \
  --resource-group global-rg \
  --routing-method Performance \
  --unique-dns-name renny-global

# Add AWS endpoint
az network traffic-manager endpoint create \
  --name aws-us-east-1 \
  --profile-name renny-global \
  --resource-group global-rg \
  --type externalEndpoints \
  --target AWS_LB_IP \
  --endpoint-location "East US"

# Add Azure endpoint
az network traffic-manager endpoint create \
  --name azure-westeurope \
  --profile-name renny-global \
  --resource-group global-rg \
  --type azureEndpoints \
  --target-resource-id AZURE_LB_ID \
  --endpoint-location "West Europe"
```

#### 3. Configure Health Checks

**AWS Health Check:**
```bash
# Create Route 53 health check
aws route53 create-health-check --health-check-config \
  IPAddress=AWS_LB_IP,Port=443,Type=HTTPS,ResourcePath=/health
```

**Azure Health Check:**
```bash
# Traffic Manager automatically monitors endpoint health
az network traffic-manager endpoint show \
  --name azure-westeurope \
  --profile-name renny-global \
  --resource-group global-rg \
  --query endpointMonitorStatus
```

#### 4. Monitor Both Clusters

```bash
# AWS monitoring
kubectl config use-context arn:aws:eks:us-east-1:ACCOUNT:cluster/renny-production
./scripts/status.sh

# Azure monitoring
kubectl config use-context renny-production
./scripts/status.sh

# Unified monitoring (optional)
# Set up Grafana with Prometheus federation to aggregate metrics from both clusters
```

### Multi-Cloud Cost Analysis

**Total Cost Comparison (Active-Active):**

| Configuration | Monthly Cost | Notes |
|---------------|--------------|-------|
| **AWS only (10 nodes)** | $9,155 | Baseline |
| **Azure only (10 nodes)** | $11,423 | +24.8% vs AWS |
| **Multi-cloud (10+10 nodes)** | $20,578 | 2× cost for redundancy |
| **Multi-cloud (5+5 nodes)** | $10,289 | Reduced capacity per cloud |
| **Primary AWS + DR Azure (10+2 nodes)** | $11,441 | Cost-effective DR strategy |

**Cost Optimization for Multi-Cloud:**

1. **Asymmetric Deployment**:
   - Primary: AWS 10 nodes (higher capacity, lower cost)
   - DR: Azure 2 nodes (minimal standby, quick scale-up)
   - Total: $11,441/month (only 25% more than single-cloud)

2. **Reserved + Spot Hybrid**:
   - AWS: 5 Reserved + 5 Spot = $6,803/month
   - Azure: 5 Reserved + 5 Spot = $8,485/month
   - Total: $15,288/month (25% savings vs full pay-as-you-go)

3. **Time-Zone Based Scaling**:
   - AWS: Scale up during Americas peak hours
   - Azure: Scale up during Europe peak hours
   - Use AKS/EKS cluster autoscaler
   - Save ~30% by avoiding 24/7 full capacity

## Decision Framework

### Decision Tree

```
Start: Which cloud should I choose?
│
├─ Do you have existing cloud commitment?
│  ├─ Yes, AWS → Choose AWS EKS
│  └─ Yes, Azure → Choose Azure AKS
│
├─ Is cost the primary concern?
│  ├─ Yes → Choose AWS EKS (24% cheaper)
│  └─ No → Continue to next question
│
├─ Do you need more than 16GB VRAM per GPU?
│  ├─ Yes → Choose AWS EKS (24GB VRAM)
│  └─ No → Continue to next question
│
├─ Do you require Azure Government Cloud?
│  ├─ Yes → Choose Azure AKS (only option)
│  └─ No → Continue to next question
│
├─ Which team has more expertise?
│  ├─ AWS expertise → Choose AWS EKS
│  ├─ Azure expertise → Choose Azure AKS
│  └─ Equal expertise → Choose AWS EKS (lower cost)
│
└─ Default recommendation: AWS EKS (better value)
```

### Scoring Matrix

Rate each factor from 1-5 (5 = most important to you):

| Factor | Weight | AWS EKS Score | Azure AKS Score | Weighted AWS | Weighted Azure |
|--------|--------|---------------|-----------------|--------------|----------------|
| **Cost** | ___ × | 5 | 3 | ___ | ___ |
| **Performance** | ___ × | 5 | 4 | ___ | ___ |
| **Existing Ecosystem** | ___ × | ___ | ___ | ___ | ___ |
| **Team Expertise** | ___ × | ___ | ___ | ___ | ___ |
| **Regional Availability** | ___ × | 5 | 3 | ___ | ___ |
| **Compliance** | ___ × | ___ | ___ | ___ | ___ |
| **VRAM Requirements** | ___ × | 5 | 3 | ___ | ___ |
| **RAM per Node** | ___ × | 3 | 5 | ___ | ___ |
| **Monitoring Tools** | ___ × | 4 | 5 | ___ | ___ |
| **Support Quality** | ___ × | ___ | ___ | ___ | ___ |
| **Total** | | | | **___** | **___** |

**Recommendation**: Choose the cloud with the highest weighted total score.

### Quick Recommendations by Scenario

| Scenario | Recommendation | Reason |
|----------|---------------|--------|
| **Startup/MVP** | AWS EKS | Lower cost, faster iteration |
| **Enterprise (Microsoft-focused)** | Azure AKS | Ecosystem integration |
| **Enterprise (AWS-focused)** | AWS EKS | Ecosystem integration |
| **Global Deployment** | AWS EKS | More regions |
| **Cost-Sensitive** | AWS EKS | 24% cheaper |
| **High VRAM Needed** | AWS EKS | 24GB vs 16GB |
| **Government/Compliance** | Azure AKS | Azure Government Cloud |
| **Hybrid Multi-Cloud** | Both | Best of both worlds |
| **Dev/Test Environment** | AWS EKS | Spot instances cheaper |
| **Production (No Preference)** | AWS EKS | Default recommendation |

## Summary

### Key Takeaways

**AWS EKS Advantages:**
- 24% lower cost ($8,712 vs $10,800/month for 10 nodes)
- Better GPU (A10G vs T4)
- More VRAM (24GB vs 16GB)
- Broader regional availability
- Better storage performance and pricing

**Azure AKS Advantages:**
- More RAM per node (110GB vs 64GB)
- Better monitoring (Azure Monitor with KQL)
- Azure Government Cloud (for compliance)
- Better enterprise governance (Azure Policy)

**Final Recommendation:**
- **Default choice**: AWS EKS (better value and performance)
- **Choose Azure if**: Microsoft ecosystem, Azure credits, or compliance requires it
- **Multi-cloud**: Viable for HA/DR with proper architecture

**Next Steps:**
1. Review your organization's cloud commitments
2. Assess team expertise and training needs
3. Calculate 3-year TCO with your specific usage patterns
4. Run pilot deployment on chosen cloud
5. Validate performance meets requirements
6. Scale to production

---

For detailed setup instructions:
- AWS EKS: See [AWS_SETUP.md](./AWS_SETUP.md)
- Azure AKS: See [AZURE_SETUP.md](./AZURE_SETUP.md)
- Deployment: See [README.md](./README.md)
