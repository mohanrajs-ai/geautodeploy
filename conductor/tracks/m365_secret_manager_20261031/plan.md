# Implementation Plan: M365 Connectors & Secret Manager JSON Credentials Integration

## Phase 1: Terraform & Shell Secret Manager JSON Credential Integration [checkpoint: f3a0f55]
- [x] Task 1.1: Update `terraform-m365/` for Secret Manager JSON Provisioning & Lookup 3ae5779
    - [x] Write failing unit tests in `tests/test_m365_connectors.sh` asserting `m365_secret_id` in `terraform-m365/variables.tf`, `google_secret_manager_secret.m365_credentials`, `google_secret_manager_secret_version.m365_credentials_initial` (with JSON syntax `tenant_id`, `client_id`, `client_secret` and `ignore_changes = [secret_data]`), and `data.google_secret_manager_secret_version.m365_credentials_latest` in `terraform-m365/m365_connectors.tf`.
    - [x] Update `terraform-m365/variables.tf`, `terraform-m365/m365_connectors.tf`, and `terraform-m365/outputs.tf` to provision the Secret Manager secret with JSON syntax and wire `local.m365_secret_json` into all 4 M365 connector resources.
    - [x] Run `terraform -chdir=terraform-m365 fmt -check`, `terraform -chdir=terraform-m365 validate`, and `./tests/test_m365_connectors.sh`.
- [x] Task 1.2: Implement Secret Manager JSON Auto-Creation & Resolution in `scripts/configure_m365_connectors.sh` f3a0f55
    - [x] Write failing unit tests in `tests/test_m365_connectors.sh` verifying `M365_SECRET_ID` support in `load_m365_config()` and `validate_m365_config()`, and testing `ensure_and_load_m365_secret_credentials()` (creating the secret with JSON `{"tenant_id","client_id","client_secret"}` if missing and loading `versions/latest:access`).
    - [x] Update `configs/m365.env.example`, `scripts/configure_m365_connectors.sh`, and `deploy_m365.sh` to create/read the JSON secret from Secret Manager and populate `M365_TENANT_ID`, `M365_CLIENT_ID`, and `M365_CLIENT_SECRET` across all 4 M365 connectors and BAP actions.
    - [x] Run `./tests/test_m365_connectors.sh` and `CI=true ./tests/run_tests.sh` (>80% line coverage).

## Phase 2: Live `mohandemo` Secret Manager Migration & End-to-End Verification [checkpoint: e24c173]
- [x] Task 2.1: Provision `m365-connector-credentials` JSON Secret in `mohandemo`, Sanitize `configs/m365.env`, and Verify Live Rollout e24c173
    - [x] Run `./deploy_m365.sh --config configs/m365.env --curl-only` to create `projects/mohandemo/secrets/m365-connector-credentials` in Secret Manager with the JSON credentials.
    - [x] Remove plaintext `M365_CLIENT_SECRET` from `configs/m365.env` (using `M365_SECRET_ID="m365-connector-credentials"`) and re-run `./deploy_m365.sh --config configs/m365.env --curl-only` to verify all 4 M365 connectors (`m365-sp`, `m365-od-test`, `m365-ol-test`, `m365-teams-test`) load credentials from Secret Manager.
    - [x] Stage and commit all M365 suite files (`deploy_m365.sh`, `scripts/configure_m365_connectors.sh`, `terraform-m365/`, `configs/m365.env.example`, `payloads/m365_connector.json.tmpl`, `tests/test_m365_connectors.sh`) and run `CI=true ./tests/run_tests.sh`.
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) e24c173
