# Terraform & Infrastructure Style Guide (`infra/`)

## 1. Stack Isolation & State Safety
- **Isolated Stacks by Lifecycle (`infra/stacks/`):**
  - `01-identity-foundation` (`infra/terraform-identity`): Organization/Tenant-level Workforce Identity Pool, OIDC/SAML Provider, and Location ACL config.
  - `02-ge-app-instance` (`infra/terraform`): Per-application Discovery Engine `SEARCH_AND_ASSISTANT` engine and initial GCS/BigQuery data stores.
  - `03-m365-connectors` (`infra/terraform-m365`): Microsoft 365 Federated Graph Connectors (SharePoint, Exchange/Outlook, Teams, OneDrive).
- **Per-Instance Workspace / State Prefix Isolation:**
  - Never overwrite a shared default `terraform.tfstate` when provisioning a second Gemini Enterprise App. Always select or create a dedicated workspace (`<location>-<engine_id>`) or GCS state prefix before running `plan`/`apply`.

## 2. Variables, Secrets & Formatting
- Run `terraform fmt -check` and `terraform validate` before committing `.tf` changes.
- Mark all credentials (`m365_client_secret`, `wif_oidc_client_secret`) with `sensitive = true` in `variables.tf`.
- Never write plaintext secrets to committed `.tfvars` or `.env` files; pass secrets via ephemeral `TF_VAR_*` environment variables at runtime and redact them from SSE/log streams.
