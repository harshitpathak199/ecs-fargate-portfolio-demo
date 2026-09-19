variable "aws_region" {
  type        = string
  description = "AWS region for the lab"
  default     = "us-east-1"
}
 
variable "project_name" {
  type        = string
  description = "Short name used for AWS resources"
  default     = "ecs-portfolio-demo"
}
 
variable "destroy_after" {
  type        = string
  description = "Human-readable reminder tag"
  default     = "same-day"
}
 
variable "create_service" {
  type        = bool
  description = "False for foundation/ECR bootstrap; true after the image is pushed"
  default     = false
}
 
variable "manage_github_oidc_provider" {
  type        = bool
  description = "Set false if token.actions.githubusercontent.com already exists in this AWS account"
  default     = true
}
 
variable "github_owner" {
  type        = string
  description = "GitHub user or organization name"
}
 
variable "github_owner_id" {
  type        = string
  description = "Immutable numeric GitHub owner ID"
}
 
variable "github_repo" {
  type        = string
  description = "GitHub repository name"
  default     = "ecs-fargate-portfolio-demo"
}
 
variable "github_repo_id" {
  type        = string
  description = "Immutable numeric GitHub repository ID"
}
 
variable "github_branch" {
  type        = string
  description = "Branch allowed to assume the AWS deployment role"
  default     = "main"
}
