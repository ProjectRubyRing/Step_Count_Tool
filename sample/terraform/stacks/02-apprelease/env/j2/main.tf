# アプリリリース用スタック

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
