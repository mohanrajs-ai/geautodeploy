# Technology Stack: Gemini Enterprise App Deployment Automation

## 1. Programming & Scripting Languages
- **Bash (Bash 4.0+ / POSIX-compatible shell):**
  - Primary orchestration language for the master entrypoint (`deploy.sh`), pre-flight checks, `curl` REST API wrappers, and post-deployment verification.
  - Strict execution mode (`set -euo pipefail`) enforced across all scripts.
- **HCL (HashiCorp Configuration Language — Terraform >= 1.5):**
  - Declarative Infrastructure-as-Code language for all supported Google Cloud and Discovery Engine resources.

## 2. Provisioning Engines, Providers & APIs
- **Terraform Providers:**
  - `hashicorp/google` (`>= 5.0`) — Core GCP resources (project services/APIs, Cloud Identity groups & memberships via `google_cloud_identity_group` / `google_cloud_identity_group_membership`, GCS buckets, BigQuery datasets).
  - `hashicorp/google-beta` (`>= 5.0`) — Discovery Engine / Gemini Enterprise resources (`google_discovery_engine_data_store`, `google_discovery_engine_search_engine`, `google_discovery_engine_chat_engine`, etc.).
- **Google Cloud REST APIs (invoked via `curl`):**
  - **Discovery Engine API (`v1` / `v1alpha` / `v1beta`):** Regional and global endpoints (`https://discoveryengine.googleapis.com` and `https://<location>-discoveryengine.googleapis.com`) for Gemini Enterprise app creation, enterprise connector configuration, ACLs, Engine-level IAM policy (`:getIamPolicy` / `:setIamPolicy`), and agent registration where Terraform provider coverage is unavailable.
  - **Cloud Identity Groups & Inbound SSO APIs (`v1` / `v1beta1`):** `https://cloudidentity.googleapis.com/v1/groups` for idempotent per-app and synced Entra group lookup, creation, and membership management, plus `inboundSamlSsoProfiles` / `inboundOidcSsoProfiles` (`google_cloud_identity_inbound_saml_sso_profile` in `terraform-identity/`) for federated SSO.
  - **Admin SDK Directory API (`directory_v1`):** `https://admin.googleapis.com/admin/directory/v1/users` for idempotent synchronization of Entra ID users into Google Cloud Identity.
  - **Cloud DNS API (`v1`):** `https://dns.googleapis.com/dns/v1` and `google_dns_record_set` in `terraform-identity/` for managing shared custom domain (`mohanrajs.demo.altostrat.com`) verification TXT records across Microsoft Entra ID and Google Cloud Identity.
  - **Microsoft Graph REST API (`v1.0`):** `https://graph.microsoft.com/v1.0` (`/users`, `/groups`, `/groups/{id}/transitiveMembers`) and Microsoft identity platform OAuth2 token endpoint (`https://login.microsoftonline.com/{tenant_id}/oauth2/v2.0/token`) for automated UPN domain migration (`@1771sp.onmicrosoft.com` -> `@mohanrajs.demo.altostrat.com`) and entity discovery.
  - **Secret Manager API (`v1`):** `https://secretmanager.googleapis.com/v1/projects/{project}/secrets` (and Terraform `google_secret_manager_secret` / `google_secret_manager_secret_version`) for storing and resolving JSON-formatted Microsoft 365 Entra ID credentials (`tenant_id`, `client_id`, `client_secret`).
- **Google Cloud SDK (`gcloud` CLI):**
  - Authentication token generation (`gcloud auth print-access-token`), project/account verification, and pre-flight checks.

## 3. Operator Interface & CLI Utilities
- **CLI / Terminal Interface (`deploy.sh` + Single Config File):**
  - Headless and interactive terminal execution designed for Google Cloud Shell, Linux, and macOS.
  - Centralized configuration via a single file (e.g., `config.env` synced with `terraform.tfvars`).
- **Core CLI Dependencies:**
  - `curl` — Executing authenticated HTTP REST calls (`GET`, `POST`, `PATCH`, `DELETE`).
  - `jq` — Constructing safe JSON request payloads and parsing REST API / `terraform output -json` responses.
  - `envsubst` / standard shell parameter expansion — Rendering JSON payload templates when needed.

## 4. State Management & Target Data Sources
- **Terraform State Management:**
  - **Default:** Local state (`terraform.tfstate`) for immediate, zero-setup execution in customer environments.
  - **Optional Production Mode:** Remote Google Cloud Storage (GCS) backend support configurable via the customer config file.
- **Target Gemini Enterprise Data Stores:**
  - Google Cloud Storage (GCS) unstructured/structured data stores.
  - BigQuery datasets and tables.
  - Website search & First-/Third-Party Enterprise Connectors.

## 5. Testing, Linting & Quality Tooling
- **Terraform Validation:** `terraform fmt -check`, `terraform validate`, and `tflint` (when available).
- **Shell Validation:** `shellcheck` for static analysis and `bats` (Bash Automated Testing System) or dry-run harness tests for script verification.
