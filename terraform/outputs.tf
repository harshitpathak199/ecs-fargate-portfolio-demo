output "aws_region" {
  value = var.aws_region
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.app.name
}

output "alb_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  value = "${var.project_name}-service"
}

output "ecs_task_family" {
  value = "${var.project_name}-task"
}

output "ecs_container_name" {
  value = local.container_name
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "github_oidc_subject" {
  value = local.github_oidc_subject
}
