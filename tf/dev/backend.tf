terraform {
  backend "gcs" {
    bucket = "dev-guesteria-stayhub-guesteria-api-tfstate"
  }
}
