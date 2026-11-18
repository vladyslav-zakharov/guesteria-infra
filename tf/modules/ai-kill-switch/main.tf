# A GCP budget only ALERTS via email — it cannot cap spend (see the budget
# module's header comment). Cloud Run is already hard-capped at
# max_instance_count = 1, so compute is bounded, but Vertex AI (Gemini calls
# made by the API) is a per-request charge with only app-level daily caps
# (AI_DAILY_LIMIT per user, AI_GLOBAL_DAILY_LIMIT across all users) and no
# billing-level ceiling. This module is that ceiling: a
# SEPARATE budget (not the alert budget in the budget module — that one is
# left untouched) whose notifications drive a Cloud Function that disables
# the paid AI APIs, and only those APIs. It does NOT detach billing: search,
# bookings, auth and the database keep working; only the AI features degrade,
# and recovery is a single `gcloud services enable` away (see the repo README).

# Pub/Sub topic the kill-switch budget publishes its notifications to.
resource "google_pubsub_topic" "budget_notifications" {
  count = var.enabled ? 1 : 0

  name = "${var.environment}-ai-kill-switch-budget-notifications"
}

# No explicit google_pubsub_topic_iam_member here: Cloud Billing grants
# itself roles/pubsub.publisher on this topic the moment the budget below is
# created with an all_updates_rule pointing at it (observed live as
# serviceAccount:billing-budget-alert@system.gserviceaccount.com). That
# account is an internal, undocumented Google-managed identity — hardcoding it
# would be brittle if Google ever renames or rotates it, so we let Cloud
# Billing wire its own grant instead of declaring one ourselves.

# A SECOND, separate google_billing_budget from the one in the budget module.
# That one only alerts; this one drives the kill-switch and must never be
# merged with it, so the two can be reasoned about independently.
resource "google_billing_budget" "kill_switch" {
  count = var.enabled ? 1 : 0

  billing_account = var.billing_account
  display_name    = "${var.environment}-${var.project}-ai-kill-switch"

  budget_filter {
    projects = ["projects/${var.project_number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.amount
    }
  }

  # Only rule that matters here: actual (not forecasted) spend at 100% of
  # var.amount. Unlike the alert budget, there is no value in 50%/90% rules —
  # every crossing of THIS threshold fires the Cloud Function.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic   = google_pubsub_topic.budget_notifications[0].id
    schema_version = "1.0"
  }
}

# Private bucket for the Cloud Function's zipped source. Only Cloud Build and
# Cloud Functions ever touch this deploy artifact, so the Cloud Run SA gets no
# access and public access prevention is enforced.
resource "google_storage_bucket" "function_source" {
  count = var.enabled ? 1 : 0

  name     = "${var.environment}-${var.project}-ai-kill-switch-source"
  location = var.region

  force_destroy               = true
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

data "archive_file" "function_source" {
  count = var.enabled ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/.tmp/function-source.zip"
}

resource "google_storage_bucket_object" "function_source" {
  count = var.enabled ? 1 : 0

  # md5-suffixed object name: any change to the function source produces a new
  # object, so the Cloud Function resource below picks up the new deploy.
  name   = "function-source-${data.archive_file.function_source[0].output_md5}.zip"
  bucket = google_storage_bucket.function_source[0].name
  source = data.archive_file.function_source[0].output_path
}

# Dedicated SA for the function. Granted ONLY serviceusage.serviceUsageAdmin —
# nothing broader, so a compromised or buggy function can disable/enable APIs
# and nothing else.
resource "google_service_account" "kill_switch_sa" {
  count = var.enabled ? 1 : 0

  account_id   = "${var.environment}-ai-kill-switch"
  display_name = "AI kill-switch Cloud Function (${var.environment})"
}

resource "google_project_iam_member" "kill_switch_service_usage_admin" {
  count = var.enabled ? 1 : 0

  project = var.project
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.kill_switch_sa[0].email}"
}

# Eventarc's Pub/Sub trigger runs as the project's Pub/Sub service agent, which
# needs permission to mint the trigger's auth token. This is Google's own
# service agent, not the function's dedicated SA above, so it does not widen
# what the function itself can do.
resource "google_project_iam_member" "eventarc_pubsub_invoker" {
  count = var.enabled ? 1 : 0

  project = var.project
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_cloudfunctions2_function" "kill_switch" {
  count = var.enabled ? 1 : 0

  name        = "${var.environment}-ai-kill-switch"
  location    = var.region
  description = "Disables ${join(", ", var.target_services)} when the ${var.environment} ai-kill-switch budget crosses its threshold."

  build_config {
    runtime     = "nodejs22"
    entry_point = "handleBudgetNotification"

    source {
      storage_source {
        bucket = google_storage_bucket.function_source[0].name
        object = google_storage_bucket_object.function_source[0].name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.kill_switch_sa[0].email

    environment_variables = {
      PROJECT_ID          = var.project
      TARGET_SERVICES     = join(",", var.target_services)
      BUDGET_DISPLAY_NAME = google_billing_budget.kill_switch[0].display_name
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.budget_notifications[0].id
    # No retries: the function is idempotent per-notification (it re-derives
    # the disable decision from costAmount/budgetAmount every time), and
    # budget notifications repeat on their own on the next recalculation, so a
    # dropped delivery is not a missed kill-switch.
    retry_policy = "RETRY_POLICY_DO_NOT_RETRY"
  }

  depends_on = [
    google_project_iam_member.kill_switch_service_usage_admin,
    google_project_iam_member.eventarc_pubsub_invoker,
  ]
}
