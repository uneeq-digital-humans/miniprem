output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "deployment_id" {
  description = "Deployment ID for resource isolation"
  value       = var.deployment_id
}

output "base_cluster_name" {
  description = "Base cluster name without deployment ID"
  value       = "${var.project_name}-${var.environment}"
}

output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "update_kubeconfig_command" {
  description = "Command to update kubeconfig"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "cluster_autoscaler_role_arn" {
  description = "ARN of the cluster autoscaler IAM role"
  value       = aws_iam_role.cluster_autoscaler.arn
}

output "node_groups" {
  description = "Information about the node groups"
  value = {
    renny = {
      name         = aws_eks_node_group.renny.node_group_name
      min_size     = aws_eks_node_group.renny.scaling_config[0].min_size
      max_size     = aws_eks_node_group.renny.scaling_config[0].max_size
      desired_size = aws_eks_node_group.renny.scaling_config[0].desired_size
    }
    a2f = {
      name         = aws_eks_node_group.a2f.node_group_name
      min_size     = aws_eks_node_group.a2f.scaling_config[0].min_size
      max_size     = aws_eks_node_group.a2f.scaling_config[0].max_size
      desired_size = aws_eks_node_group.a2f.scaling_config[0].desired_size
    }
    control = {
      name         = aws_eks_node_group.control.node_group_name
      min_size     = aws_eks_node_group.control.scaling_config[0].min_size
      max_size     = aws_eks_node_group.control.scaling_config[0].max_size
      desired_size = aws_eks_node_group.control.scaling_config[0].desired_size
    }
  }
}