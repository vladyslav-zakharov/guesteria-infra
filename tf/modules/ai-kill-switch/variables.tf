variable "project" {
  description = "GCP Project ID"
  type        = string
}

variable "project_number" {
  description = "The GCP project number the kill-switch budget's filter is scoped to"
  type        = number
}

variable "billing_account" {
  description = "The Cloud Billing account ID the kill-switch budget is created under"
  type        = string
}

variable "environment" {
  description = "The environment to deploy resources (dev, prod, staging, test)"
  type        = string
}

variable "region" {
  description = "Region to deploy the Cloud Function (and its Eventarc trigger) into"
  type        = string
}

variable "amount" {
  description = "The monthly spend threshold in USD that fires the kill-switch. Unlike the budget module's amount, crossing this ACTUALLY disables target_services — it is not just an alert email."
  type        = number
  default     = 50
}

variable "enabled" {
  description = "Whether the kill-switch (budget, Pub/Sub topic, and Cloud Function) exists at all. Gates every resource in this module via count, so it can be turned off without deleting Terraform state."
  type        = bool
  default     = true
}

variable "target_services" {
  description = "The paid, per-request GCP APIs to disable when the kill-switch budget crosses its threshold. Defaults to Vertex AI, the one AI service with no global spend ceiling."
  type        = list(string)
  default     = ["aiplatform.googleapis.com"]
}
