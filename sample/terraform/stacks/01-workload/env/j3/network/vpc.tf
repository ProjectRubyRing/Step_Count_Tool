#############################################
# VPC 定義
#############################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 既定タグ
locals {
  common_tags = {
    Environment = var.env_name
    ManagedBy   = "terraform"   # 運用管理者
  }
}

// メイン VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.env_name}-vpc"
  })
}

/*
 * インターネットゲートウェイ
 * 外部通信用
 */
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.env_name}-igw"
  }
}

variable "vpc_cidr" {
  type        = string
  description = "VPC の CIDR ブロック"
  default     = "10.0.0.0/16"
}

variable "env_name" {
  type = string
}

output "vpc_id" {
  value = aws_vpc.main.id
}
