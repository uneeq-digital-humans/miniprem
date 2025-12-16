# Azure Account Setup Guide

This guide explains how to create and configure Azure credentials for the Renny AKS deployment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Azure Account Setup](#azure-account-setup)
3. [Azure CLI Installation](#azure-cli-installation)
4. [Subscription Configuration](#subscription-configuration)
5. [GPU Instance Selection](#gpu-instance-selection)
6. [GPU Quota Requests](#gpu-quota-requests)
7. [Service Principal Creation](#service-principal-creation)
8. [Critical Warnings](#critical-warnings)
9. [Cost Estimation](#cost-estimation)
10. [Next Steps](#next-steps)

## Prerequisites

Before deploying Renny on Azure AKS, ensure you have:

- **Azure Account**: Free trial or paid subscription ($200 free credit for 30 days)
- **Azure CLI**: Version 2.50.0 or higher
- **kubectl**: Version 1.28.0 or higher
- **Terraform**: Version 1.5.0 or higher
- **Helm**: Version 3.12.0 or higher
- **Active Subscription**: With sufficient credits/quota for GPU instances

**Recommended System:**
- macOS, Linux, or Windows with WSL2
- 8GB+ RAM for deployment tools
- Stable internet connection (for large container image pulls)

## Azure Account Setup

### 1. Create Azure Account

If you don't have an Azure account:

1. Visit [https://azure.microsoft.com/free/](https://azure.microsoft.com/free/)
2. Click "Start free" or "Try Azure for free"
3. Sign in with Microsoft account (or create new one)
4. Complete identity verification:
   - Phone number verification
   - Credit card (for identity verification - not charged during trial)
5. Accept terms and conditions

**Free Trial Benefits:**
- $200 credit valid for 30 days
- 12 months of free services
- 25+ always-free services

### 2. Verify Subscription

After account creation, verify your subscription is active:

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Search for "Subscriptions" in the top search bar
3. Click on your subscription name
4. Note your **Subscription ID** (format: `12345678-1234-1234-1234-123456789012`)
5. Verify status shows "Active"

**Subscription Types:**
- **Free Trial**: $200 credit, 30 days
- **Pay-As-You-Go**: Standard billing, no commitment
- **Enterprise Agreement**: For organizations with volume licensing
- **Azure for Students**: $100 credit, no credit card required

### 3. Check Billing Status

Ensure you have sufficient credits/budget:

```bash
# Check current subscription status
az account show --query '[name,state,id]' --output table

# View available credits (if on free trial)
# Visit: https://www.microsoftazuresponsorships.com/balance
```

## Azure CLI Installation

### macOS

**Using Homebrew (Recommended):**
```bash
# Install Azure CLI
brew update && brew install azure-cli

# Verify installation
az --version
# Should show: azure-cli 2.50.0 or higher
```

**Manual Installation:**
```bash
# Download and install
curl -L https://aka.ms/InstallAzureCli | bash

# Restart terminal
exec -l $SHELL

# Verify installation
az --version
```

### Linux

**Ubuntu/Debian:**
```bash
# Install required packages
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verify installation
az --version
```

**RHEL/CentOS/Fedora:**
```bash
# Import Microsoft repository key
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

# Install Azure CLI
sudo dnf install azure-cli

# Verify installation
az --version
```

**Manual Installation (All Distributions):**
```bash
# Download install script
curl -L https://aka.ms/InstallAzureCli -o install_azure_cli.sh

# Make executable and run
chmod +x install_azure_cli.sh
./install_azure_cli.sh

# Add to PATH (if needed)
echo 'export PATH=$PATH:$HOME/azure-cli/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
az --version
```

### Windows

**Using Windows Package Manager (winget):**
```powershell
# Install Azure CLI
winget install -e --id Microsoft.AzureCLI

# Verify installation (restart terminal first)
az --version
```

**Using MSI Installer:**
1. Download installer from [https://aka.ms/installazurecliwindows](https://aka.ms/installazurecliwindows)
2. Run the MSI installer
3. Follow installation wizard
4. Restart terminal
5. Verify: `az --version`

**Using Chocolatey:**
```powershell
# Install Azure CLI
choco install azure-cli

# Verify installation
az --version
```

### Verify Installation

After installation, verify all components:

```bash
# Check Azure CLI version
az --version
# Expected: azure-cli 2.50.0+

# Check kubectl
kubectl version --client
# Expected: v1.28.0+

# Check Terraform
terraform version
# Expected: Terraform v1.5.0+

# Check Helm
helm version
# Expected: v3.12.0+
```

## Subscription Configuration

### 1. Login to Azure CLI

```bash
# Interactive browser-based login
az login

# Follow prompts:
# 1. Browser opens automatically
# 2. Sign in with your Azure account
# 3. Return to terminal once authenticated

# Verify login successful
az account show --output table
```

**Output Example:**
```
Name                 CloudName    SubscriptionId                        State    IsDefault
-------------------  -----------  ------------------------------------  -------  -----------
Pay-As-You-Go        AzureCloud   12345678-1234-1234-1234-123456789012  Enabled  True
```

### 2. Set Default Subscription

If you have multiple subscriptions:

```bash
# List all subscriptions
az account list --output table

# Set default subscription
az account set --subscription "12345678-1234-1234-1234-123456789012"

# Verify active subscription
az account show --query '[name,id]' --output table
```

### 3. Register Required Resource Providers

Azure requires resource providers to be registered before use:

```bash
# Register compute provider (for VMs)
az provider register --namespace Microsoft.Compute

# Register network provider (for VNets)
az provider register --namespace Microsoft.Network

# Register container service provider (for AKS)
az provider register --namespace Microsoft.ContainerService

# Register storage provider (for disks)
az provider register --namespace Microsoft.Storage

# Check registration status (takes 2-5 minutes)
az provider show -n Microsoft.Compute --query "registrationState"
az provider show -n Microsoft.Network --query "registrationState"
az provider show -n Microsoft.ContainerService --query "registrationState"
az provider show -n Microsoft.Storage --query "registrationState"

# All should show: "Registered"
```

## GPU Instance Selection

### Recommended: NC16as_T4_v3

**Why NC16as_T4_v3 is the Right Choice:**

| Feature | NC16as_T4_v3 | NVads_A10_v5 |
|---------|--------------|--------------|
| **GPU** | NVIDIA Tesla T4 (16GB VRAM) | NVIDIA A10 (24GB VRAM) |
| **vCPUs** | 16 AMD EPYC | 18 AMD EPYC |
| **RAM** | 110GB | 220GB |
| **Driver Type** | Standard NVIDIA | vGPU/GRID Only |
| **GPU Operator Compatible** | Yes | No |
| **Cost (East US)** | ~$1.50/hour | ~$3.06/hour |
| **Monthly Cost (10 nodes)** | ~$10,800/month | ~$22,032/month |
| **Renny Compatibility** | Proven with Unreal Engine | Untested, requires vGPU drivers |

### NC16as_T4_v3 Specifications

**GPU Capabilities:**
- **Model**: NVIDIA Tesla T4 (Turing architecture)
- **VRAM**: 16GB GDDR6
- **CUDA Cores**: 2,560
- **Tensor Cores**: 320
- **RT Cores**: 40
- **Driver Support**: Standard NVIDIA 580+ drivers
- **CUDA Version**: 12.4+ supported

**Compute Specifications:**
- **vCPUs**: 16 cores (AMD EPYC 7V12)
- **Memory**: 110GB RAM
- **Local Storage**: 360GB NVMe SSD
- **Network**: 8,000 Mbps expected bandwidth
- **Premium Storage**: Supported

**Why This Works for Renny:**
1. Uses standard NVIDIA drivers (not vGPU)
2. Compatible with GPU Operator for automatic driver installation
3. 16GB VRAM sufficient for 4 Renny pods per node with time-slicing
4. Proven compatibility with Unreal Engine Pixel Streaming
5. Cost-efficient: ~50% of NVads_A10_v5 pricing
6. AMD EPYC processors provide excellent CPU performance

### AVOID: NVads_A10_v5

**Why NVads_A10_v5 is NOT Recommended:**

Issue | Description |
|------|-------------|
| **vGPU/GRID Drivers Required** | Cannot use standard NVIDIA drivers (580+) |
| **GPU Operator Incompatible** | Requires manual driver installation and management |
| **Untested with Renny** | No validation with Unreal Engine Pixel Streaming stack |
| **Higher Cost** | 2x more expensive (~$3.06/hour vs ~$1.50/hour) |
| **Complex Setup** | Requires NVIDIA AI Enterprise license and vGPU setup |
| **Limited Documentation** | Less community support for Kubernetes + vGPU |

**When You Might Need NVads_A10_v5:**
- Enterprise with existing NVIDIA AI Enterprise licensing
- Workloads requiring 24GB VRAM per pod (rare for Renny)
- Specific vGPU features required by application

**Important**: Consult with UneeQ support before choosing NVads_A10_v5.

### Regional Availability

Check if NC16as_T4_v3 is available in your target region:

```bash
# Check availability in East US
az vm list-skus --location eastus --size Standard_NC --all --output table | grep NC16as_T4_v3

# Check availability in West US 2
az vm list-skus --location westus2 --size Standard_NC --all --output table | grep NC16as_T4_v3

# Check availability in North Europe
az vm list-skus --location northeurope --size Standard_NC --all --output table | grep NC16as_T4_v3

# Check availability in West Europe
az vm list-skus --location westeurope --size Standard_NC --all --output table | grep NC16as_T4_v3
```

**Confirmed Available Regions:**
- East US
- West US 2
- North Europe
- West Europe
- Southeast Asia
- Australia East

**Not Available:**
- Central US (use East US instead)
- West US (use West US 2 instead)
- North Central US (use East US instead)

## GPU Quota Requests

Azure enforces strict quotas on GPU instances. You MUST request quota increases before deployment.

### Understanding Azure Quotas

Azure has two quota levels:
1. **Subscription-level quotas**: Total resources across all regions
2. **Regional quotas**: Resources per specific region

**Default GPU Quotas** (typically 0 for new accounts):
- NC-series vCPUs: 0
- Total Regional vCPUs: 10-20
- Public IPs: 10
- VNets: 50

### Required Quotas for Renny Deployment

For a **10-node Renny deployment**:

| Resource | Default | Required | How to Request |
|----------|---------|----------|----------------|
| **Standard NCASv3_T4 Family vCPUs** | 0 | 160 | Support ticket |
| **Total Regional vCPUs** | 20 | 200+ | Support ticket |
| **Public IP Addresses** | 10 | 20 | Support ticket |
| **Virtual Networks** | 50 | 1 | No change needed |
| **Load Balancers** | 100 | 1 | No change needed |

**Calculation:**
- 10 nodes × 16 vCPUs per NC16as_T4_v3 = 160 vCPUs
- Add control plane, monitoring, and overhead = ~200 total vCPUs

### Check Current Quotas

```bash
# Check NC-series quota in East US
az vm list-usage --location eastus --query "[?contains(name.value, 'standardNCASFamily')]" --output table

# Check total regional vCPU quota
az vm list-usage --location eastus --query "[?contains(name.value, 'cores')]" --output table

# Check public IP quota
az network list-usages --location eastus --query "[?contains(name.value, 'PublicIP')]" --output table
```

**Example Output:**
```
Name                           CurrentValue    Limit
-----------------------------  --------------  -------
Standard NCASv3_T4 Family vCPUs  0              0       ← Need to increase!
Total Regional vCPUs             4              10      ← Need to increase!
Public IP Addresses              2              10      ← May need to increase
```

### How to Request Quota Increase

#### Method 1: Azure Portal (Recommended)

1. **Navigate to Quotas**:
   - Go to [Azure Portal](https://portal.azure.com)
   - Search for "Quotas" in top search bar
   - Select "Quotas" service

2. **Select Compute Quotas**:
   - Click "Compute" from the list of services
   - Filter by: `Subscription = Your subscription`
   - Filter by: `Location = eastus` (or your target region)

3. **Request NC-series Quota**:
   - Search for "Standard NCASv3_T4 Family vCPUs"
   - Click on the quota row
   - Click "Request increase"
   - Enter new limit: **160** (for 10 nodes)
   - Add business justification: "Deploying Renny digital humans on AKS with GPU support"
   - Click "Submit"

4. **Request Total Regional vCPU Quota**:
   - Search for "Total Regional vCPUs"
   - Click on the quota row
   - Click "Request increase"
   - Enter new limit: **200**
   - Add same justification
   - Click "Submit"

#### Method 2: Support Ticket

1. **Create Support Request**:
   - Go to Azure Portal > Help + support
   - Click "New support request"

2. **Issue Type**:
   - Issue type: "Service and subscription limits (quotas)"
   - Subscription: Select your subscription
   - Quota type: "Compute-VM (cores-vCPUs) subscription limit increases"
   - Click "Next"

3. **Problem Details**:
   - Deployment Model: "Resource Manager"
   - Location: Select your target region (e.g., East US)
   - SKU family: **Standard NCASv3_T4 Family**
   - New vCPU limit: **160**

4. **Additional Details**:
   - Severity: C - Minimal impact (or B if urgent)
   - Description: "Requesting quota increase for Renny digital human deployment on AKS. Requires 10 NC16as_T4_v3 instances (160 vCPUs) for GPU-accelerated Unreal Engine rendering."
   - Click "Next" and "Create"

#### Method 3: Azure CLI

```bash
# Note: This requires a support plan
az support tickets create \
  --ticket-name "Renny-GPU-Quota-Request" \
  --title "Quota increase for Standard NCASv3_T4 Family vCPUs" \
  --severity minimal \
  --description "Requesting 160 vCPUs for NC16as_T4_v3 instances in East US region for Renny digital human deployment" \
  --problem-classification "/providers/Microsoft.Support/services/quota/problemClassifications/compute-vm-cores"
```

### Quota Request Processing Time

**Expected Timeline:**
- **Standard Request**: 1-3 business days
- **Large Request (200+ vCPUs)**: 3-5 business days
- **Free Trial Accounts**: May take longer (5-7 business days)
- **Urgent Request**: 1 business day (requires Premier Support)

**Tips for Faster Approval:**
1. Provide detailed business justification
2. Include use case description (Renny deployment)
3. Specify exact instance types needed (NC16as_T4_v3)
4. Mention expected usage duration
5. Be specific about location and quantity

### What If Quota Request is Denied?

**Common Reasons for Denial:**
- Free trial account (limited to smaller quotas)
- Insufficient payment history
- Region capacity constraints
- Account flagged for fraud prevention

**Solutions:**
1. **Upgrade to Pay-As-You-Go**: Free trials have stricter limits
2. **Try Different Region**: Some regions have more capacity
3. **Start Smaller**: Request 5 nodes (80 vCPUs) first, then scale
4. **Contact Support**: Call Azure support to explain business need
5. **Alternative Instances**: Consider NC-series alternatives if available

## Service Principal Creation

Terraform needs a Service Principal to authenticate with Azure and manage resources.

### Recommended: Service Principal with Client Secret

This is the standard authentication method and works in all environments.

**Step 1: Create Service Principal**

```bash
# Create service principal and assign Contributor role to subscription
az ad sp create-for-rbac \
  --name "renny-aks-deployer" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv) \
  --output json

# Save the output - you'll need these values:
{
  "appId": "12345678-1234-1234-1234-123456789012",        # CLIENT_ID
  "displayName": "renny-aks-deployer",
  "password": "super-secret-password-here",               # CLIENT_SECRET
  "tenant": "87654321-4321-4321-4321-210987654321"       # TENANT_ID
}
```

**Important**: Save the `password` immediately - Azure will never show it again.

**Step 2: Note Required Values**

You'll need these four values for Terraform:
- **SUBSCRIPTION_ID**: From `az account show --query id -o tsv`
- **TENANT_ID**: From service principal output above
- **CLIENT_ID**: The `appId` from service principal output
- **CLIENT_SECRET**: The `password` from service principal output

**Step 3: Verify Service Principal**

```bash
# Test authentication
az login --service-principal \
  --username "12345678-1234-1234-1234-123456789012" \  # CLIENT_ID
  --password "super-secret-password-here" \             # CLIENT_SECRET
  --tenant "87654321-4321-4321-4321-210987654321"      # TENANT_ID

# Verify permissions
az role assignment list --assignee "12345678-1234-1234-1234-123456789012" --output table

# Expected: Should show "Contributor" role on your subscription
```

### Step 5: Understanding Kubernetes RBAC vs Azure IAM

**Critical Distinction:**

The service principal you created has **Azure IAM permissions** but needs **Kubernetes RBAC permissions** to manage resources inside the cluster.

| Permission Type | Purpose | Granted By |
|----------------|---------|------------|
| **Azure IAM (Contributor)** | Create/manage Azure resources (AKS clusters, VMs, networks) | `az role assignment create` |
| **Kubernetes RBAC** | Manage resources INSIDE the cluster (pods, secrets, namespaces) | Kubernetes role bindings OR `--admin` credentials |

**What This Means:**
- Your service principal can CREATE the AKS cluster ✅
- But it CANNOT manage resources inside the cluster (create namespaces, deploy pods) ❌

**The Solution:**
The deployment script automatically uses `--admin` flag when fetching credentials, which bypasses this issue by using the cluster's built-in admin certificate instead of Azure AD authentication.

### Step 6: Choose Authentication Method for kubectl

**Option A: Use Admin Credentials (Recommended for Automation) ✅**

The deployment script automatically uses this method:
```bash
az aks get-credentials --resource-group rg --name cluster --admin
```

**Pros:**
- Works immediately (no additional configuration)
- Uses cluster's built-in admin certificate
- Standard practice for CI/CD and automation
- No additional role assignments needed
- Avoids Azure AD authentication complexity

**Cons:**
- Bypasses Azure AD audit logging
- Not recommended for interactive/multi-user scenarios
- All operations performed as cluster-admin

**Option B: Grant Kubernetes RBAC Role to Service Principal**

For production environments with multiple users, assign Kubernetes RBAC permissions:
```bash
# After cluster creation, grant cluster-admin permissions
az role assignment create \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --assignee "$CLIENT_ID" \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/renny-kubernetes/providers/Microsoft.ContainerService/managedClusters/renny-production"
```

**Pros:**
- Full Azure AD integration
- Better audit logging
- Supports multiple users with different permissions
- Fine-grained access control (cluster-admin, namespace-scoped, etc.)

**Cons:**
- Requires additional configuration after cluster creation
- Can have authentication delays
- More complex troubleshooting
- Service principal needs to authenticate before kubectl commands work

**For Renny Deployment:**
The script uses **Option A** (`--admin`) for reliability and simplicity. This is the recommended approach for automated deployments and single-user scenarios.

**Step 4: Add to Terraform Configuration**

Copy `kubernetes/terraform/aks/terraform.tfvars.local` from the example and fill in your values:

```hcl
# Azure authentication
azure_subscription_id = "12345678-1234-1234-1234-123456789012"
azure_tenant_id       = "87654321-4321-4321-4321-210987654321"
azure_client_id       = "12345678-1234-1234-1234-123456789012"
azure_client_secret   = "super-secret-password-here"

# Required Renny credentials
dhop_tenant_id  = "your-uneeq-tenant-id"
dhop_api_key    = "your-uneeq-api-key"

# Harbor registry credentials (contact help@uneeq.com for robot account)
harbor_username = "robot$your-customer-name"
harbor_password = "your-harbor-robot-password"

# Optional: Override defaults
azure_region = "westus3"  # Change to your preferred region
```

Then copy to the working file:
```bash
cp kubernetes/terraform/aks/terraform.tfvars.local kubernetes/terraform/aks/terraform.tfvars
```

### Alternative: Certificate-Based Authentication

**Only required in environments with security policies that prohibit client secrets.** If your organization requires certificate-based authentication, you likely have internal documentation for this process. The standard client secret method (above) works in all other scenarios.

For certificate authentication, use `--cert @cert.pem` when creating the service principal and configure Terraform with `client_certificate_path` instead of `client_secret`.

### Alternative: Managed Identity (For Production/CI/CD)

If running Terraform from an Azure VM or Azure DevOps:

**Step 1: Enable System-Assigned Managed Identity**

```bash
# Enable on Azure VM
az vm identity assign \
  --name terraform-runner-vm \
  --resource-group deployment-rg

# Enable on Azure DevOps agent (via Azure Portal)
```

**Step 2: Grant Permissions**

```bash
# Assign Contributor role to managed identity
az role assignment create \
  --role Contributor \
  --assignee-object-id $(az vm show --name terraform-runner-vm --resource-group deployment-rg --query identity.principalId -o tsv) \
  --scope /subscriptions/$(az account show --query id -o tsv)
```

**Step 3: Configure Terraform**

```hcl
# terraform/provider.tf - Use managed identity
provider "azurerm" {
  features {}
  use_msi = true  # Enable managed identity authentication
}
```

### Security Best Practices

**1. Limit Service Principal Scope**

```bash
# Instead of subscription-wide Contributor, limit to resource group:
az ad sp create-for-rbac \
  --name "renny-aks-deployer-limited" \
  --role Contributor \
  --scopes /subscriptions/$(az account show --query id -o tsv)/resourceGroups/renny-production-rg
```

**2. Rotate Credentials Regularly**

```bash
# Rotate client secret every 90 days
az ad sp credential reset \
  --id "12345678-1234-1234-1234-123456789012" \
  --append  # Keep old secret valid for transition

# Update terraform.tfvars with new secret
```

**3. Use Azure Key Vault**

```bash
# Store secrets in Key Vault instead of plaintext files
az keyvault create --name renny-secrets --resource-group deployment-rg
az keyvault secret set --vault-name renny-secrets --name client-secret --value "your-secret"

# Reference in Terraform:
data "azurerm_key_vault_secret" "client_secret" {
  name         = "client-secret"
  key_vault_id = azurerm_key_vault.deployment.id
}
```

**4. Restrict by IP Address**

```bash
# Add conditional access policy to limit SP usage to specific IPs
# Via Azure Portal > Azure AD > Security > Conditional Access
```

**5. Kubeconfig Security**

The deployment script automatically sets secure permissions on kubeconfig:
```bash
chmod 600 ~/.kube/config
```

**What this does:**
- Owner: Read + Write (you)
- Group: No access
- Others: No access

**Why it matters:**
- Prevents unauthorized users from accessing your cluster
- Required by Kubernetes security best practices
- Blocks malware from exfiltrating credentials
- Satisfies compliance requirements (SOC 2, HIPAA, etc.)

**Azure CLI Warning:**
When you run `az aks get-credentials`, you may see:
```
/Users/username/.kube/config has permissions "644".
It should be readable and writable only by its owner.
```

**This is automatically fixed by the deployment script** with `chmod 600`, so you can safely ignore this warning.

**Manual Fix (if needed):**
```bash
# Set secure permissions
chmod 600 ~/.kube/config

# Verify permissions
ls -l ~/.kube/config
# Expected: -rw------- (600)
```

## Critical Warnings

### GPU Driver Type (Critical Decision)

| Instance Type | Driver Type | GPU Operator | Renny Compatibility |
|---------------|-------------|--------------|---------------------|
| **NC16as_T4_v3** | **Standard NVIDIA** | **Yes** | **Proven** |
| NVads_A10_v5 | vGPU/GRID Only | **No** | Untested |

**For Renny deployment, you MUST use NC-series (NC16as_T4_v3) with standard NVIDIA drivers.**

**Why This Matters:**
- **GPU Operator Requirement**: Renny deployment uses NVIDIA GPU Operator for automatic driver installation
- **Driver Compatibility**: GPU Operator only supports standard NVIDIA drivers, not vGPU/GRID drivers
- **Unreal Engine**: NC16as_T4_v3 proven compatible with Unreal Engine Pixel Streaming
- **Support**: Standard drivers have better community support and documentation

**What Happens If You Use NVads_A10_v5:**
- GPU Operator will fail to install drivers
- Pods will remain in `Pending` state with "Insufficient nvidia.com/gpu" errors
- Manual driver installation required (complex and unsupported)
- No time-slicing support
- Potential licensing issues with NVIDIA AI Enterprise

### Cost Management

**NC16as_T4_v3 Pricing (East US, Pay-As-You-Go):**

| Configuration | Hourly Cost | Daily Cost | Monthly Cost |
|---------------|-------------|------------|--------------|
| **1 node** | ~$1.50 | ~$36 | ~$1,080 |
| **5 nodes** | ~$7.50 | ~$180 | ~$5,400 |
| **10 nodes (recommended)** | ~$15.00 | ~$360 | ~$10,800 |
| **20 nodes (max scale)** | ~$30.00 | ~$720 | ~$21,600 |

**Additional Infrastructure Costs:**
- AKS Control Plane: ~$73/month
- Load Balancer: ~$25/month
- Public IPs (3×): ~$12/month
- Managed Disks (storage): ~$50-100/month
- Data Transfer: ~$50-200/month (varies with usage)

**Total Monthly Cost Estimate:**
- **Base (10 nodes)**: ~$11,000/month
- **Maximum (20 nodes)**: ~$22,000/month

**Cost-Saving Strategies:**

1. **Reserved Instances (20-40% savings)**:
   ```bash
   # Purchase 1-year reserved instance
   az reservations reservation-order calculate --location eastus --sku NC16as_T4_v3_Priority

   # Savings example:
   # On-demand: $1.50/hour = $10,800/month
   # 1-year reserved: ~$1.05/hour = ~$7,560/month (save $3,240/month)
   # 3-year reserved: ~$0.90/hour = ~$6,480/month (save $4,320/month)
   ```

2. **Spot Instances (60-80% savings for dev/test)**:
   ```bash
   # Use spot pricing for non-production workloads
   # NC16as_T4_v3 spot: ~$0.30-0.60/hour (vs $1.50 regular)
   # Savings: ~$8,640/month on 10-node cluster
   # Caveat: Can be evicted with 30-second notice
   ```

3. **Auto-Scaling**:
   ```yaml
   # Scale down during off-hours (16 hours/day)
   # Savings: ~40% reduction = ~$4,320/month
   # Configure in Terraform:
   aks_node_pool_min_size = 2   # Minimum nodes
   aks_node_pool_max_size = 10  # Maximum nodes
   ```

4. **Scheduled Shutdown**:
   ```bash
   # Stop cluster at night and weekends (saves ~70% of costs)
   az aks stop --name renny-production --resource-group renny-rg
   az aks start --name renny-production --resource-group renny-rg

   # Automate with Azure Automation or Azure Functions
   # Estimated savings: ~$7,560/month (70% of $10,800)
   ```

5. **Right-Sizing**:
   ```bash
   # Start with 5 nodes, scale up as needed
   # Initial cost: ~$5,400/month (vs $10,800)
   # Scale to 10 nodes only when traffic requires it
   ```

**Cost Monitoring:**
```bash
# Check current month spending
az consumption usage list --start-date 2025-10-01 --end-date 2025-10-16 --query '[].{Service:instanceName,Cost:pretaxCost}' --output table

# Set up budget alerts
az consumption budget create \
  --budget-name renny-monthly-budget \
  --amount 12000 \
  --time-grain Monthly \
  --start-date 2025-10-01 \
  --end-date 2026-10-01

# Enable Azure Cost Management alerts
# Via Azure Portal > Cost Management + Billing > Budgets
```

**Important**: Always destroy resources when not actively using them to avoid unnecessary charges.

### Regional Availability

NC16as_T4_v3 is **NOT available in all Azure regions**. Verify availability before deployment.

**Confirmed Available Regions:**
- East US
- West US 2
- North Europe
- West Europe
- Southeast Asia
- Australia East

**Limited Availability Regions:**
- South Central US (check quota)
- Japan East (check quota)
- UK South (check quota)

**Not Available:**
- Central US → Use East US instead
- West US → Use West US 2 instead
- North Central US → Use East US instead
- Canada Central → Use East US instead

**Check Availability:**
```bash
# Check if NC16as_T4_v3 is available in your region
az vm list-skus --location eastus --size Standard_NC --all --output table | grep NC16as_T4_v3

# If output is empty or shows "NotAvailableForSubscription":
# 1. Try different region
# 2. Request quota increase (may unlock availability)
# 3. Contact Azure support for capacity reservation
```

### VNet and Resource Group Planning

**Critical Decisions Before Deployment:**

1. **Resource Group Naming**:
   - Cannot be changed after creation
   - Recommended format: `renny-production-<region>`
   - Example: `renny-production-eastus`

2. **VNet CIDR Selection**:
   - Cannot be changed after deployment
   - Must not overlap with existing networks
   - Recommended: `10.20.0.0/16` (65,534 IPs)
   - Alternative: `10.50.0.0/16` or `192.168.0.0/16`

3. **Subnet Allocation**:
   - AKS System Pool: /24 (254 nodes max)
   - AKS User Pool: /22 (1,022 nodes max)
   - Application Gateway: /24 (if using)
   - Reserve space for future expansion

**VNet Planning Example:**
```hcl
# terraform/terraform.tfvars
vnet_cidr = "10.20.0.0/16"

# Subnet allocation:
# 10.20.1.0/24  = System node pool (254 IPs)
# 10.20.4.0/22  = User node pool (1,022 IPs)
# 10.20.8.0/24  = Application Gateway (254 IPs)
# 10.20.9.0/24  = Future services
# Remaining     = Reserved for expansion
```

## Cost Estimation

### Detailed Monthly Cost Breakdown (10-Node Deployment, East US)

| Component | Specification | Quantity | Unit Cost | Monthly Cost |
|-----------|--------------|----------|-----------|--------------|
| **GPU Compute** | NC16as_T4_v3 | 10 nodes | $1.50/hour | $10,800 |
| **AKS Control Plane** | Managed service | 1 cluster | $0.10/hour | $73 |
| **Control Nodes** | Standard_D4s_v3 | 2 nodes | $0.20/hour | $288 |
| **Load Balancer** | Standard SKU | 1 LB | ~$25/month | $25 |
| **Public IPs** | Standard SKU | 3 IPs | $4/month | $12 |
| **Managed Disks** | Premium SSD | ~500GB | $0.15/GB | $75 |
| **Data Transfer** | Outbound | ~500GB | $0.05/GB | $25 |
| **Azure Monitor** | Log Analytics | ~50GB | $2.50/GB | $125 |
| **Storage** | Blob storage | ~100GB | $0.02/GB | $2 |
| **Total** | | | | **~$11,425/month** |

### Cost Comparison: Pay-As-You-Go vs Reserved vs Spot

**10-Node Deployment (NC16as_T4_v3):**

| Pricing Model | Hourly | Daily | Monthly | Annual | Savings |
|---------------|--------|-------|---------|--------|---------|
| **Pay-As-You-Go** | $15.00 | $360 | $10,800 | $129,600 | Baseline |
| **1-Year Reserved** | $10.50 | $252 | $7,560 | $90,720 | 30% ($38,880) |
| **3-Year Reserved** | $9.00 | $216 | $6,480 | $77,760 | 40% ($51,840) |
| **Spot (80% off)** | $3.00 | $72 | $2,160 | $25,920 | 80% ($103,680) |
| **Hybrid (5 reserved + 5 spot)** | $6.75 | $162 | $4,860 | $58,320 | 55% ($71,280) |

**Note**: Spot pricing is variable and instances can be evicted. Best for dev/test.

### Cost Scaling Examples

**Small Deployment (5 nodes):**
- GPU Compute: ~$5,400/month
- Infrastructure: ~$625/month
- **Total**: ~$6,025/month

**Medium Deployment (10 nodes):**
- GPU Compute: ~$10,800/month
- Infrastructure: ~$625/month
- **Total**: ~$11,425/month

**Large Deployment (20 nodes):**
- GPU Compute: ~$21,600/month
- Infrastructure: ~$825/month
- **Total**: ~$22,425/month

### Hidden Costs to Consider

**1. Data Transfer Costs:**
- First 100GB outbound: Free
- Next 9.9TB: $0.05/GB (~$495 per TB)
- Inbound data transfer: Always free
- Inter-region transfer: $0.02/GB

**2. Storage Costs:**
- Premium SSD (P30, 1TB): ~$135/month per disk
- Standard SSD (E30, 1TB): ~$76/month per disk
- Snapshots: $0.05/GB per month
- Recommended: Use managed disks for simplicity

**3. Networking Costs:**
- Load Balancer data processing: $0.005 per GB
- Public IP (Standard): $4/month per IP
- VPN Gateway (if used): ~$27-525/month depending on SKU

**4. Monitoring and Logging:**
- Azure Monitor: $2.50/GB ingested
- Log Analytics: $2.50/GB ingested
- Application Insights: $2.50/GB ingested
- Typical usage: 50-100GB/month = $125-250

**5. Backup and Disaster Recovery:**
- Azure Backup: $0.10-0.20 per instance/month
- Geo-redundant storage: 2x cost of standard storage
- Snapshot storage: $0.05/GB/month

### ROI and Break-Even Analysis

**Scenario: Replace On-Premises GPU Infrastructure**

**On-Premises Initial Investment:**
- 10× NVIDIA A10G GPUs: ~$50,000
- 10× GPU Servers: ~$100,000
- Networking equipment: ~$25,000
- Rack space and power: ~$10,000
- **Total Initial**: ~$185,000

**On-Premises Annual Operating Costs:**
- Power (10kW @ $0.12/kWh): ~$10,512/year
- Cooling: ~$5,256/year
- IT staff (25% FTE): ~$37,500/year
- Maintenance: ~$10,000/year
- **Total Annual Opex**: ~$63,268/year
- **3-Year TCO**: $374,804

**Azure AKS (3-Year Reserved Instances):**
- GPU Compute (10 nodes): $77,760/year
- Infrastructure: $7,500/year
- **Total Annual**: $85,260/year
- **3-Year Total**: $255,780

**Savings**: $119,024 over 3 years (31% reduction)

**Additional Azure Benefits:**
- No upfront capital expenditure
- Instant scalability (10-20 nodes in minutes)
- No hardware obsolescence risk
- Global availability
- Automatic security updates
- 99.95% SLA

## Next Steps

### Pre-Deployment Checklist

Before running the deployment script, ensure you have:

- [ ] **Azure account created** and verified
- [ ] **Active subscription** with sufficient credits/budget
- [ ] **Azure CLI installed** (version 2.50.0+)
- [ ] **Service principal created** with Contributor role
- [ ] **GPU quota approved** (160 vCPUs for NC16as_T4_v3 in target region)
- [ ] **Regional availability confirmed** for NC16as_T4_v3
- [ ] **terraform.tfvars configured** with all required credentials:
  - `azure_subscription_id`
  - `azure_tenant_id`
  - `azure_client_id`
  - `azure_client_secret`
  - `dhop_tenant_id` (UneeQ)
  - `dhop_api_key` (UneeQ)
  - `harbor_username` (Harbor registry robot account)
  - `harbor_password` (Harbor registry robot password)
- [ ] **VNet CIDR planned** (e.g., `10.20.0.0/16`)
- [ ] **Resource group name decided** (e.g., `renny-production-eastus`)
- [ ] **kubectl, Helm, and Terraform installed** (versions verified)

### Begin Deployment

Once all prerequisites are complete:

```bash
# Navigate to Kubernetes directory
cd kubernetes/

# Make scripts executable
chmod +x scripts/*.sh

# Run one-click deployment
./scripts/deploy.sh

# Deployment will:
# 1. Verify prerequisites and Azure authentication (~2 min)
# 2. Deploy VNet and AKS cluster via Terraform (~15-20 min)
# 3. Configure node pools and join to cluster (~5 min)
# 4. Install NVIDIA GPU Operator (~5-10 min)
# 5. Deploy Renny with GPU time-slicing (~5-10 min)
# 6. Configure monitoring and logging (~3 min)
#
# Total time: ~35-50 minutes
```

### Post-Deployment Tasks

After successful deployment:

```bash
# 1. Verify cluster health
kubectl get nodes -o wide
kubectl get pods -A

# 2. Check GPU availability
kubectl get nodes -L nvidia.com/gpu

# 3. Monitor Renny pods
kubectl get pods -n uneeq-renderer

# 4. View deployment status
./scripts/status.sh

# 5. Test GPU functionality
kubectl run gpu-test --rm -it --restart=Never \
  --image=nvidia/cuda:12.4-runtime-ubuntu22.04 \
  --overrides='{"spec":{"nodeSelector":{"agentpool":"rennygpu"}}}' \
  -- nvidia-smi
```

### Troubleshooting Resources

- **Azure Documentation**: [https://docs.microsoft.com/azure/aks/](https://docs.microsoft.com/azure/aks/)
- **GPU Operator Docs**: [https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/)
- **Kubernetes Troubleshooting**: See `kubernetes/README.md` → Troubleshooting section
- **Azure Support**: Available 24/7 via Azure Portal or `az support` command

### Multi-Cloud Considerations

If you're evaluating both AWS and Azure, see the [Multi-Cloud Guide](./MULTI_CLOUD_GUIDE.md) for:
- Feature parity comparison
- Cost analysis (EKS vs AKS)
- When to choose each platform
- Migration strategies

---

## Summary

**Quick Start Path:**
1. Create Azure account → Get $200 free credit
2. Install Azure CLI → `az login`
3. Request GPU quota → 160 vCPUs for NC16as_T4_v3
4. Create service principal → Save credentials
5. Configure terraform.tfvars → Add all credentials
6. Run deployment script → `./scripts/deploy.sh`

**Expected Timeline:**
- Account setup: 15 minutes
- Quota approval: 1-3 business days
- Deployment: 35-50 minutes
- **Total**: 2-4 days (including quota wait)

**Expected Costs (Pay-As-You-Go):**
- **Development (5 nodes)**: ~$6,025/month
- **Production (10 nodes)**: ~$11,425/month
- **Scale-out (20 nodes)**: ~$22,425/month

**Cost Optimization:**
- **Reserved Instances**: Save 30-40%
- **Spot Instances**: Save 60-80% (dev/test only)
- **Auto-scaling**: Save ~40% during off-hours
- **Scheduled shutdown**: Save ~70% (nights/weekends)

**Critical Decision:**
- Use **NC16as_T4_v3** with standard NVIDIA drivers
- Avoid **NVads_A10_v5** (vGPU/GRID drivers incompatible with GPU Operator)

For production deployments, consider:
- Reserved instances for 30-40% cost savings
- Multi-region deployment for high availability
- Azure Monitor integration for alerting
- Azure Key Vault for credential management

---

**Need Help?**
- AWS comparison: See [MULTI_CLOUD_GUIDE.md](./MULTI_CLOUD_GUIDE.md)
- Deployment issues: See [kubernetes/README.md](./README.md) → Troubleshooting
- Azure support: `az support tickets create` or Azure Portal
