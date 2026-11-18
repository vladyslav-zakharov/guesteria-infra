variable "project" {
  type        = string
  description = "The GCP project ID"
}

variable "environment" {
  type        = string
  description = "Resources deployment environment"
}

variable "gh_owner" {
  type        = string
  description = "The GitHub owner of the repository"
}

variable "gh_repo_name" {
  type        = string
  description = "The GitHub repository name"
}

variable "gh_branch_name" {
  type        = string
  description = "The branch name to trigger migrations from"
}

variable "direct_url_secret_id" {
  type        = string
  description = "Short secret_id of the Supabase session-pooler URL secret (used for Prisma migrations)"
}
