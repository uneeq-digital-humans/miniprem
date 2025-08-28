
# Ubuntu EKS AMI data source for GPU nodes (matches working infra project)
data "aws_ami" "ubuntu_gpu" {
  owners      = ["099720109477"] # Canonical
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu-eks/k8s_${var.kubernetes_version}/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Launch template for GPU nodes with Ubuntu
resource "aws_launch_template" "renny_gpu" {
  name          = "${local.cluster_name}-renny-gpu-lt"
  image_id      = data.aws_ami.ubuntu_gpu.id
  instance_type = var.renny_instance_type

  vpc_security_group_ids = [module.eks.node_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 150
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/ubuntu_userdata.sh", {
    cluster_name        = local.cluster_name
    cluster_endpoint    = module.eks.cluster_endpoint
    cluster_ca          = module.eks.cluster_certificate_authority_data
    node_labels         = "uneeq.io/node-type=renny"
    cluster_dns_ip      = cidrhost(var.service_cidr, 10)  # e.g., 10.117.0.10
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.cluster_name}-renny-gpu"
      }
    )
  }
}

# Managed node group for Renny (GPU) using Ubuntu launch template
resource "aws_eks_node_group" "renny" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-renny-gpu-v4"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets

  # Use Ubuntu launch template instead of ami_type
  launch_template {
    id      = aws_launch_template.renny_gpu.id
    version = aws_launch_template.renny_gpu.latest_version
  }
  
  scaling_config {
    desired_size = var.renny_desired_size
    max_size     = var.renny_max_size
    min_size     = var.renny_min_size
  }

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

# Launch template for A2F nodes with Ubuntu
resource "aws_launch_template" "a2f_gpu" {
  name          = "${local.cluster_name}-a2f-gpu-lt"
  image_id      = data.aws_ami.ubuntu_gpu.id
  instance_type = var.a2f_instance_type

  vpc_security_group_ids = [module.eks.node_security_group_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 150
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/ubuntu_userdata.sh", {
    cluster_name        = local.cluster_name
    cluster_endpoint    = module.eks.cluster_endpoint
    cluster_ca          = module.eks.cluster_certificate_authority_data
    node_labels         = "uneeq.io/node-type=a2f"
    cluster_dns_ip      = cidrhost(var.service_cidr, 10)  # e.g., 10.117.0.10
  }))

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      local.common_tags,
      {
        Name = "${local.cluster_name}-a2f-gpu"
      }
    )
  }
}

# Managed node group for Audio2Face (GPU) using Ubuntu launch template
resource "aws_eks_node_group" "a2f" {
  cluster_name    = module.eks.cluster_name
  node_group_name = "${local.cluster_name}-a2f-gpu-v4"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = module.vpc.private_subnets

  # Use Ubuntu launch template instead of ami_type
  launch_template {
    id      = aws_launch_template.a2f_gpu.id
    version = aws_launch_template.a2f_gpu.latest_version
  }
  
  scaling_config {
    desired_size = var.a2f_desired_size
    max_size     = var.a2f_max_size
    min_size     = var.a2f_min_size
  }

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