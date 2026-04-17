#!/bin/bash

# Script to check AWS account prerequisites before deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Helper function to convert float strings to integers
# AWS CLI service-quotas returns values like "5.0" instead of "5"
# This function handles both "5" and "5.0" formats safely
to_int() {
    local value="$1"
    local default="${2:-0}"

    # Handle empty or null values
    if [ -z "$value" ] || [ "$value" = "null" ] || [ "$value" = "None" ]; then
        echo "$default"
        return
    fi

    # Remove any whitespace and newlines
    value=$(echo "$value" | tr -d '[:space:]')

    # Truncate decimal portion (5.0 -> 5, 100.0 -> 100)
    # This handles both integer and float formats
    echo "$value" | cut -d'.' -f1
}

# Parse command line arguments
AWS_PROFILE_ARG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --profile PROFILE_NAME    Use specific AWS profile"
            echo "  --help, -h                Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Set profile if provided via command line
if [ -n "$AWS_PROFILE_ARG" ]; then
    export AWS_PROFILE="$AWS_PROFILE_ARG"
fi

echo "======================================"
echo "====================================="
echo "   AWS Prerequisites Check            "
echo "====================================="
echo ""

# Check if AWS_PROFILE is set and show current profile
if [ -n "$AWS_PROFILE" ]; then
    echo "Using AWS Profile: $AWS_PROFILE"
else
    echo "Using default AWS profile"
fi
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0
echo "======================================"
echo ""

CHECKS_PASSED=0
CHECKS_FAILED=0

# Function to check a condition
check() {
    local name=$1
    local command=$2
    
    echo -n "Checking $name... "
    if eval $command &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        ((CHECKS_FAILED++))
        return 1
    fi
}

# Function to check with output
check_with_output() {
    local name=$1
    shift
    local command="$@"
    
    echo -n "Checking $name... "
    OUTPUT=$(eval $command 2>&1)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC}"
        echo "  $OUTPUT"
        ((CHECKS_PASSED++))
        return 0
    else
        echo -e "${RED}✗${NC}"
        echo "  Error: $OUTPUT"
        ((CHECKS_FAILED++))
        return 1
    fi
}

echo -e "${BLUE}1. AWS CLI Configuration${NC}"
echo "========================="

# Check AWS CLI installation
check "AWS CLI installed" "command -v aws"

# Check AWS credentials
if check "AWS credentials configured" "aws sts get-caller-identity"; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    echo "  Account ID: $ACCOUNT_ID"
    echo "  Identity: $USER_ARN"
fi

# Check region from terraform.tfvars (single source of truth)
REGION=""

# Try to get from terraform vars first
if [ -f "terraform/eks/terraform.tfvars" ]; then
    REGION=$(grep "^aws_region" terraform/eks/terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
elif [ -f "../../terraform/eks/terraform.tfvars" ]; then
    REGION=$(grep "^aws_region" ../../terraform/eks/terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
fi

# Validate region is set
if [ -z "$REGION" ]; then
    echo -e "AWS region: ${RED}Not configured${NC}"
    echo -e "${RED}Error: aws_region must be set in terraform.tfvars${NC}"
    echo "Please add: aws_region = \"us-east-2\"  (or your preferred region)"
    echo "terraform.tfvars should be the single source of truth for region configuration."
    exit 1
else
    echo -e "AWS region: ${GREEN}$REGION${NC} (from terraform.tfvars)"
fi

echo ""
echo -e "${BLUE}2. Required Permissions${NC}"
echo "========================="

# Check EKS permissions
check "EKS permissions" "aws eks list-clusters --region $REGION"

# Check EC2 permissions
check "EC2 permissions" "aws ec2 describe-instances --region $REGION --max-results 5"

# Check IAM permissions
check "IAM permissions" "aws iam list-roles --max-items 1"

# Check VPC permissions
check "VPC permissions" "aws ec2 describe-vpcs --region $REGION --max-results 5"

# Check AutoScaling permissions
check "AutoScaling permissions" "aws autoscaling describe-auto-scaling-groups --region $REGION"

echo ""
echo -e "${BLUE}3. Service Quotas${NC}"
echo "========================="

# Check VPC quota
echo -n "Checking VPC quota... "
CURRENT_VPCS_RAW=$(aws ec2 describe-vpcs --region $REGION --query 'length(Vpcs)' --output text 2>/dev/null || echo "0")
VPC_LIMIT_RAW=$(aws service-quotas get-service-quota --service-code vpc --quota-code L-F678F1CE --region $REGION --query 'Quota.Value' --output text 2>/dev/null || echo "5")
CURRENT_VPCS=$(to_int "$CURRENT_VPCS_RAW" 0)
VPC_LIMIT=$(to_int "$VPC_LIMIT_RAW" 5)
if [ "$CURRENT_VPCS" -lt "$VPC_LIMIT" ]; then
    echo -e "${GREEN}✓${NC} ($CURRENT_VPCS/$VPC_LIMIT used)"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗${NC} ($CURRENT_VPCS/$VPC_LIMIT used - no space available)"
    ((CHECKS_FAILED++))
fi

# Check EKS cluster quota
echo -n "Checking EKS cluster quota... "
CURRENT_CLUSTERS_RAW=$(aws eks list-clusters --region $REGION --query 'length(clusters)' --output text 2>/dev/null || echo "0")
EKS_LIMIT_RAW=$(aws service-quotas get-service-quota --service-code eks --quota-code L-1194D53C --region $REGION --query 'Quota.Value' --output text 2>/dev/null || echo "100")
CURRENT_CLUSTERS=$(to_int "$CURRENT_CLUSTERS_RAW" 0)
EKS_LIMIT=$(to_int "$EKS_LIMIT_RAW" 100)
if [ "$CURRENT_CLUSTERS" -lt "$EKS_LIMIT" ]; then
    echo -e "${GREEN}✓${NC} ($CURRENT_CLUSTERS/$EKS_LIMIT used)"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗${NC} ($CURRENT_CLUSTERS/$EKS_LIMIT used)"
    ((CHECKS_FAILED++))
fi

# Check EC2 instance quotas for g5.4xlarge
echo -n "Checking G5 instance quota... "
G5_LIMIT_RAW=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-DB2E81BA --region $REGION --query 'Quota.Value' --output text 2>/dev/null || echo "64")
G5_LIMIT=$(to_int "$G5_LIMIT_RAW" 64)
REQUIRED_G5=10  # 10 for Renny
if [ "$G5_LIMIT" -ge "$REQUIRED_G5" ]; then
    echo -e "${GREEN}✓${NC} ($G5_LIMIT vCPUs available, need $REQUIRED_G5 minimum)"
    ((CHECKS_PASSED++))
else
    echo -e "${YELLOW}⚠${NC} ($G5_LIMIT vCPUs available, need $REQUIRED_G5 minimum)"
    echo "  You may need to request a quota increase for G5 instances"
    ((CHECKS_FAILED++))
fi

# Check Elastic IP quota
echo -n "Checking Elastic IP quota... "
CURRENT_EIPS_RAW=$(aws ec2 describe-addresses --region $REGION --query 'length(Addresses)' --output text 2>/dev/null || echo "0")
EIP_LIMIT_RAW=$(aws service-quotas get-service-quota --service-code ec2 --quota-code L-0263D0A3 --region $REGION --query 'Quota.Value' --output text 2>/dev/null || echo "5")
CURRENT_EIPS=$(to_int "$CURRENT_EIPS_RAW" 0)
EIP_LIMIT=$(to_int "$EIP_LIMIT_RAW" 5)
REQUIRED_EIPS=3  # For NAT gateways
AVAILABLE_EIPS=$((EIP_LIMIT - CURRENT_EIPS))
if [ $AVAILABLE_EIPS -ge $REQUIRED_EIPS ]; then
    echo -e "${GREEN}✓${NC} ($CURRENT_EIPS/$EIP_LIMIT used, $AVAILABLE_EIPS available)"
    ((CHECKS_PASSED++))
else
    echo -e "${RED}✗${NC} ($CURRENT_EIPS/$EIP_LIMIT used, need $REQUIRED_EIPS more)"
    ((CHECKS_FAILED++))
fi

echo ""
echo -e "${BLUE}4. Required Tools${NC}"
echo "========================="

# Check for required command-line tools
check "terraform installed" "command -v terraform"
check "kubectl installed" "command -v kubectl"
check "helm installed" "command -v helm"

# Check terraform version
if command -v terraform &>/dev/null; then
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
    if [ -n "$TF_VERSION" ]; then
        echo "  Terraform version: $TF_VERSION"
    fi
fi

# Check helm version
if command -v helm &>/dev/null; then
    HELM_VERSION=$(helm version --short 2>/dev/null | cut -d':' -f2 | tr -d ' v')
    if [ -n "$HELM_VERSION" ]; then
        echo "  Helm version: $HELM_VERSION"
    fi
fi

# Check AWS CLI version (critical for kubectl compatibility)
if command -v aws &>/dev/null; then
    AWS_VERSION=$(aws --version 2>/dev/null | cut -d'/' -f2 | cut -d' ' -f1)
    if [ -n "$AWS_VERSION" ]; then
        echo "  AWS CLI version: $AWS_VERSION"
        
        # Check if version is too old (< 2.3.0) - causes kubectl compatibility issues
        AWS_MAJOR=$(echo "$AWS_VERSION" | cut -d'.' -f1)
        AWS_MINOR=$(echo "$AWS_VERSION" | cut -d'.' -f2)
        
        if [ "$AWS_MAJOR" -lt 2 ] || ([ "$AWS_MAJOR" -eq 2 ] && [ "$AWS_MINOR" -lt 3 ]); then
            echo -e "    ${YELLOW}⚠️  AWS CLI version is old and may cause kubectl authentication issues${NC}"
            echo "    Recommendation: Update to AWS CLI v2.3.0 or later"
            echo "    Update command: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            echo "    This deployment will auto-fix any kubectl compatibility issues"
            ((CHECKS_FAILED++))
        fi
    fi
fi

echo ""
echo -e "${BLUE}5. Estimated Costs${NC}"
echo "========================="

echo "Deployment will create:"
echo "  - 1 EKS cluster"
echo "  - 1 VPC with 3 NAT gateways"
echo "  - 10 g5.4xlarge instances (Renny)"
echo "  - 2 t3.large instances (Control plane)"
echo ""
echo -e "${YELLOW}Estimated costs:${NC}"
echo "  - Hourly: ~\$15-20/hour"
echo "  - Daily: ~\$360-480/day"
echo "  - Monthly: ~\$10,800-14,400/month"
echo ""
echo -e "${YELLOW}⚠️  Remember to run ./scripts/destroy.sh when done testing!${NC}"

echo ""
echo "======================================"
echo "              Summary                 "
echo "======================================"

if [ $CHECKS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed ($CHECKS_PASSED/$((CHECKS_PASSED + CHECKS_FAILED)))${NC}"
    echo ""
    echo "Your AWS account is ready for deployment!"
    echo "Next steps:"
    echo "  1. Place your renny-chart.tgz in the kubernetes/ directory"
    echo "  2. Create terraform/eks/terraform.tfvars with your credentials"
    echo "  3. Run ./scripts/deploy.sh"
else
    echo -e "${RED}❌ Some checks failed ($CHECKS_FAILED failed, $CHECKS_PASSED passed)${NC}"
    echo ""
    echo "Please address the issues above before proceeding."
    echo ""
    echo "Common fixes:"
    echo "  - Configure AWS credentials: aws configure"
    echo "  - Request quota increases: AWS Console → Service Quotas"
    echo "  - Install missing tools: terraform, kubectl, helm"
    echo "  - Ensure IAM user has required permissions (see AWS_SETUP.md)"
fi

echo ""