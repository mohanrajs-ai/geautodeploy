# Specification: M365 Connectors & Secret Manager JSON Credentials Integration

## 1. Overview
Formalize the Microsoft 365 (M365) Data Connectors deployment suite (`deploy_m365.sh`, `scripts/configure_m365_connectors.sh`, `terraform-m365/`, `configs/m365.env.example`, and `tests/test_m365_connectors.sh`) under Conductor and refactor all M365 Entra ID credentials (`tenant_id`, `client_id`, `client_secret`) to be provisioned in and dynamically read from **Google Cloud Secret Manager** using a single JSON-formatted secret (`M365_SECRET_ID="m365-connector-credentials"`).

## 2. Functional Requirements
1. **Google Cloud Secret Manager Provisioning (JSON Format):**
   - Enable `secretmanager.googleapis.com` in the target project.
   - Automatically create the Secret Manager secret specified by `M365_SECRET_ID` (default: `m365-connector-credentials`) if it does not exist.
   - When creating the initial secret version, populate it with valid JSON syntax:
     ```json
     {
       "tenant_id": "<M365_TENANT_ID_or_placeholder>",
       "client_id": "<M365_CLIENT_ID_or_placeholder>",
       "client_secret": "<M365_CLIENT_SECRET_or_placeholder>"
     }
     ```
   - Preserve external admin updates: once the initial JSON version exists, never overwrite newer versions added by a Deployment Admin in Google Cloud Console or `gcloud secrets versions add`.
2. **Dynamic Credential Resolution in `scripts/configure_m365_connectors.sh` & `deploy_m365.sh`:**
   - Implement `ensure_and_load_m365_secret_credentials()` in `scripts/configure_m365_connectors.sh` to:
     1. Ensure the Secret (`projects/${GCP_PROJECT_ID}/secrets/${M365_SECRET_ID}`) and an initial JSON version exist via the Secret Manager REST API (`https://secretmanager.googleapis.com/v1`).
     2. Fetch `versions/latest:access`, base64-decode the JSON payload, validate the JSON keys (`tenant_id`, `client_id`, `client_secret`), and populate `M365_TENANT_ID`, `M365_CLIENT_ID`, `M365_CLIENT_SECRET`, and `TF_VAR_*` in memory.
   - Ensure `render_m365_connector_payload()` and `activate_m365_connector_actions()` use the Secret Manager JSON credentials across all 4 M365 connectors (SharePoint Online, OneDrive, Outlook, Microsoft Teams).
3. **Terraform Secret Manager Integration (`terraform-m365/`):**
   - Add `m365_secret_id` variable (default `"m365-connector-credentials"`) to `terraform-m365/variables.tf` and make `m365_client_secret` optional with a placeholder default for initial bootstrap.
   - Add `google_project_service.secretmanager`, `google_secret_manager_secret.m365_credentials`, and `google_secret_manager_secret_version.m365_credentials_initial` (with `lifecycle { ignore_changes = [secret_data] }`) in `terraform-m365/m365_connectors.tf`.
   - Read the active credentials from Secret Manager (`jsondecode(...)`) to configure `sharepoint`, `onedrive`, `outlook`, and `teams` connectors.
4. **Configuration & Live `mohandemo` Migration:**
   - Update `configs/m365.env.example` and `configs/m365.env` to configure `M365_SECRET_ID="m365-connector-credentials"` and remove plaintext `M365_CLIENT_SECRET` from `configs/m365.env`.
   - Provision `projects/mohandemo/secrets/m365-connector-credentials` in `mohandemo` with the JSON credentials and verify `./deploy_m365.sh --config configs/m365.env --curl-only` succeeds end-to-end.

## 3. Non-Functional Requirements
- **Zero Plaintext Secret Leakage:** Never log `client_secret` or base64 secret payloads in stdout or log files, including in `--dry-run` mode.
- **Test Coverage:** Maintain >80% line coverage across all shell scripts in `CI=true ./tests/run_tests.sh`.

## 4. Acceptance Criteria
- [ ] `projects/mohandemo/secrets/m365-connector-credentials` is created in Secret Manager with JSON syntax `{"tenant_id": "...", "client_id": "...", "client_secret": "..."}`.
- [ ] Plaintext `M365_CLIENT_SECRET` is removed from `configs/m365.env`.
- [ ] Both `terraform-m365/` and `scripts/configure_m365_connectors.sh` create the JSON secret if missing and read `tenant_id`, `client_id`, and `client_secret` from `versions/latest`.
- [ ] `./deploy_m365.sh --config configs/m365.env --curl-only` and `CI=true ./tests/run_tests.sh` pass with 0 errors.
