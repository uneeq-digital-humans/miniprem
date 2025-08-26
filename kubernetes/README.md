# Renny EKS Deployment Solution

This folder contains a complete one-click deployment solution for Renny on AWS EKS with GPU support.

## 📁 Folder Structure

```
kubernetes/
├── terraform/           # Infrastructure as Code
│   ├── main.tf         # Main Terraform configuration
│   ├── variables.tf    # Variable definitions
│   ├── outputs.tf      # Output definitions
│   ├── vpc.tf          # VPC configuration
│   ├── eks.tf          # EKS cluster configuration
│   ├── node-groups.tf  # Node group configurations
│   └── iam.tf          # IAM roles and policies
├── manifests/          # Kubernetes manifests
│   ├── namespace.yaml  # Namespace definition
│   ├── gpu-operator.yaml
│   └── autoscaler.yaml
├── values/             # Helm chart values
│   ├── renny-values.yaml
│   └── a2f-values.yaml
├── scripts/            # Deployment scripts
│   ├── deploy.sh       # One-click deployment (~30-45 min)
│   ├── scale.sh        # Scale Renny instances
│   ├── destroy.sh      # Full cleanup (~15-20 min)
│   ├── status.sh       # Check deployment status
│   ├── cleanup.sh      # Emergency cleanup (no confirmations)
│   ├── check-aws-prerequisites.sh # Verify AWS setup
│   └── check-vpc-usage.sh # Analyze VPC usage and limits
└── README.md           # This file
```

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate permissions (see [AWS_SETUP.md](AWS_SETUP.md))
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0 (see installation below)
4. **kubectl** 
5. **Helm** >= 3.0
6. **Docker Hub** account with access to UneeQ repositories
7. **Renny Helm chart** (renny-chart.tar file)

#### Install Required Tools

**Terraform Installation:**

*macOS:*
```bash
# Using Homebrew (recommended)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Or download binary
curl -LO https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_darwin_arm64.zip
unzip terraform_1.6.6_darwin_arm64.zip
sudo mv terraform /usr/local/bin/
```

*Linux:*
```bash
# Using package manager (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Or download binary
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

*Windows:*
```powershell
# Using Chocolatey (recommended)
choco install terraform

# Using Scoop
scoop install terraform

# Or download binary from https://releases.hashicorp.com/terraform/
# Extract and add to PATH
```

**Other Tools:**

*AWS CLI:*
- macOS: `brew install awscli`
- Linux: `pip install awscli` or use package manager
- Windows: Download from AWS or `choco install awscli`

*kubectl:*
- macOS: `brew install kubectl`
- Linux: `sudo snap install kubectl --classic`
- Windows: `choco install kubernetes-cli`

*Helm:*
- macOS: `brew install helm`
- Linux: `sudo snap install helm --classic`
- Windows: `choco install kubernetes-helm`

**Verify Installations:**
```bash
terraform version  # Should show v1.6.6 or higher
aws --version      # AWS CLI version
kubectl version    # Kubernetes CLI
helm version       # Helm package manager
```

1. **AWS Account** with appropriate permissions (see [AWS_SETUP.md](AWS_SETUP.md))
2. **AWS CLI** configured with credentials
3. **Terraform** >= 1.0
4. **kubectl** 
5. **Helm** >= 3.0
6. **Docker Hub** account with access to UneeQ repositories
7. **Renny Helm chart** (renny-chart.tgz file)

### Step -1: Install Required Tools

**Terraform Installation:**

*macOS:*
```bash
# Using Homebrew (recommended)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Or download binary
curl -LO https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_darwin_arm64.zip

unzip terraform_1.6.6_darwin_arm64.zip
sudo mv terraform /usr/local/bin/
```

*Linux:*
```bash
# Using package manager (Ubuntu/Debian)
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Or download binary
wget https://releases.hashicorp.com/terraform/1.6.6/terraform_1.6.6_linux_amd64.zip
unzip terraform_1.6.6_linux_amd64.zip
sudo mv terraform /usr/local/bin/
```

*Windows:*
```powershell
# Using Chocolatey (recommended)
choco install terraform

# Using Scoop
scoop install terraform

# Manual: Download from https://releases.hashicorp.com/terraform/
# Extract terraform.exe and add directory to PATH
```

**Other Required Tools:**

*AWS CLI:*
- macOS: `brew install awscli`
- Linux: `pip install awscli` or `sudo apt install awscli`
- Windows: `choco install awscli` or download from AWS

*kubectl:*
- macOS: `brew install kubectl`
- Linux: `sudo snap install kubectl --classic`
- Windows: `choco install kubernetes-cli`

*Helm:*
- macOS: `brew install helm`
- Linux: `sudo snap install helm --classic`
- Windows: `choco install kubernetes-helm`

**Verify Installations:**
```bash
terraform version  # Should show v1.6.6 or higher
aws --version      # AWS CLI version
kubectl version    # Kubernetes CLI
helm version       # Helm package manager
```

### Step 0: Setup AWS Credentials

**Quick Setup (for testing):**

Check [AWS SETUP](AWS_SETUP.md) for more detailed instructions.

1. Create an IAM user in AWS Console with:
   - `PowerUserAccess` policy
   - `IAMFullAccess` policy
2. Download the access key CSV
3. Configure AWS CLI:
   ```bash
   aws configure
   # Enter Access Key ID and Secret Access Key from CSV
   # Region: your preferred region (default: us-east-2)
   ```

**Verify your AWS setup:**
```bash
./scripts/check-aws-prerequisites.sh
```

**Check VPC availability (important - AWS has VPC limits):**
```bash
./scripts/check-vpc-usage.sh
```

This deployment creates a new VPC, so you need to ensure you haven't hit the VPC limit (5 per region by default). The VPC checker helps you:
- Analyze VPC usage across all AWS services 
- Identify unused VPCs that can be safely deleted
- Check specific VPCs or regions

**VPC Checker Usage Examples:**
```bash
# Check all VPCs in your configured region
./scripts/check-vpc-usage.sh

# Check VPCs in a specific region
./scripts/check-vpc-usage.sh --region us-west-2

# Analyze a specific VPC 
./scripts/check-vpc-usage.sh --vpc vpc-123456789

# Analyze specific VPC in specific region
./scripts/check-vpc-usage.sh --region us-west-2 --vpc vpc-123456789
```

The script will show you which VPCs are safe to delete and provide deletion commands if needed.

For detailed AWS setup instructions, see [AWS_SETUP.md](AWS_SETUP.md).

### Step 1: Configure Credentials

Create `terraform/terraform.tfvars` with your credentials:

```hcl
# Required credentials
dhop_tenant_id  = "your-tenant-id"
dhop_api_key    = "your-base64-encoded-api-key"
docker_username = "your-dockerhub-username"
docker_password = "your-dockerhub-password"

# Optional: Override defaults
aws_region = "us-east-2"  # Change to your preferred region
```

The region will be used by all scripts automatically. You can also override other settings like instance types and scaling parameters - see `terraform.tfvars.example` for all options.

### Step 2: Place Helm Chart

Place your `renny-chart.tgz` file in the `kubernetes/` directory.

### Step 3: Deploy

Run the one-click deployment:

```bash
cd kubernetes
chmod +x scripts/*.sh
./scripts/deploy.sh
```

This will:
1. ✅ Check prerequisites
2. 🏗️ Deploy VPC and EKS cluster via Terraform (~15-20 minutes)
3. 🎮 Install NVIDIA GPU Operator (~5-10 minutes)
4. 🎭 Deploy Audio2Face on dedicated GPU nodes (~3-5 minutes)
5. 🤖 Deploy Renny on separate GPU nodes (10 instances) (~5-10 minutes)
6. ⚖️ Configure autoscaling (10-20 instances)

**Total deployment time: ~30-45 minutes**

## 📊 Architecture

### Cluster Configuration

- **Region**: Configurable (default: us-east-2)
- **Kubernetes Version**: 1.31
- **Node Groups**:
  - **Control Plane**: 2x t3.large nodes (for management)
  - **Renny Nodes**: 10-20x g5.2xlarge GPU instances
  - **A2F Nodes**: 2-5x g5.2xlarge GPU instances

### Network Architecture

```
Internet → ALB/NLB → EKS Cluster
                      ├── GPU Node Group (Renny)
                      │   └── 10-20 g5.2xlarge instances
                      ├── GPU Node Group (A2F)
                      │   └── 2-5 g5.2xlarge instances
                      └── Control Node Group
                          └── 2 t3.large instances
```

### Port Configuration

- **WebRTC/UDP**: 22000-23000 (for PixelStreaming)
- **TURN/STUN**: 3478 (TCP/UDP)
- **HTTPS**: 443 (egress to *.uneeq.io)

## 🔧 Operations

### Scaling Renny Instances

Scale between 10-20 instances:

```bash
./scripts/scale.sh 15  # Scale to 15 instances
```

### Check Deployment Status

Get a comprehensive status report:
```bash
./scripts/status.sh
```

### Monitoring

View cluster status:
```bash
kubectl get nodes -l uneeq.io/node-type=renny
kubectl get pods -n uneeq-renderer
```

Check GPU utilization:
```bash
kubectl exec -n gpu-operator $(kubectl get pods -n gpu-operator -l app=nvidia-dcgm-exporter -o name | head -1) -- nvidia-smi
```

### Updating Configuration

1. Edit values files in `values/`
2. Upgrade Helm releases:
```bash
helm upgrade renny ./renny-chart.tgz -n uneeq-renderer -f values/renny-values.yaml
helm upgrade a2f oci://registry-1.docker.io/facemeproduction/a2f -n uneeq-renderer -f values/a2f-values.yaml
```

### Cleanup

To destroy all resources (takes ~15-20 minutes):
```bash
./scripts/destroy.sh
```

This will:
1. Prompt for confirmation (twice)
2. Remove all Helm deployments
3. Delete Kubernetes resources and wait for cleanup
4. Remove EKS node groups (waits for completion)
5. Destroy all AWS infrastructure via Terraform
6. Clean up local files

**Important**: The destroy script waits for resources to be fully deleted before proceeding, ensuring clean removal and avoiding AWS charges.

For emergency cleanup without confirmations:
```bash
./scripts/cleanup.sh  # USE WITH CAUTION
```

## 🔐 Security Considerations

- All GPU nodes are in private subnets
- Security groups configured for WebRTC/TURN traffic
- IRSA enabled for pod-level AWS permissions
- Network policies can be added as needed
- Secrets managed via Kubernetes secrets

## 💰 Cost Optimization

### Estimated Costs (us-east-1)

- **EKS Control Plane**: ~$73/month
- **NAT Gateways** (3x): ~$135/month
- **Control Nodes** (2x t3.large): ~$120/month
- **Renny Nodes** (10x g5.2xlarge): ~$8,760/month
- **A2F Nodes** (2x g5.2xlarge): ~$1,752/month
- **Total Base**: ~$10,840/month

*Note: Costs scale with the number of Renny instances (10-20)*

**IMPORTANT**: Remember to destroy resources when not in use:
- Hourly cost: ~$15-20/hour
- Daily cost if left running: ~$360-480/day

### Cost Saving Tips

1. Use single NAT gateway for dev/test
2. Scale down to minimum during off-hours
3. Consider Spot instances for non-critical workloads
4. Use Reserved Instances for production

## 🐛 Troubleshooting

### GPU Operator Issues
```bash
kubectl logs -n gpu-operator -l app=nvidia-operator
kubectl describe nodes | grep -A 5 "Allocated resources"
```

### Renny Pod Not Starting
```bash
kubectl describe pod <renny-pod> -n uneeq-renderer
kubectl logs <renny-pod> -n uneeq-renderer
```

### A2F Connection Issues
```bash
kubectl exec -it <renny-pod> -n uneeq-renderer -- curl http://audio2face-gateway:52000/health
```

## 📞 Support

For issues specific to:
- **Infrastructure**: Check Terraform state and AWS Console
- **Kubernetes**: Use `kubectl describe` and `kubectl logs`
- **GPU**: Check NVIDIA GPU Operator logs
- **Renny/A2F**: Contact UneeQ support with pod logs

## 🔄 Updates and Maintenance

### Updating EKS Version
1. Update `kubernetes_version` in `terraform/variables.tf`
2. Run `terraform apply` to update control plane
3. Update node groups via AWS Console or Terraform

### Updating GPU Drivers
```bash
helm upgrade gpu-operator nvidia/gpu-operator -n gpu-operator
```

### Backup Considerations
- Terraform state should be stored in S3 with versioning
- Consider using Velero for Kubernetes backup
- Persistent volumes use EBS with snapshot capabilities