# guesteria-infra

Terraform for the StayHub API (`guesteria-back`) on Google Cloud: Cloud Run, Cloud Build triggers for deploy and Prisma migrations, Secret Manager, a billing budget and an AI kill switch. The database is Supabase Postgres and the frontend is on Vercel; neither is managed here.

StayHub is a mobile web hotel-booking app with Guest Hub, a per-booking AI concierge on Gemini through Vertex AI. The other repos: [`guesteria-back`](https://github.com/vladyslav-zakharov/guesteria-back) (the API this repo deploys) and [`guesteria-front`](https://github.com/vladyslav-zakharov/guesteria-front) (the Next.js app and the reviewer entry point).

- **Deploy flow:** a push to `main` in `guesteria-back` fires the Cloud Build deploy trigger, which builds the image from `cloudbuild.yaml`, pushes it to Artifact Registry and deploys a new Cloud Run revision. Prisma migrations run from a separate trigger (`migration-cloudbuild.yaml`). The Vercel frontend reaches the API through its `/api` rewrite, so requests pass Vercel and the Google Front End before Cloud Run (`trust_proxy_hops = 2`).
- **Secrets:** only in Secret Manager. Terraform creates the secrets and generates the application secret; the database URLs, docs password and LiteAPI key are added as versions by hand (see the runbook). Cloud Run reads them as env vars; nothing secret is in `terraform.tfvars`.
- **AI cost guard:** the API caps concierge calls per user per UTC day (`ai_daily_limit` → `AI_DAILY_LIMIT`) and across all users (`AI_GLOBAL_DAILY_LIMIT`, back default); `ai_daily_limit = 0` turns the concierge off (the API answers 503). As a last resort, the `ai-kill-switch` module disables the Vertex AI API once monthly spend reaches `ai_kill_switch_budget_amount`.

## Infrastructure overview

| Module | What it creates |
| --- | --- |
| `project-api` | Enables the project APIs the other modules use. |
| `secret` | Secret Manager secrets: `<env>-application-secret` (random, versioned by Terraform), `<env>-database-url`, `<env>-direct-url`, `<env>-docs-password`, `<env>-liteapi-api-key` (versions added by hand). |
| `cloud-run` | The `guesteria-api` Cloud Run service (scale to zero, max 1 instance, CPU only during requests), its service account, the Artifact Registry repo and the deploy trigger (`cloudbuild.yaml` in `guesteria-back`). |
| `migration` | The migration trigger (`migration-cloudbuild.yaml` in `guesteria-back`) and its service account, which reads only `<env>-direct-url`. |
| `budget` | An alert-only billing budget. It emails the billing account's admins; it never caps spend. |
| `ai-kill-switch` | A second budget whose Pub/Sub notifications drive a Cloud Function that disables `aiplatform.googleapis.com` once spend reaches the threshold. |

Values for the `dev` environment live in `tf/dev/terraform.tfvars`: project `guesteria-stayhub`, region `europe-west1`, GitHub repo `vladyslav-zakharov/guesteria-back` on `main`. The project number and billing account live in the untracked `tf/dev/account.auto.tfvars` (copy it from `account.auto.tfvars.example`).

```
.
├── README.md
└── tf
    ├── dev
    │   ├── main.tf
    │   ├── outputs.tf
    │   ├── terraform.tfvars
    │   └── variables.tf
    └── modules
        ├── ai-kill-switch   (main.tf, variables.tf, function/)
        ├── budget
        ├── cloud-run
        ├── migration
        ├── project-api
        └── secret
```

## Apply runbook

Run every step from `tf/dev` unless stated otherwise. Every `gcloud` command passes `--project=guesteria-stayhub`. Never run `gcloud config set project` and never change the ADC quota project: the local gcloud config points at another project, and the provider block already sets `user_project_override = true` and `billing_project = var.project`.

### 0. Prerequisites

- Terraform `>= 1.10.5`, the gcloud CLI with beta components (`gcloud components install beta`).
- `gcloud auth login` and `gcloud auth application-default login`.
- The operator has Owner on the project (or Editor + Project IAM Admin + Service Account Admin + Secret Manager Admin + Artifact Registry Admin + Cloud Run Admin + Cloud Functions Admin + Pub/Sub Admin + Eventarc Admin + Storage Admin + Service Usage Admin) and Billing Account Administrator or Costs Manager on the project's billing account.
- The project is linked to that billing account:

```bash
gcloud billing projects describe guesteria-stayhub
```

- `tf/dev/account.auto.tfvars` exists. Copy `account.auto.tfvars.example` and fill in the project number and the billing account ID (drop the `billingAccounts/` prefix):

```bash
cp account.auto.tfvars.example account.auto.tfvars
gcloud projects describe guesteria-stayhub --format='value(projectNumber)'
gcloud billing projects describe guesteria-stayhub --format='value(billingAccountName)'
```

### 1. Bootstrap APIs

`serviceusage` and `cloudresourcemanager` are needed for any `google_project_service`, `storage` for the state bucket, `aiplatform` for Vertex AI. They were enabled on `guesteria-stayhub` on 2026-11-17; the step stays for a fresh project.

```bash
gcloud services enable \
  serviceusage.googleapis.com \
  cloudresourcemanager.googleapis.com \
  storage.googleapis.com \
  aiplatform.googleapis.com \
  --project=guesteria-stayhub
```

### 2. State bucket and backend

```bash
terraform init
terraform apply -target=google_storage_bucket.tfstate -target=local_file.backend
terraform init -migrate-state
```

The targeted apply creates the GCS state bucket and writes `backend.tf`. Answer `yes` to the migration prompt. Never use `-reconfigure` here: it drops the local state instead of copying it.

### 3. Project APIs

```bash
terraform apply -target=module.project_api
```

`module.secret` depends on `module.project_api`, so the targeted apply in the next step would enable the APIs anyway. Applying them first keeps that step's plan limited to the secrets.

### 4. Secret containers

```bash
terraform apply -target=module.secret
```

This creates `dev-application-secret` with a Terraform-generated version and four empty secrets: `dev-database-url`, `dev-direct-url`, `dev-docs-password`, `dev-liteapi-api-key`.

### 5. Cloud Build service-agent grant

Both triggers run as user-specified service accounts, so the Cloud Build service agent must be able to mint tokens for them. Without this grant the first build fails with `permission_denied on iam.serviceAccounts.getAccessToken`.

```bash
gcloud beta services identity create --service=cloudbuild.googleapis.com --project=guesteria-stayhub
PROJECT_NUMBER="$(gcloud projects describe guesteria-stayhub --format='value(projectNumber)')"
gcloud projects add-iam-policy-binding guesteria-stayhub \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-cloudbuild.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountTokenCreator"
```

### 6. Secret versions

Cloud Run reads every secret at version `latest` and fails the revision if a version is missing, so all of them must exist before the full apply. The values come from `guesteria-back/.env` and are never printed. Run from the workspace root (the folder that holds `guesteria-back`). The user runs this block, or an agent with the user's explicit go-ahead.

```bash
eval "$(grep -E '^(SUPABASE_|LITEAPI_API_KEY=)' guesteria-back/.env)"
printf '%s' "$SUPABASE_DATABASE_URL" | gcloud secrets versions add dev-database-url --data-file=- --project=guesteria-stayhub
printf '%s' "$SUPABASE_DIRECT_URL"   | gcloud secrets versions add dev-direct-url   --data-file=- --project=guesteria-stayhub
printf '%s' "$LITEAPI_API_KEY"       | gcloud secrets versions add dev-liteapi-api-key --data-file=- --project=guesteria-stayhub
openssl rand -base64 24 | tr -d '\n' | gcloud secrets versions add dev-docs-password --data-file=- --project=guesteria-stayhub
```

- `dev-database-url` is the Supabase **transaction pooler** URL, port `6543`, with `?pgbouncer=true&connection_limit=1`. Cloud Run uses it at runtime.
- `dev-direct-url` is the Supabase **session pooler** URL, port `5432`, no query parameters. Prisma migrations use it.
- Never use the Supabase direct host `db.<ref>.supabase.co`: it is IPv6-only and Cloud Run and Cloud Build egress is IPv4.
- Do not add a version to `dev-application-secret`; Terraform owns it.
- The secret IDs carry the `dev-` prefix from the `secret` module (`${var.environment}-...`).

### 7. Protect `main` in `guesteria-back`

Every push to `main` of `guesteria-back` deploys a new image and runs `prisma migrate deploy` against Supabase, and Cloud Build does not wait for GitHub Actions. A migration has no down step, so CI that fails a minute later cannot undo it. Protect the branch before the triggers exist:

GitHub → `guesteria-back` → Settings → Branches → Add branch protection rule for `main`:

- Require a pull request before merging.
- Require status checks to pass before merging, with these checks from `.github/workflows/`: `build (22.x)` (workflow `Lint & Build`, `build.yml`), `test (22.x)` (workflow `Unit Tests`, `unit-test.yml`) and `integration-test (22.x)` (workflow `Integration Tests`, `integration-test.yml`). The jobs use a `node-version` matrix, so GitHub lists each check with the matrix value; a check appears in the picker only after it has run once on the repo.
- Do not allow bypassing the above settings, so direct pushes to `main` are blocked for admins too.

### 8. Connect GitHub to Cloud Build

Cloud Console → Cloud Build → Repositories → **1st gen** → Connect repository → GitHub (Cloud Build GitHub App) → personal account `vladyslav-zakharov` → repository `guesteria-back` only. Done on 2026-11-18 for `guesteria-stayhub`; the step stays for a fresh project. Without it, trigger creation in the next step fails with a repository-not-connected error.

### 9. Full apply

```bash
terraform apply
```

This creates Cloud Run (placeholder image), both Cloud Build triggers (`github { owner = "vladyslav-zakharov", name = "guesteria-back" }`), the budget and the AI kill switch. Cloud Run waits for its secret access grants in the graph, but IAM propagation can still lag: if the Cloud Run create fails once on secret access, run `terraform apply` again.

### 10. Application URL

```bash
terraform output api_url
```

Put the URL into `cloud_run_application_url` in `terraform.tfvars` (replacing `REPLACE_ME`) and run `terraform apply` again.

### 11. First build and migration

Merge a pull request into `main` of `guesteria-back`. The deploy trigger builds the image and points Cloud Run at it; the migration trigger runs `prisma migrate deploy` in parallel. Confirm both builds succeeded before treating the service as ready:

```bash
gcloud builds list --project=guesteria-stayhub --limit=5
```

### 12. Placeholder image

`cloud_run_set_dummy_image = true` gives the service the placeholder image when step 9 creates it, because Artifact Registry is still empty. After the first deploy the flag no longer matters: the image, the revision name and the template annotations and labels are in the service's `ignore_changes`, so Cloud Build owns the image and a later `terraform apply` neither reverts it nor rolls a new revision. Leave the flag as it is. It is read again only if the service is re-created.

### 13. Vercel

Set `BACKEND_API_URL` in the Vercel project `guesteria-front` (Production and Preview) to the Cloud Run URL before the first frontend push. `frontend_url` is already `https://guesteria-front.vercel.app`, so CORS needs no extra apply.

## AI kill switch

The `budget` module only sends emails. The `ai-kill-switch` module creates a separate budget (`ai_kill_switch_budget_amount`, USD per month) that publishes every spend update to Pub/Sub. A Cloud Function reads `costAmount / budgetAmount` from each notification, ignores notifications from other budgets, and once the ratio reaches `1.0` disables `aiplatform.googleapis.com` through the Service Usage API. Billing, Cloud Run, the database and the rest of the API keep working; only the AI features stop.

Recovery, once the cost issue is resolved:

```bash
gcloud services enable aiplatform.googleapis.com --project=guesteria-stayhub
```

**Any `terraform apply` re-enables a killed `aiplatform` API.** `project-api` manages `aiplatform.googleapis.com` as a `google_project_service`, so the next apply, for any reason, sees the drift and turns the API back on. If the kill switch has fired, resolve the cost issue before running any apply against this project.

To remove the kill switch without touching state, set `ai_kill_switch_enabled = false` and apply.

## Rollback

Each Cloud Build deploy creates a new revision and sends it 100% of traffic. To go back, list the revisions and route all traffic to the last good one:

```bash
gcloud run revisions list --service=guesteria-api --region=europe-west1 --project=guesteria-stayhub
gcloud run services update-traffic guesteria-api --to-revisions=<revision>=100 --region=europe-west1 --project=guesteria-stayhub
```

This only switches the code. A migration that already ran stays applied, so the old revision must still work with the current schema.

Traffic is now pinned to that revision. Later deploys still create revisions, but they get 0% of traffic and nothing reports it. Once the fix is merged and deployed, send traffic back to the latest revision:

```bash
gcloud run services update-traffic guesteria-api --to-latest --region=europe-west1 --project=guesteria-stayhub
```

Terraform does not declare `traffic` on the service. While traffic is pinned, check `terraform plan` before any apply and do not apply if it changes `traffic`.

## Adding a secret environment variable

1. Add a `google_secret_manager_secret` and its `*_secret_id` output to `tf/modules/secret/main.tf`.
2. Map it in `secret_vars` of `module "cloud_run"` in `tf/dev/main.tf`. The module grants the Cloud Run service account `roles/secretmanager.secretAccessor` on every secret in that map.
3. `terraform apply -target=module.secret`, add a version with `printf '%s' ... | gcloud secrets versions add ... --data-file=- --project=guesteria-stayhub`, then `terraform apply`.

## Teardown

1. Disable the kill switch first so it cannot fire mid-teardown: set `ai_kill_switch_enabled = false`, `terraform apply`.
2. Move state back to local, because `terraform destroy` deletes the bucket that holds it: delete `backend.tf`, then `terraform init -migrate-state` and answer `yes`.
3. `terraform destroy`. Cloud Run has `deletion_protection = false`. The state bucket has `force_destroy = false`; if the destroy stops on it, empty it with `gcloud storage rm -r "gs://<bucket>/**" --project=guesteria-stayhub` and run `terraform destroy` again.
4. APIs stay enabled (`disable_on_destroy = false`). Secret versions added by hand are deleted together with their secrets.

## Related documentation

- [General style and structure guidelines](https://cloud.google.com/docs/terraform/best-practices/general-style-structure)
- [Root modules](https://cloud.google.com/docs/terraform/best-practices/root-modules)
- [Budget notification format](https://cloud.google.com/billing/docs/how-to/budget-notifications-format)
