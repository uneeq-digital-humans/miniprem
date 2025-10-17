#!/bin/bash

################################################################################
# MiniPrem Multi-Cloud Kubernetes Status Router
#
# This script provides a unified entry point for checking the status of MiniPrem
# deployments across multiple cloud platforms. It handles:
#   - Interactive platform selection (AWS, Azure, GCP)
#   - CLI tool validation with OS-specific install instructions
#   - Authentication verification using environment variables and CLI
#   - Delegation to platform-specific status scripts
#
# Usage:
#   ./status.sh
#
# The script will prompt for platform selection and guide you through
# prerequisites before delegating to the appropriate platform-specific script.
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
║          MiniPrem Multi-Cloud Kubernetes Status Check         ║
╚═══════════════════════════════════════════════════════════════╝
"

    echo "Select your cloud platform:"
    echo ""
    echo "  1) Amazon Web Services (AWS)"
    echo "  2) Microsoft Azure"
    echo "  3) Google Cloud Platform (GCP)"
    echo ""
    echo -n "Enter your choice (1-3): "

    read -r choice

    case $choice in
        1)
            PLATFORM="aws"
            PLATFORM_NAME="Amazon Web Services (AWS)"
            CLI_TOOL="aws"
            STATUS_SCRIPT="status-aws.sh"
            ;;
        2)
            PLATFORM="azure"
            PLATFORM_NAME="Microsoft Azure"
            CLI_TOOL="az"
            STATUS_SCRIPT="status-azure.sh"
            ;;
        3)
            PLATFORM="gcp"
            PLATFORM_NAME="Google Cloud Platform (GCP)"
            CLI_TOOL="gcloud"
            STATUS_SCRIPT="status-gcp.sh"
            ;;
        *)
            error "Invalid choice. Please run the script again and select 1, 2, or 3."
            exit 1
            ;;
    esac

    info "Selected platform: $PLATFORM_NAME"
    echo ""
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
            az version --output tsv 2>&1 | grep azure-cli | head -1
            ;;
        gcloud)
            gcloud version 2>&1 | grep "Google Cloud SDK" | head -1
            ;;
    esac

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
    esac

    echo ""
}

################################################################################
# Status Check Delegation
################################################################################

delegate_to_platform_script() {
    local script_path="$SCRIPT_DIR/$STATUS_SCRIPT"

    info "Delegating to platform-specific script: $STATUS_SCRIPT"

    # Check if platform-specific script exists
    if [[ ! -f "$script_path" ]]; then
        error "Platform-specific status script not found: $script_path"
        echo ""

        if [[ "$PLATFORM" == "gcp" ]]; then
            warning "GCP status support is planned but not yet implemented."
            echo ""
            echo "To track progress or contribute:"
            echo "  - Check for open issues in the repository"
            echo "  - See documentation for AWS/Azure status as reference"
            exit 1
        else
            error "Expected script location: $script_path"
            echo "Please ensure the status scripts are properly installed."
            exit 1
        fi
    fi

    # Make sure script is executable
    chmod +x "$script_path"

    print_color "$BOLD" "
╔═══════════════════════════════════════════════════════════════╗
║           Checking $PLATFORM_NAME Deployment Status           ║
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

    # Validate authentication
    check_authentication

    # Delegate to platform-specific status script
    delegate_to_platform_script "$@"
}

# Execute main function with all script arguments
main "$@"
