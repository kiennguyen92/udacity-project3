 data "aws_availability_zones" "available" {}

locals {
  cluster_name   = "udacity"
  region = "us-east-1"

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

}

################################################################################
# EKS Module
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "19.15.4"

  cluster_name    = local.cluster_name
  cluster_version = "1.23"

  cluster_security_group_name = "eks-${local.cluster_name}-cluster-SG"
  node_security_group_name    = "eks-${local.cluster_name}-nodegroup-SG"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  cluster_enabled_log_types   = ["audit"]

        iam_role_additional_policies = {
        additional = aws_iam_policy.additional.arn
      }

  eks_managed_node_groups = {
    
    default = {
      name = "abc"

      instance_types = ["t3.xlarge"]

      min_size     = 0
      max_size     = 2
      desired_size = 1

      iam_role_additional_policies = {
        additional = aws_iam_policy.additional.arn
      }
    }
  }

}
################################################################################
# Supporting resources
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "vpc"

  cidr = local.vpc_cidr
  azs  = local.azs

  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 1)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + length(local.azs) + 1)]

  enable_nat_gateway = true
  single_nat_gateway = true

}

resource "aws_iam_policy" "additional" {
  name = "additional"

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:BatchCheckLayerAvailability",
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer",
                "ecr:GetAuthorizationToken"
            ],
            "Resource": "*"
        }
    ]
  })
}