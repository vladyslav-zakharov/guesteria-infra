variable "billing_account" {
  description = "The Cloud Billing account ID the budget is created under (e.g. \"XXXXXX-XXXXXX-XXXXXX\")"
  type        = string
}

variable "project" {
  description = "GCP Project ID"
  type        = string
}

variable "project_number" {
  description = "The GCP project number the budget's filter is scoped to"
  type        = number
}

variable "environment" {
  description = "The environment to deploy resources (dev, prod, staging, test)"
  type        = string
}

variable "amount" {
  description = "The budget amount in whole units of currency_code (USD). This only triggers alert emails — it does not cap or throttle spend."
  type        = number
}
