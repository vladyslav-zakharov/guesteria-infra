resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudbuild" {
  service            = "cloudbuild.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Powers the Gemini calls the API makes through Vertex AI.
# This is also the ai-kill-switch target: any apply re-enables it after the kill switch disabled it.
resource "google_project_service" "aiplatform" {
  service            = "aiplatform.googleapis.com"
  disable_on_destroy = false
}

# Powers the Cloud Billing budgets (budget and ai-kill-switch modules).
resource "google_project_service" "billingbudgets" {
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

# Required by the Google provider to manage the billing budgets alongside billingbudgets.googleapis.com.
resource "google_project_service" "cloudbilling" {
  service            = "cloudbilling.googleapis.com"
  disable_on_destroy = false
}

# Powers the ai-kill-switch Cloud Function (Gen2) that disables paid AI APIs on overspend.
resource "google_project_service" "cloudfunctions" {
  service            = "cloudfunctions.googleapis.com"
  disable_on_destroy = false
}

# Powers the Eventarc trigger that connects the kill-switch budget's Pub/Sub topic to the Cloud Function.
resource "google_project_service" "eventarc" {
  service            = "eventarc.googleapis.com"
  disable_on_destroy = false
}

# Powers the Pub/Sub topic the kill-switch budget publishes notifications to (ai-kill-switch module).
resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = false
}

# Powers the Service Usage API the ai-kill-switch function calls to disable target APIs.
resource "google_project_service" "serviceusage" {
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = false
}
