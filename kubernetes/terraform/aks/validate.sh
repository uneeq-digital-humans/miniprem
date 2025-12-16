#!/usr/bin/env bash
#
# AKS Terraform Validation Script
# Validates prerequisites and configuration before deployment

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

echo "================================================================================"
echo "Azure AKS Terraform Validation"
echo "================================================================================"
echo

# Function to print colored output
print_status() {
    local status=$1
    local message=$2

    case $status in
        "ok")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "error")
            echo -e "${RED}✗${NC} $message"
            ((ERRORS++))
            ;;
        "warning")
            echo -e "${YELLOW}⚠${NC} $message"
            ((WARNINGS++))
            ;;
        "info")
            echo -e "  $message"
            ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "Checking Prerequisites..."
echo

# Check Azure CLI
if command_exists az; then
    AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null || echo "unknown")
    print_status "ok" "Azure CLI installed (version: $AZ_VERSION)"

    # Check Azure login
    if az account show >/dev/null 2>&1; then
        SUBSCRIPTION=$(az account show --query name -o tsv)
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        print_status "ok" "Logged into Azure (subscription: $SUBSCRIPTION)"
        print_status "info" "  Subscription ID: $SUBSCRIPTION_ID"
    else
        print_status "error" "Not logged into Azure. Run: az login"
    fi
else
    print_status "error" "Azure CLI not installed. Run: brew install azure-cli"
fi

# Check Terraform
if command_exists terraform; then
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
    print_status "ok" "Terraform installed (version: $TF_VERSION)"

    # Check Terraform version >= 1.0
    if [[ "$TF_VERSION" != "unknown" ]]; then
        MAJOR_VERSION=$(echo "$TF_VERSION" | cut -d. -f1)
        if [[ $MAJOR_VERSION -ge 1 ]]; then
            print_status "ok" "Terraform version >= 1.0"
        else
            print_status "error" "Terraform version must be >= 1.0 (current: $TF_VERSION)"
        fi
    fi
else
    print_status "error" "Terraform not installed. Run: brew install terraform"
fi

# Check kubectl
if command_exists kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | head -1 || echo "unknown")
    print_status "ok" "kubectl installed ($KUBECTL_VERSION)"
else
    print_status "warning" "kubectl not installed. Run: brew install kubectl"
    print_status "info" "  (Required for cluster management after deployment)"
fi

# Check Helm
if command_exists helm; then
    HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
    print_status "ok" "Helm installed ($HELM_VERSION)"
else
    print_status "warning" "Helm not installed. Run: brew install helm"
    print_status "info" "  (Required for GPU Operator installation)"
fi

echo
echo "Checking Configuration Files..."
echo

# Check if terraform.tfvars exists
if [[ -f "terraform.tfvars" ]]; then
    print_status "ok" "terraform.tfvars exists"

    # Check required variables
    if grep -q 'azure_subscription_id.*=.*"YOUR_AZURE_SUBSCRIPTION_ID"' terraform.tfvars; then
        print_status "error" "azure_subscription_id not configured in terraform.tfvars"
    else
        print_status "ok" "azure_subscription_id configured"
    fi

    if grep -q 'dhop_tenant_id.*=' terraform.tfvars; then
        print_status "ok" "dhop_tenant_id configured"
    else
        print_status "warning" "dhop_tenant_id not found in terraform.tfvars"
    fi

    if grep -q 'harbor_username.*=' terraform.tfvars; then
        print_status "ok" "harbor_username configured"
    else
        print_status "warning" "harbor_username not found in terraform.tfvars"
    fi
else
    print_status "error" "terraform.tfvars not found"
    print_status "info" "  Copy from terraform.tfvars and update values"
fi

# Check core Terraform files
REQUIRED_FILES=("main.tf" "aks.tf" "vnet.tf" "node-pools.tf" "variables.tf" "outputs.tf")
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        print_status "ok" "$file exists"
    else
        print_status "error" "$file missing"
    fi
done

echo
echo "Checking Terraform Configuration..."
echo

# Check if Terraform is initialized
if [[ -d ".terraform" ]]; then
    print_status "ok" "Terraform initialized (.terraform directory exists)"
else
    print_status "warning" "Terraform not initialized. Run: terraform init"
fi

# Try terraform validate (will fail if not initialized or misconfigured)
if command_exists terraform && [[ -d ".terraform" ]]; then
    if terraform validate >/dev/null 2>&1; then
        print_status "ok" "Terraform configuration valid"
    else
        print_status "warning" "Terraform validation failed (may require Azure credentials)"
        print_status "info" "  This is expected on macOS due to provider security restrictions"
    fi
fi

echo
echo "Checking Azure Resources..."
echo

# Check if resource group exists
if command_exists az && az account show >/dev/null 2>&1; then
    RG_NAME="renny-kubernetes"
    if grep -q "resource_group_name" terraform.tfvars 2>/dev/null; then
        RG_NAME=$(grep "resource_group_name" terraform.tfvars | cut -d'"' -f2)
    fi

    if az group show --name "$RG_NAME" >/dev/null 2>&1; then
        print_status "warning" "Resource group '$RG_NAME' already exists"
        print_status "info" "  Terraform will use existing resource group"
    else
        print_status "ok" "Resource group '$RG_NAME' does not exist (will be created)"
    fi
fi

echo
echo "Checking Quotas and Limits..."
echo

if command_exists az && az account show >/dev/null 2>&1; then
    REGION="eastus"
    if grep -q "azure_region" terraform.tfvars 2>/dev/null; then
        REGION=$(grep "azure_region" terraform.tfvars | cut -d'"' -f2 | head -1)
    fi

    print_status "info" "Region: $REGION"

    # Check if NC-series VMs are available in region
    if az vm list-skus --location "$REGION" --query "[?name=='Standard_NC16as_T4_v3']" -o tsv 2>/dev/null | grep -q "NC16as_T4_v3"; then
        print_status "ok" "Standard_NC16as_T4_v3 available in $REGION"
    else
        print_status "warning" "Unable to verify Standard_NC16as_T4_v3 availability in $REGION"
        print_status "info" "  Check: az vm list-skus --location $REGION --query \"[?family=='NCasT4_v3']\" -o table"
    fi
fi

echo
echo "================================================================================"
echo "Validation Summary"
echo "================================================================================"
echo

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo
    echo "Ready to deploy:"
    echo "  terraform plan -var-file=terraform.tfvars"
    echo "  terraform apply -var-file=terraform.tfvars"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Validation passed with $WARNINGS warning(s)${NC}"
    echo
    echo "You can proceed with deployment, but review warnings above."
    echo
    echo "Ready to deploy:"
    echo "  terraform plan -var-file=terraform.tfvars"
    echo "  terraform apply -var-file=terraform.tfvars"
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo
    echo "Please fix the errors above before deploying."
    exit 1
fi
