module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = data.aws_availability_zones.available.names
  private_subnets = [
    cidrsubnet(var.vpc_cidr, 8, 1),   # e.g., 10.17.1.0/24
    cidrsubnet(var.vpc_cidr, 8, 2),   # e.g., 10.17.2.0/24
    cidrsubnet(var.vpc_cidr, 8, 3)    # e.g., 10.17.3.0/24
  ]
  public_subnets  = [
    cidrsubnet(var.vpc_cidr, 8, 101), # e.g., 10.17.101.0/24
    cidrsubnet(var.vpc_cidr, 8, 102), # e.g., 10.17.102.0/24
    cidrsubnet(var.vpc_cidr, 8, 103)  # e.g., 10.17.103.0/24
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = !var.enable_nat_ha  # Use customer choice for NAT HA
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required for EKS
  enable_flow_log                      = true
  create_flow_log_cloudwatch_iam_role  = true
  create_flow_log_cloudwatch_log_group = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = local.common_tags
}

data "aws_availability_zones" "available" {
  state = "available"
}