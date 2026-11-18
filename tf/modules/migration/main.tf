resource "google_service_account" "cloudbuild_migration" {
  account_id   = "${var.environment}-cloudbuild-migration"
  display_name = "Service Account for DB Migrations using Cloud Build (${var.environment})"
}

resource "google_secret_manager_secret_iam_member" "direct_url_access" {
  secret_id = var.direct_url_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloudbuild_migration.email}"
}

resource "google_project_iam_member" "migration_logging" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild_migration.email}"
}

resource "google_cloudbuild_trigger" "run_migration" {
  description = "Migration Trigger ${var.gh_repo_name} (${var.gh_branch_name}) ${var.environment}"

  github {
    push {
      branch = "^${var.gh_branch_name}$"
    }
    name  = var.gh_repo_name
    owner = var.gh_owner
  }

  filename        = "migration-cloudbuild.yaml"
  service_account = google_service_account.cloudbuild_migration.id

  substitutions = {
    _DIRECT_URL_SECRET_ID = "projects/${var.project}/secrets/${var.direct_url_secret_id}"
  }
}
