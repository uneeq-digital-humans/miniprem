# Managed node group for Renny (GPU)
resource "aws_eks_node_group" "renny" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-renny-gpu"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets
  version         = var.kubernetes_version

  instance_types = [var.renny_instance_type]
  
  scaling_config {
    desired_size = var.renny_desired_size
    max_size     = var.renny_max_size
    min_size     = var.renny_min_size
  }

  # Ensure GPU AMI is used
  ami_type = "AL2_x86_64_GPU"

  labels = {
    "uneeq.io/node-type" = "renny"
    "workload-type"      = "gpu"
    "nvidia.com/gpu"     = "true"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-renny-gpu"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled" = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEBSCSIDriverPolicy,
  ]
}

# Managed node group for Audio2Face (GPU)
resource "aws_eks_node_group" "a2f" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-a2f-gpu"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets
  version         = var.kubernetes_version

  instance_types = [var.a2f_instance_type]
  
  scaling_config {
    desired_size = var.a2f_desired_size
    max_size     = var.a2f_max_size
    min_size     = var.a2f_min_size
  }

  # Ensure GPU AMI is used
  ami_type = "AL2_x86_64_GPU"

  labels = {
    "uneeq.io/node-type" = "a2f"
    "workload-type"      = "gpu"
    "nvidia.com/gpu"     = "true"
  }

  taint {
    key    = "nvidia.com/gpu"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-a2f-gpu"
      "k8s.io/cluster-autoscaler/${local.cluster_name}" = "owned"
      "k8s.io/cluster-autoscaler/enabled" = "true"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEBSCSIDriverPolicy,
  ]
}

# Control plane nodes (non-GPU for management services)
resource "aws_eks_node_group" "control" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-control"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets
  version         = var.kubernetes_version

  instance_types = ["t3.large"]
  
  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 2
  }

  labels = {
    "uneeq.io/node-type" = "control"
    "workload-type"      = "general"
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-control"
    }
  )

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_group_AmazonEBSCSIDriverPolicy,
  ]
}