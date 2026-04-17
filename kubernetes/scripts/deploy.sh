#!/bin/bash

################################################################################
# MiniPrem Multi-Cloud Kubernetes Deployment Router
#
# This script provides a unified entry point for deploying MiniPrem to multiple
# cloud platforms and on-premises environments. It handles:
#   - Interactive platform selection (AWS, Azure, GCP, NVIDIA CNS)
#   - CLI tool validation with OS-specific install instructions
#   - Authentication verification using environment variables and CLI
#   - Delegation to platform-specific deployment scripts
#
# Usage:
#   ./deploy.sh
#
# The script will prompt for platform selection and guide you through
# prerequisites before delegating to the appropriate platform-specific script.
#
# Supported Platforms:
#   - AWS EKS (Elastic Kubernetes Service)
#   - Azure AKS (Azure Kubernetes Service)
#   - Google Cloud GKE (Google Kubernetes Engine)
#   - NVIDIA CNS (Cloud Native Stack) - On-premises deployment
################################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# Output Functions
################################################################################

print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

info() {
    print_color "$BLUE" "ℹ️  $*"
}

success() {
    print_color "$GREEN" "✅ $*"
}

warning() {
    print_color "$YELLOW" "⚠️  $*"
}

error() {
    print_color "$RED" "❌ $*"
}

################################################################################
# Platform Selection
################################################################################

select_platform() {
    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║         MiniPrem Multi-Cloud Kubernetes Deployment            ║
╚═══════════════════════════════════════════════════════════════╝
"

    echo "Select your deployment platform:"
    echo ""
    print_color "$BLUE" "  Cloud Managed Kubernetes:"
    echo "    1) Amazon Web Services (AWS EKS)"
    echo "    2) Microsoft Azure (AKS)"
    echo "    3) Google Cloud Platform (GKE)"
    echo ""
    print_color "$BLUE" "  On-Premises:"
    echo "    4) NVIDIA Cloud Native Stack (CNS)"
    echo ""
    echo -n "Enter your choice (1-4): "

    read -r choice

    case $choice in
        1)
            PLATFORM="aws"
            PLATFORM_NAME="Amazon Web Services (AWS EKS)"
            CLI_TOOL="aws"
            DEPLOYMENT_SCRIPT="aws/deploy.sh"
            ;;
        2)
            PLATFORM="azure"
            PLATFORM_NAME="Microsoft Azure (AKS)"
            CLI_TOOL="az"
            DEPLOYMENT_SCRIPT="azure/deploy.sh"
            ;;
        3)
            PLATFORM="gcp"
            PLATFORM_NAME="Google Cloud Platform (GKE)"
            CLI_TOOL="gcloud"
            DEPLOYMENT_SCRIPT="gke/deploy.sh"
            ;;
        4)
            PLATFORM="cns"
            PLATFORM_NAME="NVIDIA Cloud Native Stack (CNS)"
            CLI_TOOL="kubectl"
            DEPLOYMENT_SCRIPT="cns/deploy.sh"
            select_cns_deployment_type
            ;;
        *)
            error "Invalid choice. Please run the script again and select 1-4."
            exit 1
            ;;
    esac

    info "Selected platform: $PLATFORM_NAME"
    echo ""
}

################################################################################
# CNS Deployment Type Selection
################################################################################

select_cns_deployment_type() {
    echo ""
    print_color "$BOLD" "CNS Deployment Options:"
    echo ""
    echo "  1) Local Install (install CNS on this machine)"
    echo "  2) Remote Deploy (deploy to server over LAN via SSH/Ansible)"
    echo ""
    echo -n "Enter your choice (1-2): "

    read -r cns_choice

    case $cns_choice in
        1)
            CNS_DEPLOY_TYPE="local"
            DEPLOYMENT_SCRIPT="cns/deploy-local.sh"
            info "Selected: Local CNS installation"
            select_cns_kubernetes_type
            ;;
        2)
            CNS_DEPLOY_TYPE="remote"
            DEPLOYMENT_SCRIPT="cns/deploy-remote.sh"
            info "Selected: Remote CNS deployment"
            prompt_remote_target
            select_cns_kubernetes_type
            ;;
        *)
            error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

select_cns_kubernetes_type() {
    echo ""
    print_color "$BOLD" "Kubernetes Distribution:"
    echo ""
    echo "  1) MicroK8s (recommended for single-node, simpler setup)"
    echo "  2) kubeadm (standard Kubernetes, more flexible)"
    echo ""
    echo -n "Enter your choice (1-2): "

    read -r k8s_choice

    case $k8s_choice in
        1)
            CNS_K8S_TYPE="microk8s"
            export CNS_K8S_TYPE
            info "Selected: MicroK8s"
            ;;
        2)
            CNS_K8S_TYPE="kubeadm"
            export CNS_K8S_TYPE
            info "Selected: kubeadm"
            ;;
        *)
            error "Invalid choice. Please run the script again."
            exit 1
            ;;
    esac
}

prompt_remote_target() {
    echo ""
    print_color "$BOLD" "Remote Server Configuration:"
    echo ""
    echo -n "Enter target server IP or hostname: "
    read -r CNS_REMOTE_HOST

    echo -n "Enter SSH username [ubuntu]: "
    read -r CNS_REMOTE_USER
    CNS_REMOTE_USER=${CNS_REMOTE_USER:-ubuntu}

    echo -n "Enter SSH key path [~/.ssh/id_rsa]: "
    read -r CNS_SSH_KEY
    CNS_SSH_KEY=${CNS_SSH_KEY:-~/.ssh/id_rsa}

    export CNS_REMOTE_HOST CNS_REMOTE_USER CNS_SSH_KEY

    info "Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
}

################################################################################
# CLI Tool Validation
################################################################################

get_os_type() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            echo "linux"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

show_install_instructions() {
    local tool=$1
    local os_type=$(get_os_type)

    error "Required CLI tool '$tool' is not installed."
    echo ""
    print_color "$BOLD" "Installation Instructions:"
    echo ""

    case $tool in
        aws)
            case $os_type in
                macos)
                    echo "macOS:"
                    echo "  1. Using Homebrew (recommended):"
                    echo "     brew install awscli"
                    echo ""
                    echo "  2. Using pip:"
                    echo "     pip3 install awscli"
                    echo ""
                    echo "  3. Using installer:"
                    echo "     curl \"https://awscli.amazonaws.com/AWSCLIV2.pkg\" -o \"AWSCLIV2.pkg\""
                    echo "     sudo installer -pkg AWSCLIV2.pkg -target /"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  1. Using package manager:"
                    echo "     Ubuntu/Debian: sudo apt-get install awscli"
                    echo "     CentOS/RHEL: sudo yum install awscli"
                    echo ""
                    echo "  2. Using pip:"
                    echo "     pip3 install awscli"
                    echo ""
                    echo "  3. Using installer:"
                    echo "     curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\""
                    echo "     unzip awscliv2.zip"
                    echo "     sudo ./aws/install"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  1. Download and run the AWS CLI MSI installer:"
                    echo "     https://awscli.amazonaws.com/AWSCLIV2.msi"
                    echo ""
                    echo "  2. Using Chocolatey:"
                    echo "     choco install awscli"
                    ;;
            esac
            echo ""
            echo "Documentation: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
            ;;

        az)
            case $os_type in
                macos)
                    echo "macOS:"
                    echo "  Using Homebrew:"
                    echo "     brew update && brew install azure-cli"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  1. Download and run the Azure CLI MSI installer:"
                    echo "     https://aka.ms/installazurecliwindows"
                    echo ""
                    echo "  2. Using Chocolatey:"
                    echo "     choco install azure-cli"
                    ;;
            esac
            echo ""
            echo "Documentation: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            ;;

        gcloud)
            case $os_type in
                macos)
                    echo "macOS:"
                    echo "  1. Download and run the installer:"
                    echo "     https://cloud.google.com/sdk/docs/install#mac"
                    echo ""
                    echo "  2. Using Homebrew:"
                    echo "     brew install --cask google-cloud-sdk"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  curl https://sdk.cloud.google.com | bash"
                    echo "  exec -l \$SHELL"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  1. Download and run the Google Cloud SDK installer:"
                    echo "     https://cloud.google.com/sdk/docs/install#windows"
                    ;;
            esac
            echo ""
            echo "Documentation: https://cloud.google.com/sdk/docs/install"
            ;;

        kubectl)
            case $os_type in
                macos)
                    echo "macOS:"
                    echo "  Using Homebrew:"
                    echo "     brew install kubectl"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\""
                    echo "  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  choco install kubernetes-cli"
                    ;;
            esac
            echo ""
            echo "Documentation: https://kubernetes.io/docs/tasks/tools/"
            ;;

        ssh)
            case $os_type in
                macos)
                    echo "macOS: SSH is pre-installed"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  Ubuntu/Debian: sudo apt-get install openssh-client"
                    echo "  CentOS/RHEL: sudo yum install openssh-clients"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  Enable OpenSSH in Windows Settings > Apps > Optional Features"
                    ;;
            esac
            ;;

        ansible)
            case $os_type in
                macos)
                    echo "macOS:"
                    echo "  brew install ansible"
                    ;;
                linux)
                    echo "Linux:"
                    echo "  Ubuntu/Debian: sudo apt-get install ansible"
                    echo "  CentOS/RHEL: sudo yum install ansible"
                    echo "  pip: pip3 install ansible"
                    ;;
                windows)
                    echo "Windows:"
                    echo "  Use WSL2 and install Ansible in the Linux environment"
                    ;;
            esac
            echo ""
            echo "Documentation: https://docs.ansible.com/ansible/latest/installation_guide/"
            ;;
    esac

    echo ""
    error "Please install the required CLI tool and run this script again."
    exit 1
}

check_cli_tool() {
    local tool=$1

    info "Checking for $tool CLI..."

    if ! command -v "$tool" &> /dev/null; then
        show_install_instructions "$tool"
    fi

    success "$tool CLI is installed"

    # Show version
    case $tool in
        aws)
            aws --version 2>&1 | head -1
            ;;
        az)
            az --version 2>&1 | head -1
            ;;
        gcloud)
            gcloud --version 2>&1 | head -1
            ;;
        kubectl)
            kubectl version --client 2>&1 | head -1
            ;;
        ssh)
            ssh -V 2>&1
            ;;
        ansible)
            ansible --version 2>&1 | head -1
            ;;
    esac

    echo ""
}

################################################################################
# CNS-Specific Tool Validation
################################################################################

check_cns_tools() {
    info "Checking CNS deployment prerequisites..."

    # For remote deployments, check SSH
    if [[ "${CNS_DEPLOY_TYPE:-local}" == "remote" ]]; then
        check_cli_tool "ssh"

        # Verify SSH key exists
        local ssh_key="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
        ssh_key=$(eval echo "$ssh_key")
        if [[ ! -f "$ssh_key" ]]; then
            error "SSH key not found: $ssh_key"
            echo "Please specify a valid SSH key path."
            exit 1
        fi
        success "SSH key found: $ssh_key"

        # Check for Ansible (optional but recommended for remote)
        if command -v ansible &> /dev/null; then
            success "Ansible is available (recommended for remote deployments)"
            ansible --version 2>&1 | head -1
        else
            warning "Ansible not installed. SSH-only deployment will be used."
            echo "  For more robust deployments, consider installing Ansible."
        fi
    fi

    # Check for NVIDIA drivers (local install)
    if [[ "${CNS_DEPLOY_TYPE:-local}" == "local" ]]; then
        if command -v nvidia-smi &> /dev/null; then
            success "NVIDIA drivers detected"
            nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>/dev/null | head -1
        else
            warning "NVIDIA drivers not detected locally."
            echo "  CNS will install drivers during deployment."
        fi
    fi

    # Check for MicroK8s or kubeadm based on selection
    if [[ "${CNS_K8S_TYPE:-microk8s}" == "microk8s" ]]; then
        if command -v microk8s &> /dev/null; then
            success "MicroK8s already installed"
            microk8s version 2>/dev/null || true
        else
            info "MicroK8s will be installed during deployment"
        fi
    else
        if command -v kubeadm &> /dev/null; then
            success "kubeadm already installed"
            kubeadm version 2>/dev/null | head -1 || true
        else
            info "kubeadm will be installed during deployment"
        fi
    fi

    echo ""
}

################################################################################
# Authentication Validation
################################################################################

show_auth_instructions() {
    local platform=$1

    error "Authentication required for $PLATFORM_NAME"
    echo ""
    print_color "$BOLD" "Authentication Instructions:"
    echo ""

    case $platform in
        aws)
            echo "AWS Authentication Options:"
            echo ""
            echo "Option 1: AWS SSO (Recommended for organizations)"
            echo "  aws sso login --profile <your-profile-name>"
            echo "  export AWS_PROFILE=<your-profile-name>"
            echo ""
            echo "Option 2: AWS Configure"
            echo "  aws configure"
            echo "  # Enter your Access Key ID and Secret Access Key"
            echo ""
            echo "Option 3: Environment Variables"
            echo "  export AWS_ACCESS_KEY_ID=<your-key-id>"
            echo "  export AWS_SECRET_ACCESS_KEY=<your-secret-key>"
            echo "  export AWS_DEFAULT_REGION=<your-region>"
            echo ""
            echo "To verify authentication:"
            echo "  aws sts get-caller-identity"
            echo ""
            echo "Documentation: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-authentication.html"
            ;;

        azure)
            echo "Azure Authentication Options:"
            echo ""
            echo "Option 1: Interactive Login (Recommended)"
            echo "  az login"
            echo ""
            echo "Option 2: Service Principal (Automated deployments)"
            echo "  az login --service-principal \\"
            echo "    --username <client-id> \\"
            echo "    --password <client-secret> \\"
            echo "    --tenant <tenant-id>"
            echo ""
            echo "Option 3: Environment Variables"
            echo "  export AZURE_SUBSCRIPTION_ID=<subscription-id>"
            echo "  export AZURE_TENANT_ID=<tenant-id>"
            echo "  export AZURE_CLIENT_ID=<client-id>"
            echo "  export AZURE_CLIENT_SECRET=<client-secret>"
            echo ""
            echo "To verify authentication:"
            echo "  az account show"
            echo ""
            echo "Documentation: https://docs.microsoft.com/en-us/cli/azure/authenticate-azure-cli"
            ;;

        gcp)
            echo "Google Cloud Authentication Options:"
            echo ""
            echo "Option 1: Interactive Login (Recommended)"
            echo "  gcloud auth login"
            echo "  gcloud config set project <project-id>"
            echo ""
            echo "Option 2: Service Account (Automated deployments)"
            echo "  gcloud auth activate-service-account --key-file=<key-file>"
            echo ""
            echo "Option 3: Environment Variables"
            echo "  export GOOGLE_CLOUD_PROJECT=<project-id>"
            echo "  export GOOGLE_APPLICATION_CREDENTIALS=<path-to-key-file>"
            echo ""
            echo "To verify authentication:"
            echo "  gcloud auth list"
            echo "  gcloud config get-value project"
            echo ""
            echo "Documentation: https://cloud.google.com/sdk/docs/authorizing"
            ;;

        cns)
            echo "CNS On-Premises Deployment Requirements:"
            echo ""
            if [[ "${CNS_DEPLOY_TYPE:-local}" == "remote" ]]; then
                echo "Remote Deployment:"
                echo "  1. SSH access to target server"
                echo "     ssh $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
                echo ""
                echo "  2. Ensure your SSH key is authorized on the target"
                echo "     ssh-copy-id -i $CNS_SSH_KEY $CNS_REMOTE_USER@$CNS_REMOTE_HOST"
                echo ""
                echo "  3. Target server should have:"
                echo "     - Ubuntu 22.04+ or RHEL 8.7+"
                echo "     - NVIDIA GPU(s)"
                echo "     - Internet access for package downloads"
            else
                echo "Local Deployment:"
                echo "  1. Ensure you have sudo access"
                echo "     sudo -v"
                echo ""
                echo "  2. System requirements:"
                echo "     - Ubuntu 22.04+ or RHEL 8.7+"
                echo "     - NVIDIA GPU(s)"
                echo "     - 2+ CPU cores, 8GB+ RAM recommended"
                echo "     - Internet access for package downloads"
            fi
            echo ""
            echo "Documentation: https://github.com/NVIDIA/cloud-native-stack"
            ;;
    esac

    echo ""
    error "Please authenticate and run this script again."
    exit 1
}

check_authentication() {
    info "Checking authentication for $PLATFORM_NAME..."

    case $PLATFORM in
        aws)
            # Check for AWS_PROFILE environment variable
            if [[ -n "${AWS_PROFILE:-}" ]]; then
                info "Using AWS_PROFILE: $AWS_PROFILE"
            fi

            # Verify authentication
            if ! aws sts get-caller-identity &> /dev/null; then
                show_auth_instructions "aws"
            fi

            # Show authenticated identity
            local identity=$(aws sts get-caller-identity --output json 2>/dev/null)
            local account=$(echo "$identity" | grep -o '"Account": "[^"]*"' | cut -d'"' -f4)
            local arn=$(echo "$identity" | grep -o '"Arn": "[^"]*"' | cut -d'"' -f4)

            success "Authenticated to AWS"
            echo "  Account: $account"
            echo "  Identity: $arn"
            ;;

        azure)
            # Check for AZURE_SUBSCRIPTION_ID environment variable
            if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
                info "Using AZURE_SUBSCRIPTION_ID: $AZURE_SUBSCRIPTION_ID"
            fi

            # Verify authentication
            if ! az account show &> /dev/null; then
                show_auth_instructions "azure"
            fi

            # Show authenticated identity
            local account_info=$(az account show --output json 2>/dev/null)
            local subscription_name=$(echo "$account_info" | grep -o '"name": "[^"]*"' | head -1 | cut -d'"' -f4)
            local subscription_id=$(echo "$account_info" | grep -o '"id": "[^"]*"' | head -1 | cut -d'"' -f4)
            local user=$(echo "$account_info" | grep -o '"name": "[^"]*"' | tail -1 | cut -d'"' -f4)

            success "Authenticated to Azure"
            echo "  Subscription: $subscription_name ($subscription_id)"
            echo "  User: $user"
            ;;

        gcp)
            # Check for GOOGLE_CLOUD_PROJECT environment variable
            if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
                info "Using GOOGLE_CLOUD_PROJECT: $GOOGLE_CLOUD_PROJECT"
            fi

            # Verify authentication
            if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &> /dev/null; then
                show_auth_instructions "gcp"
            fi

            # Show authenticated identity
            local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
            local project=$(gcloud config get-value project 2>/dev/null)

            if [[ -z "$active_account" ]]; then
                show_auth_instructions "gcp"
            fi

            success "Authenticated to Google Cloud"
            echo "  Account: $active_account"
            if [[ -n "$project" ]]; then
                echo "  Project: $project"
            else
                warning "No default project set. You may need to run: gcloud config set project <project-id>"
            fi
            ;;

        cns)
            # CNS authentication depends on deployment type
            if [[ "${CNS_DEPLOY_TYPE:-local}" == "remote" ]]; then
                info "Testing SSH connectivity to $CNS_REMOTE_HOST..."

                local ssh_key="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
                ssh_key=$(eval echo "$ssh_key")

                if ssh -i "$ssh_key" -o ConnectTimeout=10 -o BatchMode=yes \
                    "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" "echo 'SSH connection successful'" 2>/dev/null; then
                    success "SSH connection verified"
                    echo "  Target: $CNS_REMOTE_USER@$CNS_REMOTE_HOST"

                    # Check remote NVIDIA GPU
                    info "Checking remote NVIDIA GPU..."
                    if ssh -i "$ssh_key" "$CNS_REMOTE_USER@$CNS_REMOTE_HOST" \
                        "nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null || echo 'No GPU detected'" | head -1; then
                        :
                    fi
                else
                    show_auth_instructions "cns"
                fi
            else
                # Local deployment - check sudo access
                info "Checking local sudo access..."
                if sudo -n true 2>/dev/null; then
                    success "Sudo access verified (passwordless)"
                elif sudo -v 2>/dev/null; then
                    success "Sudo access verified"
                else
                    error "Sudo access required for local CNS installation"
                    show_auth_instructions "cns"
                fi
            fi
            ;;
    esac

    echo ""
}

################################################################################
# Deployment Delegation
################################################################################

delegate_to_platform_script() {
    local script_path="$SCRIPT_DIR/$DEPLOYMENT_SCRIPT"

    info "Delegating to platform-specific script: $DEPLOYMENT_SCRIPT"

    # Check if platform-specific script exists
    if [[ ! -f "$script_path" ]]; then
        error "Platform-specific deployment script not found: $script_path"
        echo ""

        case "$PLATFORM" in
            gcp)
                warning "GCP deployment support is planned but not yet implemented."
                echo ""
                echo "To track progress or contribute:"
                echo "  - Check for open issues in the repository"
                echo "  - See documentation for AWS/Azure deployment as reference"
                exit 1
                ;;
            cns)
                warning "CNS deployment scripts are being developed."
                echo ""
                echo "CNS deployment configuration:"
                echo "  - Deployment type: ${CNS_DEPLOY_TYPE:-local}"
                echo "  - Kubernetes type: ${CNS_K8S_TYPE:-microk8s}"
                if [[ "${CNS_DEPLOY_TYPE:-local}" == "remote" ]]; then
                    echo "  - Target host: ${CNS_REMOTE_USER:-ubuntu}@${CNS_REMOTE_HOST:-}"
                fi
                echo ""
                echo "For manual CNS setup, see:"
                echo "  - https://github.com/NVIDIA/cloud-native-stack"
                echo "  - kubernetes/CNS_SETUP.md (coming soon)"
                exit 1
                ;;
            *)
                error "Expected script location: $script_path"
                echo "Please ensure the deployment scripts are properly installed."
                exit 1
                ;;
        esac
    fi

    # Make sure script is executable
    chmod +x "$script_path"

    # Export CNS-specific variables for the deployment script
    if [[ "$PLATFORM" == "cns" ]]; then
        export CNS_DEPLOY_TYPE="${CNS_DEPLOY_TYPE:-local}"
        export CNS_K8S_TYPE="${CNS_K8S_TYPE:-microk8s}"
        export CNS_REMOTE_HOST="${CNS_REMOTE_HOST:-}"
        export CNS_REMOTE_USER="${CNS_REMOTE_USER:-ubuntu}"
        export CNS_SSH_KEY="${CNS_SSH_KEY:-~/.ssh/id_rsa}"
    fi

    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║              Starting $PLATFORM_NAME Deployment                ║
╚═══════════════════════════════════════════════════════════════╝
"

    # Execute platform-specific script with all original arguments
    exec "$script_path" "$@"
}

################################################################################
# Main Execution
################################################################################

main() {
    # Always prompt for platform selection (no defaults)
    select_platform

    # Validate CLI tools are installed
    check_cli_tool "$CLI_TOOL"

    # Platform-specific additional checks
    if [[ "$PLATFORM" == "cns" ]]; then
        check_cns_tools
    fi

    # Validate authentication
    check_authentication

    # Delegate to platform-specific deployment script
    delegate_to_platform_script "$@"
}

# Execute main function with all script arguments
main "$@"
