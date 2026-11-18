terraform {
  required_version = ">= 1.10.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "6.20.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "2.4.2"
    }

    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
  zone    = var.zone

  # billingbudgets.googleapis.com is a user-project-override API: with local
  # ADC the provider must send the quota project explicitly, or the call
  # falls through to Google's shared SDK project and 403s with
  # SERVICE_DISABLED. Fixed here rather than by changing the machine's
  # global ADC quota project, which is a single system-wide setting shared
  # by every other tool.
  user_project_override = true
  billing_project       = var.project
}

resource "google_storage_bucket" "tfstate" {
  name     = "${var.environment}-${var.project}-${var.service_name}-tfstate"
  location = var.region

  force_destroy               = false
  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 5
    }

    action {
      type = "Delete"
    }
  }
}

resource "local_file" "backend" {
  file_permission = "0644"
  filename        = "${path.module}/backend.tf"

  content = <<-EOT
  terraform {
    backend "gcs" {
      bucket = "${google_storage_bucket.tfstate.name}"
    }
  }
  EOT
}

module "project_api" {
  source = "../modules/project-api"
}

module "secret" {
  source = "../modules/secret"

  environment = var.environment

  depends_on = [
    module.project_api,
  ]
}

module "cloud_run" {
  source = "../modules/cloud-run"

  set_dummy_image = var.cloud_run_set_dummy_image

  project = var.project
  region  = var.region

  environment = var.environment

  gh_owner       = var.gh_owner
  gh_repo_name   = var.gh_repo_name
  service_name   = var.service_name
  gh_branch_name = var.gh_branch_name

  instance_limit_cpus   = var.cloud_run_instance_limit_cpus
  instance_limit_memory = var.cloud_run_instance_limit_memory
  min_instance_count    = var.cloud_run_min_instance_count

  env_vars = {
    NODE_ENV              = "production"
    APPLICATION_URL       = var.cloud_run_application_url
    FRONTEND_URL          = var.frontend_url
    GCP_PROJECT_ID        = var.project
    AI_DAILY_LIMIT        = var.ai_daily_limit
    AI_GLOBAL_DAILY_LIMIT = var.ai_global_daily_limit
    TRUST_PROXY_HOPS      = var.trust_proxy_hops
  }

  secret_vars = {
    DATABASE_URL       = module.secret.database_url_secret_id
    APPLICATION_SECRET = module.secret.application_secret
    DOCS_PASSWORD      = module.secret.docs_password_secret_id
    LITEAPI_API_KEY    = module.secret.liteapi_api_key_secret_id
  }

  depends_on = [
    module.project_api,
    module.secret,
  ]
}

module "migration" {
  source = "../modules/migration"

  project        = var.project
  environment    = var.environment
  gh_owner       = var.gh_owner
  gh_repo_name   = var.gh_repo_name
  gh_branch_name = var.gh_branch_name

  direct_url_secret_id = module.secret.direct_url_secret_id

  depends_on = [
    module.project_api,
    module.secret,
  ]
}

module "budget" {
  source = "../modules/budget"

  billing_account = var.billing_account
  project         = var.project
  project_number  = var.project_number
  environment     = var.environment
  amount          = var.budget_amount

  depends_on = [
    module.project_api,
  ]
}

module "ai_kill_switch" {
  source = "../modules/ai-kill-switch"

  billing_account = var.billing_account
  project         = var.project
  project_number  = var.project_number
  environment     = var.environment
  region          = var.region
  amount          = var.ai_kill_switch_budget_amount
  enabled         = var.ai_kill_switch_enabled
  target_services = var.ai_kill_switch_target_services

  depends_on = [
    module.project_api,
  ]
}
