data "aws_availability_zones" "available" {}

locals {
  common_tags = {
    Owner    = "quybao@bot-it.ai"
    CreateBy = "terraform"
    Project  = "Quy Bao DevOps Training"
  }
  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

}

########################################################################
# Cluster
# Github repo: https://github.com/terraform-aws-modules/terraform-aws-eks
########################################################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.23"

  cluster_security_group_name = "eks-${var.cluster_name}-cluster-SG"
  node_security_group_name    = "eks-${var.cluster_name}-nodegroup-SG"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      preserve                 = false
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      preserve = false
    }
    vpc-cni = {
      preserve = false
    }
    kube-proxy = {
      preserve = false
    }
  }

  cluster_enabled_log_types   = []
  create_cloudwatch_log_group = false

  eks_managed_node_groups = {
    default = {
      name = "abc"

      instance_types = ["t3.xlarge"]

      min_size     = 0
      max_size     = 2
      desired_size = 1
    }
  }

  # Disable Recommended rules from module, e.g node-to-node TPC ingress, allows all egress traffic.
  # Self define rule to more control
  node_security_group_enable_recommended_rules = false
  node_security_group_additional_rules = {
    istio = {
      description                   = "Istio webhook"
      protocol                      = "tcp"
      from_port                     = 15017
      to_port                       = 15017
      type                          = "ingress"
      source_cluster_security_group = true
    }
    keda_metrics_server_access = {
      description                   = "Access to KEDA metrics"
      protocol                      = "tcp"
      from_port                     = 6443
      to_port                       = 6443
      type                          = "ingress"
      source_cluster_security_group = true
    }
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
    egress_all = {
      description = "Allow all egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
  tags = local.common_tags
}
########################################################################
# Cluster Addon
# Github repo: https://aws-ia.github.io/terraform-aws-eks-blueprints-addons/main/
########################################################################
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.29"

  role_name_prefix = "${module.eks.cluster_name}-EBSCSIDriver-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.common_tags
}

module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "1.1.0"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  tags = local.common_tags
}

########################################################################
# Cluster VPC
# Github repo: https://github.com/terraform-aws-modules/terraform-aws-vpc
########################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${var.prefix_name != "" ? "${var.prefix_name}-" : ""}vpc"

  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 1)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + length(local.azs) + 1)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.common_tags

}

########################################################################
# Project Support Infrastructure
# Github repo: https://github.com/terraform-aws-modules/terraform-aws-vpc
########################################################################
module "istio" {

  count = var.deploy_istio ? 1 : 0

  source              = "./modules/istio"
  istio_chart_version = "1.18.1"
  depends_on = [
    module.eks
  ]
}

locals {
  monitoring_namespace = "monitoring"
}

module "monitoring" {
  count = var.deploy_monitoring ? 1 : 0

  source = "./modules/monitoring"

  tsdb_s3_bucket = "${var.prefix_name != "" ? "${var.prefix_name}-" : ""}prometheus-tsdb"

  oidc_provider_arn = module.eks.oidc_provider_arn

  monitoring_namespace = local.monitoring_namespace
  bucket_config        = file("../../project-4/thanos-objstore-config.yaml")

  tags = local.common_tags

}
