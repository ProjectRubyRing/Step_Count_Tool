# アプリリリース用スタック (ecs/service.tf は未配置 → j1 から推測)

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "image_tag" {
  type = string
}
