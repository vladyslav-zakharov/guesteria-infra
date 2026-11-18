resource "random_password" "app_secret" {
  length  = 40
  special = true
}

resource "google_secret_manager_secret" "application_secret" {
  secret_id = "${var.environment}-application-secret"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "application_secret" {
  secret      = google_secret_manager_secret.application_secret.id
  secret_data = random_password.app_secret.result
}

# Supabase transaction-pooler URL (port 6543) — used by Cloud Run at runtime.
# No version is created here; add one manually after apply:
#   gcloud secrets versions add <env>-database-url --data-file=-
resource "google_secret_manager_secret" "database_url" {
  secret_id = "${var.environment}-database-url"
  replication {
    auto {}
  }
}

# Supabase session-pooler URL (port 5432) — used by Prisma migrate at CI time.
# No version is created here; add one manually after apply:
#   gcloud secrets versions add <env>-direct-url --data-file=-
resource "google_secret_manager_secret" "direct_url" {
  secret_id = "${var.environment}-direct-url"
  replication {
    auto {}
  }
}

# Swagger UI (/api/docs) basic-auth password — used by Cloud Run at runtime.
# No version is created here; add one manually after apply:
#   gcloud secrets versions add <env>-docs-password --data-file=-
resource "google_secret_manager_secret" "docs_password" {
  secret_id = "${var.environment}-docs-password"
  replication {
    auto {}
  }
}

# LiteAPI key — billable credential for hotel search, rates and bookings.
# No version is created here; add one manually after apply:
#   gcloud secrets versions add <env>-liteapi-api-key --data-file=-
resource "google_secret_manager_secret" "liteapi_api_key" {
  secret_id = "${var.environment}-liteapi-api-key"
  replication {
    auto {}
  }
}

output "application_secret" {
  value = google_secret_manager_secret.application_secret.secret_id
}

output "database_url_secret_id" {
  value = google_secret_manager_secret.database_url.secret_id
}

output "direct_url_secret_id" {
  value = google_secret_manager_secret.direct_url.secret_id
}

output "docs_password_secret_id" {
  value = google_secret_manager_secret.docs_password.secret_id
}

output "liteapi_api_key_secret_id" {
  value = google_secret_manager_secret.liteapi_api_key.secret_id
}
