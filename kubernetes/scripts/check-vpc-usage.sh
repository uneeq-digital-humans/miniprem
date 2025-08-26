#!/bin/bash

# Script to check VPC usage across AWS services
# This helps identify which VPCs can be safely deleted
# 
# Usage:
#   ./check-vpc-usage.sh                    # Check default VPCs in terraform region
#   ./check-vpc-usage.sh --region us-west-2 # Check VPCs in specific region
#   ./check-vpc-usage.sh --vpc vpc-123456    # Check specific VPC ID
#   ./check-vpc-usage.sh --region us-west-2 --vpc vpc-123456  # Check specific VPC in specific region

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values
REGION=""
SPECIFIC_VPC=""
VPCS=()
AWS_PROFILE_ARG=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region|-r)
            REGION="$2"
            shift 2
            ;;
        --vpc|-v)
            SPECIFIC_VPC="$2"
            shift 2
            ;;
        --profile|-p)
            AWS_PROFILE_ARG="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --region, -r REGION      AWS region to check (default: from terraform or us-east-1)"
            echo "  --vpc, -v VPC_ID         Check specific VPC ID only"
            echo "  --profile, -p PROFILE    Use specific AWS profile"
            echo "  --help, -h               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --region, -r REGION      AWS region to check (default: from terraform or us-east-1)"
            echo "  --vpc, -v VPC_ID         Check specific VPC ID only"
            echo "  --profile, -p PROFILE    Use specific AWS profile"
            echo "  --help, -h               Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Check all VPCs in configured region"
            echo "  $0 --region us-west-2           # Check VPCs in specific region"
            echo "  $0 --vpc vpc-123456789          # Check specific VPC"
            echo "  $0 --profile tyler@uneeq        # Use specific AWS profile"
            exit 1
            ;;
    esac
done

# Set profile if provided via command line
if [ -n "$AWS_PROFILE_ARG" ]; then
    export AWS_PROFILE="$AWS_PROFILE_ARG"
fi

# Determine region to use
if [ -z "$REGION" ]; then
    # Try to get region from terraform output first
    if [ -f "../terraform/terraform.tfstate" ]; then
        REGION=$(cd ../terraform && terraform output -raw region 2>/dev/null || echo "")
    fi
    
    # If still empty, check terraform.tfvars
    if [ -z "$REGION" ] && [ -f "../terraform/terraform.tfvars" ]; then
        REGION=$(grep "^aws_region" ../terraform/terraform.tfvars | cut -d'"' -f2 2>/dev/null || echo "")
    fi
    
    # Final fallback
    if [ -z "$REGION" ]; then
        REGION="us-east-1"
    fi
fi

# Determine VPCs to check
if [ -n "$SPECIFIC_VPC" ]; then
    VPCS=("$SPECIFIC_VPC")
else
    # Get all VPCs in the region
    echo "Discovering VPCs in region $REGION..."
    mapfile -t VPCS < <(aws ec2 describe-vpcs --region $REGION --query 'Vpcs[].VpcId' --output text | tr '\t' '\n')
    
    if [ ${#VPCS[@]} -eq 0 ]; then
        echo -e "${RED}No VPCs found in region $REGION${NC}"
        exit 1
    fi
    
    echo "Found ${#VPCS[@]} VPCs to analyze"
fi

echo "========================================"
echo "         VPC Usage Analysis            "
echo "========================================"
echo ""
echo "Region: $REGION"

if [ -n "$AWS_PROFILE" ]; then
    echo "Using AWS Profile: $AWS_PROFILE"
else
    echo "Using default AWS profile"
fi

IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "AWS Identity: $IDENTITY"

if [ -n "$SPECIFIC_VPC" ]; then
    echo "Analyzing specific VPC: $SPECIFIC_VPC"
else
    echo "Analyzing all VPCs in region: ${#VPCS[@]} found"
fi
echo ""

# Function to check if a command returns results
has_results() {
    local result="$1"
    if [[ "$result" =~ "No" ]] || [[ -z "$result" ]] || [[ "$result" == "0" ]]; then
        return 1
    else
        return 0
    fi
}

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}1. QUICK SUMMARY - Resource Counts per VPC${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

for vpc in "${VPCS[@]}"; do
    echo -e "${CYAN}=== VPC: $vpc ===${NC}"
    
    # Get VPC name
    vpc_name=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "No name")
    cidr=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].CidrBlock' --output text 2>/dev/null || echo "Unknown")
    is_default=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].IsDefault' --output text 2>/dev/null || echo "false")
    
    echo "  Name: $vpc_name"
    echo "  CIDR: $cidr"
    if [ "$is_default" == "True" ]; then
        echo -e "  ${RED}*** DEFAULT VPC - DO NOT DELETE ***${NC}"
    fi
    
    # Count active EC2 instances
    instances=$(aws ec2 describe-instances --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'length(Reservations[].Instances[?State.Name!=`terminated`])' --output text 2>/dev/null || echo "0")
    echo "  Active EC2 Instances: $instances"
    
    # Count subnets
    subnets=$(aws ec2 describe-subnets --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'length(Subnets)' --output text 2>/dev/null || echo "0")
    echo "  Subnets: $subnets"
    
    # Count NAT gateways
    nats=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$vpc" --query 'length(NatGateways[?State!=`deleted`])' --output text 2>/dev/null || echo "0")
    echo "  NAT Gateways: $nats"
    
    # Count Internet Gateways
    igws=$(aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$vpc" --query 'length(InternetGateways)' --output text 2>/dev/null || echo "0")
    echo "  Internet Gateways: $igws"
    
    # Count Load Balancers
    albs=$(aws elbv2 describe-load-balancers --region $REGION --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text 2>/dev/null || echo "0")
    elbs=$(aws elb describe-load-balancers --region $REGION --query "length(LoadBalancerDescriptions[?VPCId=='$vpc'])" --output text 2>/dev/null || echo "0")
    total_lbs=$((albs + elbs))
    echo "  Load Balancers: $total_lbs (ALB: $albs, Classic: $elbs)"
    
    # Count RDS instances
    rds_count=$(aws rds describe-db-instances --region $REGION --query "length(DBInstances[?DBSubnetGroup.VpcId=='$vpc'])" --output text 2>/dev/null || echo "0")
    echo "  RDS Instances: $rds_count"
    
    # Determine if VPC appears to be in use
    total_resources=$((instances + nats + total_lbs + rds_count))
    if [ "$is_default" == "True" ]; then
        echo -e "  ${RED}Status: DEFAULT VPC - NEVER DELETE${NC}"
    elif [ $total_resources -eq 0 ]; then
        echo -e "  ${GREEN}Status: Appears SAFE TO DELETE${NC}"
    else
        echo -e "  ${YELLOW}Status: IN USE - CHECK DETAILS BELOW${NC}"
    fi
    
    echo ""
done

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}2. DETAILED BREAKDOWN${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

for vpc in "${VPCS[@]}"; do
    echo -e "${CYAN}=== DETAILED CHECK FOR VPC: $vpc ===${NC}"
    
    vpc_name=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "No name")
    echo "VPC Name: $vpc_name"
    echo ""
    
    # Check EC2 Instances
    echo "--- EC2 Instances ---"
    instances=$(aws ec2 describe-instances --region $REGION --filters "Name=vpc-id,Values=$vpc" --query "Reservations[].Instances[?State.Name!=\`terminated\`].[InstanceId,State.Name,InstanceType,Tags[?Key==\`Name\`].Value|[0]]" --output table 2>/dev/null)
    if [[ "$instances" == *"|"* ]] && [[ "$instances" != *"None"* ]]; then
        echo "$instances"
    else
        echo -e "${GREEN}No active instances found${NC}"
    fi
    echo ""
    
    # Check EKS Clusters
    echo "--- EKS Clusters ---"
    found_eks=false
    for cluster in $(aws eks list-clusters --region $REGION --query 'clusters[]' --output text 2>/dev/null); do
        cluster_vpc=$(aws eks describe-cluster --region $REGION --name $cluster --query 'cluster.resourcesVpcConfig.vpcId' --output text 2>/dev/null)
        if [ "$cluster_vpc" == "$vpc" ]; then
            echo "EKS Cluster: $cluster (VPC: $cluster_vpc)"
            found_eks=true
        fi
    done
    if [ "$found_eks" = false ]; then
        echo -e "${GREEN}No EKS clusters found${NC}"
    fi
    echo ""
    
    # Check RDS Instances
    echo "--- RDS Instances ---"
    rds_instances=$(aws rds describe-db-instances --region $REGION --query "DBInstances[?DBSubnetGroup.VpcId=='$vpc'].[DBInstanceIdentifier,DBInstanceStatus,Engine]" --output table 2>/dev/null)
    if [[ "$rds_instances" == *"|"* ]] && [[ "$rds_instances" != *"None"* ]]; then
        echo "$rds_instances"
    else
        echo -e "${GREEN}No RDS instances found${NC}"
    fi
    echo ""
    
    # Check Load Balancers
    echo "--- Load Balancers ---"
    albs=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?VpcId=='$vpc'].[LoadBalancerName,State.Code,Type]" --output table 2>/dev/null)
    if [[ "$albs" == *"|"* ]] && [[ "$albs" != *"None"* ]]; then
        echo "Application/Network Load Balancers:"
        echo "$albs"
    fi
    
    elbs=$(aws elb describe-load-balancers --region $REGION --query "LoadBalancerDescriptions[?VPCId=='$vpc'].[LoadBalancerName,Scheme]" --output table 2>/dev/null)
    if [[ "$elbs" == *"|"* ]] && [[ "$elbs" != *"None"* ]]; then
        echo "Classic Load Balancers:"
        echo "$elbs"
    fi
    
    if [[ "$albs" != *"|"* ]] && [[ "$elbs" != *"|"* ]]; then
        echo -e "${GREEN}No load balancers found${NC}"
    fi
    echo ""
    
    # Check NAT Gateways
    echo "--- NAT Gateways ---"
    nat_gateways=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$vpc" --query "NatGateways[?State!=\`deleted\`].[NatGatewayId,State,SubnetId]" --output table 2>/dev/null)
    if [[ "$nat_gateways" == *"|"* ]] && [[ "$nat_gateways" != *"None"* ]]; then
        echo "$nat_gateways"
    else
        echo -e "${GREEN}No NAT gateways found${NC}"
    fi
    echo ""
    
    # Check Internet Gateways
    echo "--- Internet Gateways ---"
    igws=$(aws ec2 describe-internet-gateways --region $REGION --filters "Name=attachment.vpc-id,Values=$vpc" --query "InternetGateways[].[InternetGatewayId,Attachments[0].State]" --output table 2>/dev/null)
    if [[ "$igws" == *"|"* ]] && [[ "$igws" != *"None"* ]]; then
        echo "$igws"
    else
        echo -e "${GREEN}No internet gateways found${NC}"
    fi
    echo ""
    
    # Check Security Groups (non-default)
    echo "--- Custom Security Groups ---"
    custom_sgs=$(aws ec2 describe-security-groups --region $REGION --filters "Name=vpc-id,Values=$vpc" --query "SecurityGroups[?GroupName!=\`default\`].[GroupId,GroupName,Description]" --output table 2>/dev/null)
    if [[ "$custom_sgs" == *"|"* ]] && [[ "$custom_sgs" != *"None"* ]]; then
        echo "$custom_sgs"
    else
        echo -e "${GREEN}No custom security groups found (only default)${NC}"
    fi
    echo ""
    
    # Check VPC Endpoints
    echo "--- VPC Endpoints ---"
    endpoints=$(aws ec2 describe-vpc-endpoints --region $REGION --filters "Name=vpc-id,Values=$vpc" --query "VpcEndpoints[].[VpcEndpointId,ServiceName,State]" --output table 2>/dev/null)
    if [[ "$endpoints" == *"|"* ]] && [[ "$endpoints" != *"None"* ]]; then
        echo "$endpoints"
    else
        echo -e "${GREEN}No VPC endpoints found${NC}"
    fi
    echo ""
    
    echo -e "${CYAN}========================================${NC}"
    echo ""
done

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}3. DELETION RECOMMENDATIONS${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

echo -e "${YELLOW}NEVER DELETE:${NC}"
echo "• Default VPC (vpc-0acda9a2bdc4d7332) - This is your account's default VPC"
echo ""

echo -e "${GREEN}LIKELY SAFE TO DELETE:${NC}"
safe_to_delete=()
in_use=()

for vpc in "${VPCS[@]}"; do
    if [ "$vpc" == "vpc-0acda9a2bdc4d7332" ]; then
        continue  # Skip default VPC
    fi
    
    # Check if VPC has any resources
    instances=$(aws ec2 describe-instances --region $REGION --filters "Name=vpc-id,Values=$vpc" --query 'length(Reservations[].Instances[?State.Name!=`terminated`])' --output text 2>/dev/null || echo "0")
    nats=$(aws ec2 describe-nat-gateways --region $REGION --filter "Name=vpc-id,Values=$vpc" --query 'length(NatGateways[?State!=`deleted`])' --output text 2>/dev/null || echo "0")
    albs=$(aws elbv2 describe-load-balancers --region $REGION --query "length(LoadBalancers[?VpcId=='$vpc'])" --output text 2>/dev/null || echo "0")
    elbs=$(aws elb describe-load-balancers --region $REGION --query "length(LoadBalancerDescriptions[?VPCId=='$vpc'])" --output text 2>/dev/null || echo "0")
    rds_count=$(aws rds describe-db-instances --region $REGION --query "length(DBInstances[?DBSubnetGroup.VpcId=='$vpc'])" --output text 2>/dev/null || echo "0")
    
    total_resources=$((instances + nats + albs + elbs + rds_count))
    vpc_name=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "No name")
    
    if [ $total_resources -eq 0 ]; then
        safe_to_delete+=("$vpc")
        echo "• $vpc ($vpc_name) - No active resources found"
    else
        in_use+=("$vpc")
    fi
done

if [ ${#safe_to_delete[@]} -eq 0 ]; then
    echo "• None found - all VPCs appear to be in use"
fi

echo ""
echo -e "${YELLOW}CURRENTLY IN USE (check details above):${NC}"
for vpc in "${in_use[@]}"; do
    vpc_name=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "No name")
    echo "• $vpc ($vpc_name)"
done

if [ ${#in_use[@]} -eq 0 ]; then
    echo "• None found"
fi

echo ""
echo -e "${BLUE}DELETION COMMANDS (if you want to proceed):${NC}"
echo ""
if [ ${#safe_to_delete[@]} -gt 0 ]; then
    echo "To delete VPCs that appear unused (BE VERY CAREFUL!):"
    echo ""
    for vpc in "${safe_to_delete[@]}"; do
        vpc_name=$(aws ec2 describe-vpcs --region $REGION --vpc-ids $vpc --query 'Vpcs[0].Tags[?Key==`Name`].Value' --output text 2>/dev/null || echo "No name")
        echo "# Delete $vpc ($vpc_name)"
        echo "# First, delete any remaining subnets, route tables, etc."
        echo "# aws ec2 delete-vpc --vpc-id $vpc --region $REGION"
        echo ""
    done
    echo -e "${YELLOW}NOTE: You may need to delete subnets, route tables, security groups, etc. first!${NC}"
else
    echo "No VPCs appear safe to delete automatically."
    echo "You may need to:"
    echo "1. Request a VPC quota increase"
    echo "2. Use a different AWS region"
    echo "3. Manually clean up resources in existing VPCs"
fi

echo ""
echo "========================================"
echo "           Analysis Complete            "
echo "========================================"