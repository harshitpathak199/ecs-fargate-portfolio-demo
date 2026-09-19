locals {
  container_name = "app"
  container_port = 3000
 
  # Repositories created on GitHub.com after 15 July 2026 use immutable OIDC subjects.
  github_oidc_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/${var.github_branch}"
}
 
# ---------------------------
# NETWORK
# ---------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
 
  tags = { Name = "${var.project_name}-vpc" }
}
 
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}
 
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-a" }
}
 
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-b" }
}
 
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
 
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
 
  tags = { Name = "${var.project_name}-public-rt" }
}
 
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
 
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
 
# ---------------------------
# SECURITY GROUPS
# ---------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Public HTTP to the demo ALB"
  vpc_id      = aws_vpc.main.id
 
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
 
resource "aws_security_group" "ecs" {
  name        = "${var.project_name}-ecs-sg"
  description = "Only the ALB may reach the Node.js container"
  vpc_id      = aws_vpc.main.id
 
  ingress {
    description     = "Node.js from ALB only"
    from_port       = local.container_port
    to_port         = local.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
 
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
 
# ---------------------------
# ECR + CLOUDWATCH
# ---------------------------
resource "aws_ecr_repository" "app" {
  name         = "${var.project_name}-app"
  force_delete = true
 
  image_scanning_configuration {
    scan_on_push = true
  }
}
 
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 1
}
 
# ---------------------------
# ECS IAM + CLUSTER
# ---------------------------
data "aws_iam_policy_document" "ecs_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
 
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}
 
resource "aws_iam_role" "ecs_execution" {
  name               = "${var.project_name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume.json
}
 
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
 
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}
 
# ---------------------------
# APPLICATION LOAD BALANCER
# ---------------------------
resource "aws_lb" "app" {
  name               = "${var.project_name}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}
 
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = local.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
 
  health_check {
    enabled             = true
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}
 
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
 
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
 
# ---------------------------
# ECS TASK + SERVICE
# Created only after bootstrap image exists in ECR.
# ---------------------------
resource "aws_ecs_task_definition" "app" {
  count = var.create_service ? 1 : 0
 
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution.arn
 
  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${aws_ecr_repository.app.repository_url}:bootstrap"
      essential = true
 
      portMappings = [
        {
          containerPort = local.container_port
          hostPort      = local.container_port
          protocol      = "tcp"
        }
      ]
 
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "APP_VERSION", value = "bootstrap" }
      ]
 
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}
 
resource "aws_ecs_service" "app" {
  count = var.create_service ? 1 : 0
 
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "LATEST"
 
  health_check_grace_period_seconds = 30
 
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
 
  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
 
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }
 
  depends_on = [aws_lb_listener.http]
}
 
# ---------------------------
# ECS SERVICE AUTO SCALING
# 1 task normally, maximum 2 for the demo.
# ---------------------------
resource "aws_appautoscaling_target" "ecs" {
  count = var.create_service ? 1 : 0
 
  max_capacity       = 2
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app[0].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
 
resource "aws_appautoscaling_policy" "cpu" {
  count = var.create_service ? 1 : 0
 
  name               = "${var.project_name}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs[0].resource_id
  scalable_dimension = aws_appautoscaling_target.ecs[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs[0].service_namespace
 
  target_tracking_scaling_policy_configuration {
    target_value       = 25
    scale_out_cooldown = 30
    scale_in_cooldown  = 60
 
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
 
# ---------------------------
# GITHUB OIDC PROVIDER + DEPLOYMENT ROLE
# ---------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.manage_github_oidc_provider ? 1 : 0
 
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
 
data "aws_iam_openid_connect_provider" "github_existing" {
  count = var.manage_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}
 
locals {
  github_oidc_provider_arn = (
    var.manage_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : data.aws_iam_openid_connect_provider.github_existing[0].arn
  )
}
 
data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
 
    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }
 
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
 
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [local.github_oidc_subject]
    }
  }
}
 
resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}
 
data "aws_iam_policy_document" "github_deploy" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
 
  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage"
    ]
    resources = [aws_ecr_repository.app.arn]
  }
 
  statement {
    sid = "ECSDeploy"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeServices",
      "ecs:UpdateService"
    ]
    resources = ["*"]
  }
 
  statement {
    sid       = "PassExecutionRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.ecs_execution.arn]
  }
}
 
resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.project_name}-github-deploy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy.json
}
 
# ---------------------------
# SIMPLE CLOUDWATCH DASHBOARD
# ---------------------------
resource "aws_cloudwatch_dashboard" "app" {
  count          = var.create_service ? 1 : 0
  dashboard_name = "${var.project_name}-dashboard"
 
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x = 0
        y = 0
        width = 12
        height = 6
        properties = {
          title  = "ECS CPU and Memory"
          region = var.aws_region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.main.name, "ServiceName", aws_ecs_service.app[0].name],
            [".", "MemoryUtilization", ".", ".", ".", "."]
          ]
        }
      },
      {
        type = "metric"
        x = 12
        y = 0
        width = 12
        height = 6
        properties = {
          title  = "ALB Request Count"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.app.arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        x = 0
        y = 6
        width = 12
        height = 6
        properties = {
          title  = "ALB Target Response Time"
          region = var.aws_region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.app.arn_suffix, "TargetGroup", aws_lb_target_group.app.arn_suffix]
          ]
        }
      },
      {
        type = "metric"
        x = 12
        y = 6
        width = 12
        height = 6
        properties = {
          title  = "Healthy / Unhealthy Hosts"
          region = var.aws_region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.app.arn_suffix, "TargetGroup", aws_lb_target_group.app.arn_suffix],
            [".", "UnHealthyHostCount", ".", ".", ".", "."]
          ]
        }
      }
    ]
  })
}
