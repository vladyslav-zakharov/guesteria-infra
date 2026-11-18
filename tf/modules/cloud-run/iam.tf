resource "google_cloud_run_service_iam_binding" "cloud_run_invoker" {
  service = google_cloud_run_v2_service.node-api.name
  role    = "roles/run.invoker"
  members = [
    "allUsers"
  ]

  depends_on = [google_cloud_run_v2_service.node-api]
}

// Cloud Run Service Account

resource "google_service_account" "cloud_run_sa" {
  account_id   = "${var.environment}-cloud-run-sa"
  display_name = "Service Account for Cloud Run"
}

resource "google_project_iam_member" "cloud_run_logging" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Lets the Cloud Run SA call Vertex AI (Gemini) for the AI features of the API.
resource "google_project_iam_member" "cloud_run_aiplatform" {
  project = var.project
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "dynamic_access" {
  for_each = var.secret_vars

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

// Cloud Build Service Account

resource "google_service_account" "cloud_build" {
  account_id   = "${var.environment}-cloud-build-sa"
  display_name = "Custom Service Account for Cloud Build"
}

resource "google_service_account_iam_member" "cloud_build_act_as_run_sa" {
  service_account_id = google_service_account.cloud_run_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_artifact" {
  project = var.project
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_run" {
  project = var.project
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_logging" {
  project = var.project
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}
