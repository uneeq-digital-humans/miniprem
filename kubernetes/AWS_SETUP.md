# AWS Account Setup Guide

This guide explains how to create and configure AWS credentials for the Renny EKS deployment.

## Option 1: IAM User (Recommended for Testing)

### Step 1: Create IAM User

1. Log into AWS Console → IAM → Users → "Add users"
2. User name: `renny-eks-deployer`
3. Select: "Access key - Programmatic access"
4. Click "Next: Permissions"

### Step 2: Attach Permissions

You can either use managed policies (easier) or create a custom policy (more secure).

#### Option A: Using AWS Managed Policies (Easier)

Attach these AWS managed policies:
- `PowerUserAccess` (includes most services except IAM)
- `IAMFullAccess` (needed for creating roles)

#### Option B: Custom Policy (More Secure)

Create a custom policy with the minimum required permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSFullAccess",
      "Effect": "Allow",
      "Action": [
        "eks:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EC2RequiredPermissions",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMRequiredPermissions",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:ListRoles",
        "iam:UpdateRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:GetRolePolicy",
        "iam:PutRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListRolePolicies",
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicies",
        "iam:ListPolicyVersions",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:ListInstanceProfiles",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:ListOpenIDConnectProviders",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:PassRole",
        "iam:CreateServiceLinkedRole",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AutoScalingRequiredPermissions",
      "Effect": "Allow",
      "Action": [
        "autoscaling:CreateAutoScalingGroup",
        "autoscaling:DeleteAutoScalingGroup",
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeScalingActivities",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup",
        "autoscaling:UpdateAutoScalingGroup",
        "autoscaling:CreateOrUpdateTags",
        "autoscaling:DeleteTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudFormationAccess",
      "Effect": "Allow",
      "Action": [
        "cloudformation:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElasticLoadBalancingAccess",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "elb:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogsAccess",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DeleteLogGroup",
        "logs:DeleteLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy",
        "logs:TagLogGroup",
        "logs:UntagLogGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KMSAccess",
      "Effect": "Allow",
      "Action": [
        "kms:CreateAlias",
        "kms:CreateKey",
        "kms:DeleteAlias",
        "kms:DescribeKey",
        "kms:GetKeyPolicy",
        "kms:GetKeyRotationStatus",
        "kms:ListAliases",
        "kms:ListKeys",
        "kms:ListResourceTags",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:UpdateAlias",
        "kms:EnableKeyRotation"
      ],
      "Resource": "*"
    },
    {
      "Sid": "STSAssumeRole",
      "Effect": "Allow",
      "Action": [
        "sts:AssumeRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 3: Download Credentials

1. After creating the user, download the CSV file with Access Key ID and Secret Access Key
2. **Store these securely** - you won't be able to see the secret key again

### Step 4: Configure AWS CLI

On your local machine where you'll run the deployment:

```bash
# Option 1: Configure default profile
aws configure
# Enter:
# AWS Access Key ID: [from CSV]
# AWS Secret Access Key: [from CSV]
# Default region name: us-east-1
# Default output format: json

# Option 2: Configure named profile
aws configure --profile renny-deployer
# Enter same values

# If using named profile, export it:
export AWS_PROFILE=renny-deployer
```

### Step 5: Verify Access

Test your credentials:

```bash
# Check identity
aws sts get-caller-identity

# Should return something like:
{
    "UserId": "AIDAXXXXXXXXX",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/renny-eks-deployer"
}

# Test EC2 access
aws ec2 describe-regions --region us-east-1
```

## Option 2: IAM Role (For Production/Automation)

If running from an EC2 instance or CI/CD system:

### Create IAM Role

1. Go to IAM → Roles → Create role
2. Trusted entity type: 
   - For EC2: "AWS service" → "EC2"
   - For GitHub Actions: "Web identity" → "GitHub"
   - For Jenkins: "AWS service" → "EC2"
3. Attach the same permissions as above
4. Role name: `renny-eks-deployer-role`

### For EC2 Instance

```bash
# Attach role to EC2 instance
aws ec2 associate-iam-instance-profile \
    --instance-id i-1234567890abcdef0 \
    --iam-instance-profile Name=renny-eks-deployer-role
```

## Option 3: Using AWS SSO (For Organizations)

If your company uses AWS SSO:

```bash
# Configure SSO
aws configure sso

# Follow prompts for:
# - SSO start URL
# - SSO Region
# - Account/Role selection

# Then before running deployment:
aws sso login --profile your-sso-profile
export AWS_PROFILE=your-sso-profile
```

## Security Best Practices

### 1. Use MFA (Multi-Factor Authentication)

Add MFA to the IAM user:
1. IAM → Users → renny-eks-deployer → Security credentials
2. Assigned MFA device → Manage → Virtual MFA device

### 2. Use Temporary Credentials

Instead of long-lived access keys, use temporary credentials:

```bash
# Create a script to assume role with MFA
aws sts assume-role \
    --role-arn arn:aws:iam::123456789012:role/renny-eks-deployer-role \
    --role-session-name renny-deployment \
    --serial-number arn:aws:iam::123456789012:mfa/your-username \
    --token-code 123456  # From your MFA device
```

### 3. Restrict by IP

Add IP restrictions to the IAM policy:

```json
{
  "Condition": {
    "IpAddress": {
      "aws:SourceIp": ["203.0.113.0/24", "198.51.100.0/24"]
    }
  }
}
```

### 4. Use Permission Boundaries

Create a permission boundary to limit maximum permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": ["us-east-1"]
        }
      }
    },
    {
      "Effect": "Deny",
      "Action": [
        "iam:DeleteRole",
        "iam:DeleteRolePolicy",
        "iam:DeletePolicy"
      ],
      "Resource": "*",
      "Condition": {
        "StringNotLike": {
          "aws:PrincipalArn": "arn:aws:iam::*:role/renny-*"
        }
      }
    }
  ]
}
```

## Troubleshooting

### Common Permission Errors

1. **"User is not authorized to perform: iam:CreateRole"**
   - Add IAMFullAccess policy or specific IAM permissions

2. **"User is not authorized to perform: eks:CreateCluster"**
   - Add EKS permissions

3. **"VPC limit exceeded"**
   - Check VPC quotas in Service Quotas
   - Default is 5 VPCs per region

4. **"Instance limit exceeded"**
   - Check EC2 limits for g5.2xlarge instances
   - Request limit increase if needed

### Checking Required Service Quotas

```bash
# Check EC2 instance limits
aws service-quotas get-service-quota \
    --service-code ec2 \
    --quota-code L-DB2E81BA  # For G instances

# Check VPC limits  
aws service-quotas get-service-quota \
    --service-code vpc \
    --quota-code L-F678F1CE  # VPCs per region

# Check EKS limits
aws service-quotas get-service-quota \
    --service-code eks \
    --quota-code L-1194D53C  # Clusters per region
```

## Summary

For quick testing:
1. Create IAM user with PowerUserAccess + IAMFullAccess
2. Download credentials
3. Run `aws configure`
4. Run deployment script

For production:
1. Use the custom policy with minimum required permissions
2. Enable MFA
3. Consider using IAM roles instead of users
4. Implement permission boundaries
5. Use temporary credentials when possible