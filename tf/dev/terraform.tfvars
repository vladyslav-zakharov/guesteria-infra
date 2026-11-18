project = "guesteria-stayhub"

region = "europe-west1"
zone   = "europe-west1-b"

environment  = "dev"
service_name = "guesteria-api"

# GitHub repository that Cloud Build will watch.
gh_owner       = "vladyslav-zakharov"
gh_repo_name   = "guesteria-back"
gh_branch_name = "main"

# CORS origin for the backend (FRONTEND_URL env var): the public Vercel production URL.
frontend_url = "https://guesteria-front.vercel.app"

# Fill after the first full apply: set this to `terraform output api_url`, then apply again.
cloud_run_application_url = "REPLACE_ME"

# Scales to zero: no idle cost, at the price of cold starts.
cloud_run_min_instance_count = 0

# 512Mi is enough for Node + Prisma; keeps free GB-seconds usage low.
cloud_run_instance_limit_memory = "512Mi"
cloud_run_instance_limit_cpus   = 1

# Placeholder image for the first apply (Artifact Registry is empty). Only read
# when the service is created: the image is in ignore_changes and Cloud Build
# owns it after the first deploy, so the value no longer matters.
cloud_run_set_dummy_image = true

# Daily cap on AI (Gemini) calls per user per UTC day, enforced by the API.
ai_daily_limit = 30

# Daily cap on AI (Gemini) calls across all users, enforced by the API.
ai_global_daily_limit = 500

# Proxy hops in front of the API whose X-Forwarded-For entries are trusted.
# Expected chain: Vercel rewrite -> Google Front End -> Cloud Run, so 2.
# Confirm after the first deploy: two different clients must get different request.ip;
# 1 would put all Vercel traffic in one rate-limit bucket.
trust_proxy_hops = 2

# Alert-only budget: emails the billing account's admins, never caps spend.
budget_amount = 10

# AI kill-switch: unlike budget_amount above, crossing this threshold ACTUALLY
# disables aiplatform.googleapis.com via a Cloud Function. Any later
# `terraform apply` re-enables it (see README, "AI kill switch").
ai_kill_switch_enabled         = true
ai_kill_switch_budget_amount   = 10
ai_kill_switch_target_services = ["aiplatform.googleapis.com"]
