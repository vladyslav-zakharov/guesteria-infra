# NOTE: a GCP budget only ALERTS via email — it cannot cap or throttle spend.
# There is no native hard spend ceiling; this resource just gets the team
# notified early so a runaway (e.g. Vertex AI usage) can be stopped by hand.
resource "google_billing_budget" "budget" {
  billing_account = var.billing_account
  display_name    = "${var.environment}-${var.project}-budget"

  budget_filter {
    projects = ["projects/${var.project_number}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.amount
    }
  }

  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  # Forecasted spend so the alert lands before the money is actually gone,
  # not just after it's already spent.
  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # No all_updates_rule / pubsub_topic here: leaving notifications unset means
  # GCP falls back to its built-in behaviour of emailing the billing account's
  # existing admins and users — no extra channel wiring needed.
}
