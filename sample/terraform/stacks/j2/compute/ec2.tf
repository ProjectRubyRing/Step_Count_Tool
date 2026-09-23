# EC2 インスタンス

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  user_data = <<-EOT
    #!/bin/bash
    # ここはヒアドキュメント内なのでコメントではない
    dnf -y update

    systemctl enable --now nginx
  EOT

  tags = {
    Name = "${var.env_name}-app"
  }
}

module "alb" {
  source = "../modules/alb"

  name       = "${var.env_name}-alb"
  subnet_ids = aws_subnet.public[*].id
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
