variable "project" {
  type        = string
  description = "The GCP project ID to deploy resources"
}

variable "project_number" {
  type        = number
  description = "The GCP project number to deploy resources"
}

variable "region" {
  type        = string
  description = "Region where to deploy resources"
}

variable "zone" {
  description = "Region zone where to deploy resources"
  type        = string
}

variable "environment" {
  description = "The environment to deploy resources (dev, prod, staging, test)"
  type        = string
}

variable "service_name" {
  description = "Deployed resources naming e.g. my-project-name"
  type        = string
}

variable "frontend_url" {
  type        = string
  description = "The frontend (Vercel) origin, used for CORS"
}

variable "gh_branch_name" {
  description = "The branch name to trigger new revisions from"
  type        = string
}

variable "gh_owner" {
  description = "The GitHub owner of the repository"
  type        = string
}

variable "gh_repo_name" {
  description = "The GitHub repository name"
  type        = string
}

// cloud-run module

variable "cloud_run_instance_limit_cpus" {
  description = "The number of CPUs to allocate to the Cloud Run instance"
  type        = number
}

variable "cloud_run_instance_limit_memory" {
  description = "The amount of memory to allocate to the Cloud Run instance"
  type        = string
}

variable "cloud_run_min_instance_count" {
  description = "The minimum number of instances to run. 0 = scale to zero (free), 1 = always-on (eliminates cold starts)."
  type        = number
  default     = 0
}

variable "cloud_run_application_url" {
  description = "Cloud Run application URL (update after first apply)"
  type        = string
}

variable "cloud_run_set_dummy_image" {
  description = "Use a placeholder image when the Cloud Run service is created, because Artifact Registry has no image yet. Only read on create: the image is in ignore_changes, so after the first deploy Cloud Build owns it and this flag has no effect."
  type        = bool
}

variable "ai_daily_limit" {
  description = "Daily cap on AI (Gemini) calls per user per UTC day, enforced by the API (AI_DAILY_LIMIT)."
  type        = number
}

variable "ai_global_daily_limit" {
  description = "Daily cap on AI (Gemini) calls across all users, enforced by the API (AI_GLOBAL_DAILY_LIMIT)."
  type        = number
  default     = 500
}

variable "trust_proxy_hops" {
  description = "Number of proxy hops in front of the API whose X-Forwarded-For entries the API trusts for the client IP (TRUST_PROXY_HOPS). Expected chain is Vercel rewrite -> Google Front End -> Cloud Run, so 2; confirm after the first deploy by checking that two different clients get different request.ip. 1 would put all Vercel traffic in one rate-limit bucket."
  type        = number
}

// budget module

variable "billing_account" {
  description = "The Cloud Billing account ID the budget is created under"
  type        = string
}

variable "budget_amount" {
  description = "The monthly budget amount in USD. This only triggers alert emails to the billing account's admins/users at 50/90/100% (plus a forecasted-100% rule) — it does NOT cap or throttle spend."
  type        = number
}

// ai-kill-switch module

variable "ai_kill_switch_enabled" {
  description = "Whether the AI kill-switch (budget, Pub/Sub topic, Cloud Function) exists. Set false to remove the automated kill-switch without deleting Terraform state."
  type        = bool
  default     = true
}

variable "ai_kill_switch_budget_amount" {
  description = "The monthly spend threshold in USD that fires the kill-switch. Unlike budget_amount above, crossing this ACTUALLY disables ai_kill_switch_target_services — it is not just an alert email."
  type        = number
}

variable "ai_kill_switch_target_services" {
  description = "The paid, per-request GCP APIs to disable when the kill-switch budget crosses its threshold."
  type        = list(string)
  default     = ["aiplatform.googleapis.com"]
}
