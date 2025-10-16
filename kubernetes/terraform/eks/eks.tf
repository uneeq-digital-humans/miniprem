module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = var.kubernetes_version

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Configure service IPv4 CIDR from customer choice
  cluster_service_ipv4_cidr = var.service_cidr

  # Enable IRSA (v20 standard)
  enable_irsa = true

  # Disable KMS encryption for reference deployment (can be enabled later)
  create_kms_key            = false
  cluster_encryption_config = {}

  # Enable cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  # OIDC Provider
  cluster_identity_providers = {}

  # Security group rules
  cluster_security_group_additional_rules = {
    egress_nodes_ephemeral_ports_tcp = {
      description                = "To node 1025-65535"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "egress"
      source_node_security_group = true
    }
    # WebRTC/TURN ports
    ingress_turn_udp = {
      description = "TURN UDP"
      protocol    = "udp"
      from_port   = 3478
      to_port     = 3478
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_turn_tcp = {
      description = "TURN TCP"
      protocol    = "tcp"
      from_port   = 3478
      to_port     = 3478
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_turn_tls = {
      description = "TURN TLS"
      protocol    = "tcp"
      from_port   = 5349
      to_port     = 5349
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    ingress_webrtc_udp = {
      description = "WebRTC UDP Range"
      protocol    = "udp"
      from_port   = 22000
      to_port     = 23000
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  # Node security group rules
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description = "Node all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
    # Additional WebRTC ports for nodes
    ingress_webrtc_from_internet = {
      description = "WebRTC from Internet"
      protocol    = "udp"
      from_port   = 22000
      to_port     = 23000
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = local.common_tags
}