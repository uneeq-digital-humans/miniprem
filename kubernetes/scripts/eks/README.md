# EKS-Specific Utility Scripts

This directory contains AWS EKS-specific utility scripts for checking prerequisites and resource usage.

## Scripts

### check-aws-prerequisites.sh

Comprehensive check of AWS account prerequisites before deployment.

**Usage:**
```bash
# From kubernetes/ directory
./scripts/eks/check-aws-prerequisites.sh

# Or from scripts/eks/ directory
./check-aws-prerequisites.sh

# With specific AWS profile
./check-aws-prerequisites.sh --profile uneeq-admin
```

**Checks performed:**
1. AWS CLI configuration and credentials
2. Required IAM permissions (EKS, EC2, VPC, AutoScaling)
3. Service quotas (VPCs, EKS clusters, GPU instances, Elastic IPs)
4. Required tools (terraform, kubectl, helm)
5. Cost estimates

**Exit codes:**
- `0`: All checks passed
- `1`: One or more checks failed

### check-vpc-usage.sh

Analyzes VPC usage across AWS services to help identify which VPCs can be safely deleted.

**Usage:**
```bash
# Check all VPCs in configured region (from terraform.tfvars)
./check-vpc-usage.sh

# Check VPCs in specific region
./check-vpc-usage.sh --region us-west-2

# Check specific VPC
./check-vpc-usage.sh --vpc vpc-123456789

# With specific AWS profile
./check-vpc-usage.sh --profile uneeq-admin

# Combined options
./check-vpc-usage.sh --region us-west-2 --vpc vpc-123456789 --profile uneeq-admin
```

**Features:**
- Scans VPCs for active resources (EC2, RDS, EKS, NAT Gateways, Load Balancers)
- Identifies default VPCs (never delete these!)
- Provides deletion recommendations
- Shows detailed resource breakdown per VPC

**Output sections:**
1. Quick Summary - Resource counts per VPC
2. Detailed Breakdown - Full resource listing
3. Deletion Recommendations - Safe to delete vs. in use

## Path Configuration

Both scripts automatically detect the Terraform configuration location:

### When run from `kubernetes/` directory:
```bash
./scripts/eks/check-aws-prerequisites.sh
# Looks for: terraform/eks/terraform.tfvars
```

### When run from `kubernetes/scripts/eks/` directory:
```bash
./check-aws-prerequisites.sh
# Looks for: ../../terraform/eks/terraform.tfvars
```

## AWS Profile Configuration

All scripts support AWS profile selection via `--profile` flag:

```bash
# Use specific profile
./check-aws-prerequisites.sh --profile uneeq-admin

# Or set environment variable
export AWS_PROFILE=uneeq-admin
./check-aws-prerequisites.sh
```

## Region Configuration

**Single source of truth:** `kubernetes/terraform/eks/terraform.tfvars`

The `aws_region` variable in terraform.tfvars is used by all scripts. This ensures consistency across:
- Terraform infrastructure
- Prerequisites checks
- VPC usage analysis
- Deployment scripts

Example:
```hcl
aws_region = "us-east-2"
```

## Common Use Cases

### Before Initial Deployment

Check if your AWS account is ready:
```bash
cd kubernetes/
./scripts/eks/check-aws-prerequisites.sh
```

### VPC Limit Reached

If you hit the VPC quota limit:
```bash
# Identify unused VPCs that can be deleted
./scripts/eks/check-vpc-usage.sh

# Check specific region
./scripts/eks/check-vpc-usage.sh --region us-east-1
```

### Multiple AWS Accounts

Working with different AWS accounts/profiles:
```bash
# Check prerequisites for specific account
./scripts/eks/check-aws-prerequisites.sh --profile dev-account

# Check VPC usage in production account
./scripts/eks/check-vpc-usage.sh --profile prod-account
```

## Troubleshooting

### "AWS region not configured"

Ensure `aws_region` is set in `kubernetes/terraform/eks/terraform.tfvars`:
```hcl
aws_region = "us-east-2"
```

### "AWS credentials not configured"

Configure AWS CLI:
```bash
aws configure
# OR
aws sso login --profile your-profile
```

### Permission Errors

The scripts require these IAM permissions:
- `eks:ListClusters`, `eks:DescribeCluster`
- `ec2:Describe*` (VPCs, instances, volumes, etc.)
- `iam:ListRoles`
- `autoscaling:Describe*`
- `servicequotas:GetServiceQuota`

## Migration Notes

**October 2024 Reorganization:**

These scripts were moved from `kubernetes/scripts/` to `kubernetes/scripts/eks/` to better organize cloud-provider-specific utilities.

**Path updates:**
- Old: `../terraform/terraform.tfvars`
- New: `../../terraform/eks/terraform.tfvars`

All path references have been updated to work from both:
1. `kubernetes/` directory (via `./scripts/eks/`)
2. `kubernetes/scripts/eks/` directory (via `./`)

## See Also

- Main deployment scripts: `kubernetes/scripts/`
- Terraform configuration: `kubernetes/terraform/eks/`
- Project documentation: `kubernetes/docs/`
