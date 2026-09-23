# ECS サービス

resource "aws_ecs_task_definition" "app" {
  family                   = "app"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 512
  memory                   = 1024

  container_definitions = jsonencode([
    {
      name  = "app"
      image = "app:${var.image_tag}"
    }
  ])
}

resource "aws_ecs_service" "app" {
  name            = "app"
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 4
}
