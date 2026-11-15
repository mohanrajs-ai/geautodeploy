# Track Specification: Microsoft Entra ID to Google Cloud Identity Entity Sync & SSO (`entra_cloud_identity_sync_20261103`)

## 1. Overview
This feature track introduces a standalone, automated Microsoft Entra ID to Google Cloud Identity synchronization and SSO provisioning suite (`deploy_identity.sh`, `scripts/configure_identity.sh`, `terraform-identity/`, `configs/identity.env`, and `tests/test_identity.sh`).

It reuses the existing JSON-formatted credentials stored in Google Cloud Secret Manager (`projects/mohandemo/secrets/m365-connector-credentials`: `{"tenant_id","client_id","client_secret"}` for Entra App Registration `argolis-msft`) and aligns Microsoft Entra ID (`10a65113-9363-432b-bd99-a575f3337dd2`) and Google Cloud Identity (`customers/C00x1gdg6`) on the shared custom domain **`mohanrajs.demo.altostrat.com`** (hosted in Cloud DNS project `mohan-dns`, managed zone `mohanrajs-demo`).

## 2. Functional Requirements

### FR1: Shared Secret Manager Credentials Resolution
1. Both `terraform-identity/` (`data.google_secret_manager_secret_version.m365_credentials_latest`) and `scripts/configure_identity.sh` (`ensure_and_load_identity_secret_credentials`) must read the JSON secret (`m365-connector-credentials`) from Google Cloud Secret Manager:
   ```json
   {
     "tenant_id": "<entra-tenant-id>",
     "client_id": "<entra-app-client-id>",
     "client_secret": "<entra-app-client-secret>"
   }
   ```
2. No plaintext `client_secret` values may be stored in `configs/identity.env` or `configs/identity.env.example`.

### FR2: Automated Entra ID Bulk UPN Domain Migration (`@1771sp.onmicrosoft.com` -> `@mohanrajs.demo.altostrat.com`)
1. When `ENTRA_BULK_UPDATE_UPN_DOMAIN="true"`, `scripts/configure_identity.sh` must query Microsoft Graph (`/v1.0/users`) using the OAuth2 `client_credentials` token obtained from `m365-connector-credentials`.
2. For each Entra ID user whose `userPrincipalName` ends with `@${ENTRA_SOURCE_DOMAIN}` (`1771sp.onmicrosoft.com`)—and who is not listed in `ENTRA_UPN_REWRITE_EXCLUDE_USERS` (to protect break-glass Global Admin accounts)—the script must execute an idempotent `PATCH https://graph.microsoft.com/v1.0/users/{id}` updating:
   - `userPrincipalName`: `<mailNickname>@${SHARED_IDENTITY_DOMAIN}` (`@mohanrajs.demo.altostrat.com`)
   - `mail`: `<mailNickname>@${SHARED_IDENTITY_DOMAIN}` (`@mohanrajs.demo.altostrat.com`)

### FR3: Microsoft Graph Entity Discovery & Cloud Identity User/Group Sync
1. `scripts/configure_identity.sh` must discover Entra ID Users (`/v1.0/users`), Security/M365 Groups (`/v1.0/groups`), and transitive Group Memberships (`/v1.0/groups/{id}/transitiveMembers`).
2. When `SYNC_CLOUD_IDENTITY_USERS="true"`, `scripts/configure_identity.sh` must idempotently provision/update corresponding user accounts in Google Cloud Identity (`admin.googleapis.com/admin/directory/v1/users`) under `@mohanrajs.demo.altostrat.com` (or fallback domain `@mohanrajs.altostrat.com` when configured).
3. `scripts/configure_identity.sh` must generate `terraform-identity/identity_entities.auto.tfvars.json` containing the discovered Entra groups, normalized member emails, and Entra-to-Gemini-Enterprise Per-App Group mappings (`ENTRA_TO_APP_GROUP_MAPPINGS`, e.g., mapping Entra groups into `finance-app-01-users@mohanrajs.altostrat.com`, `hr-app-01-users@mohanrajs.altostrat.com`, etc.).

### FR4: Separate Terraform Module (`terraform-identity/`)
1. Create a dedicated `terraform-identity/` directory (`versions.tf`, `variables.tf`, `identity.tf`, `outputs.tf`) isolated from the core app and M365 connector states.
2. Manage the following declarative resources:
   - **Secret Manager Data Source:** `data.google_secret_manager_secret_version.m365_credentials_latest` reading `m365-connector-credentials`.
   - **Cloud DNS Domain Verification Record (Optional/Toggleable via `manage_dns_verification_record`):** `google_dns_record_set` on `mohanrajs.demo.altostrat.com.` in project `mohan-dns` (zone `mohanrajs-demo`) preserving `"MS=ms62188609"` and appending `"google-site-verification=..."` when provided.
   - **Synced Entra Security Groups in Cloud Identity:** `google_cloud_identity_group` (`for_each = var.synced_groups`) under `customers/C00x1gdg6` with `cloudidentity.googleapis.com/groups.security` and `cloudidentity.googleapis.com/groups.discussion_forum` labels.
   - **Synced Group Memberships:** `google_cloud_identity_group_membership` (`for_each`) adding synced users to their corresponding Cloud Identity groups.
   - **Gemini Enterprise Per-App Group Nesting:** `google_cloud_identity_group_membership` (`for_each`) nesting synced Entra groups (or mapped users) into the target Gemini Enterprise per-app groups (`<app-id>-users@mohanrajs.altostrat.com`).
   - **Cloud Identity Inbound SAML SSO Profile (Optional/Toggleable via `enable_inbound_saml_sso`):** `google_cloud_identity_inbound_saml_sso_profile` for Entra ID SAML federation alongside OIDC SSO profile automation in `scripts/configure_identity.sh`.

### FR5: Standalone Master Entrypoint (`deploy_identity.sh`) & Config (`configs/identity.env`)
1. Provide `deploy_identity.sh` supporting `--config <path>`, `--dry-run`, and `--skip-terraform` flags with structured `[PRE-FLIGHT]`, `[ENTRA-GRAPH-SYNC]`, `[TERRAFORM-IDENTITY]`, `[CLOUD-IDENTITY-SSO]`, `[VERIFY]`, and `[SUMMARY]` phases.
2. Verify and ensure Discovery Engine global/regional `aclConfig` is configured with `idpType: GSUITE` (Cloud Identity).

## 3. Non-Functional Requirements
- **Zero Secret Leakage:** Never log or echo raw `client_secret`, Microsoft Graph access tokens, or GCP bearer tokens.
- **Idempotency & Resilience:** Gracefully handle HTTP 409 (`ALREADY_EXISTS`) on Cloud Identity users/groups/memberships and provide actionable remediation guidance if Microsoft Graph returns `Authorization_RequestDenied` (missing `User.ReadWrite.All` / `Group.Read.All` admin consent).
- **Test Coverage:** Unit and dry-run test suite (`tests/test_identity.sh`) integrated into `tests/run_tests.sh` achieving `>80%` line coverage.

## 4. Acceptance Criteria
1. `terraform -chdir=terraform-identity fmt -check` and `terraform -chdir=terraform-identity validate` pass with zero errors.
2. `./deploy_identity.sh --config configs/identity.env.example --dry-run` executes end-to-end without error.
3. `tests/test_identity.sh` and `CI=true ./tests/run_tests.sh` pass with `>80%` coverage.
4. `docs/entra-cloud-identity-design.md` and `README.md` document the architecture, Microsoft Entra Admin Portal prerequisites, Google Admin Console domain verification steps, and CLI usage.

## 5. Out of Scope
- Modifying the core Gemini Enterprise engine provisioning logic in `terraform/` or `terraform-m365/`.
- Automated DNS registration of new top-level domains outside `mohanrajs.demo.altostrat.com`.
