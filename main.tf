terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.15.0"
    }

    # random = {
    #   source  = "hashicorp/random"
    #   version = "~> 3.1.0"
    # }

    # tls = {
    #   source  = "hashicorp/tls"
    #   version = "~> 3.4.0"
    # }

    # cloudinit = {
    #   source  = "hashicorp/cloudinit"
    #   version = "~> 2.2.0"
    # }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }

  backend "remote" {
    organization = "sreyo23"

    workspaces {
      name = "new-config-eks"
    }
  }
  #required_version = "~> 1.3"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "name"
  # default     = "launch"
}

# locals {
#   cluster_name = "education-eks-${random_string.suffix.result}"
# }

# resource "random_string" "suffix" {
#   length  = 8
#   special = false
# }

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {}

resource "aws_security_group" "node_group_one" {
  name_prefix = "node_group_one"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"

    cidr_blocks = [
      "10.0.0.0/8",
    ]
  }
}

# resource "aws_security_group" "node_group_two" {
#   name_prefix = "node_group_two"
#   vpc_id      = module.vpc.vpc_id

#   ingress {
#     from_port = 22
#     to_port   = 22
#     protocol  = "tcp"

#     cidr_blocks = [
#       "192.168.0.0/16",
#     ]
#   }
# }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  name = "${var.cluster_name}-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "18.26.6"

  cluster_name    = var.cluster_name
  cluster_version = "1.22"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

    attach_cluster_primary_security_group = true
    
    node_security_group_tags = {
      "kubernetes.io/cluster/${var.name}" = null
    }

    # Disabling and using externally provided security groups
    create_security_group = false
  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.large"]

      min_size     = 1
      max_size     = 3
      desired_size = 2

      pre_bootstrap_user_data = <<-EOT
      echo 'foo bar'
      EOT

      vpc_security_group_ids = [
        aws_security_group.node_group_one.id
      ]
    }

    # two = {
    #   name = "node-group-2"

    #   instance_types = ["t3.medium"]

    #   min_size     = 1
    #   max_size     = 2
    #   desired_size = 1

    #   pre_bootstrap_user_data = <<-EOT
    #   echo 'foo bar'
    #   EOT

    #   vpc_security_group_ids = [
    #     aws_security_group.node_group_two.id
    #   ]
    # }
  }
}
