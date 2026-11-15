# Implementation Plan: Per-App Cloud Identity Group Creation & Exclusive App Access Control

## Phase 1: Configuration Schema & Terraform Group / IAM Refactoring [checkpoint: f694137]
- [x] Task 1.1: Update Configuration Loader & App Environment Files (`config.env`, `configs/*.env`, `scripts/lib/common.sh`) 34bb222
    - [x] Write failing unit tests in `tests/test_common.sh` verifying default derivation of `GE_CUSTOMER_DOMAIN`, `GE_APP_ACCESS_GROUP` (`<GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>`), `GE_APP_GROUP_MEMBERS`, and `TF_VAR_*` exports.
    - [x] Implement `GE_CUSTOMER_DOMAIN`, `GE_CLOUD_IDENTITY_CUSTOMER_ID`, `GE_APP_ACCESS_GROUP`, and `GE_APP_GROUP_MEMBERS` defaults and exports in `scripts/lib/common.sh`.
    - [x] Update `config.env`, `config.env.example`, and `configs/{hr,marketing,ops,sales,service_desk}.env` with per-app group configuration variables.
    - [x] Run `CI=true ./tests/run_tests.sh` to verify Green phase.
- [x] Task 1.2: Refactor Terraform IAM & Add Cloud Identity Group Support (`terraform/apis_and_iam.tf`, `terraform/variables.tf`, `terraform/outputs.tf`) f694137
    - [x] Write failing tests in `tests/test_terraform.sh` asserting `cloudidentity.googleapis.com` is in `required_apis`, project-level `google_project_iam_member.ge_viewers` is removed, `google_cloud_identity_group` is defined, and `app_access_group` output exists.
    - [x] Update `terraform/variables.tf`, `terraform/apis_and_iam.tf`, and `terraform/outputs.tf` to remove project-level `roles/discoveryengine.viewer` bindings and add Cloud Identity API + per-app group resource definitions.
    - [x] Run `terraform fmt -check`, `terraform validate`, and `CI=true ./tests/run_tests.sh`.

## Phase 2: Cloud Identity Group Provisioning & Exclusive Engine-Level IAM Enforcement (`curl` REST API) [checkpoint: e536a39]
- [x] Task 2.1: Implement Idempotent Cloud Identity Group & Membership Provisioning (`scripts/configure_ge_app.sh`) 88d2baa
    - [x] Write failing unit tests in `tests/test_curl_modules.sh` verifying `ensure_app_cloud_identity_group()` (auto-discovering `directoryCustomerId`, looking up/creating `<GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>` via Cloud Identity v1 API, and syncing `GE_APP_GROUP_MEMBERS`).
    - [x] Implement `render_cloud_identity_group_payload()`, `render_cloud_identity_membership_payload()`, and `ensure_app_cloud_identity_group()` in `scripts/configure_ge_app.sh`.
    - [x] Run `CI=true ./tests/run_tests.sh` to verify tests pass.
- [x] Task 2.2: Implement Exclusive Engine-Level IAM Policy & Project-Level Access Revocation (`scripts/configure_ge_app.sh`) e536a39
    - [x] Write failing unit tests in `tests/test_curl_modules.sh` verifying `revoke_project_level_ge_access()` (pruning project-wide `roles/discoveryengine.user` and `roles/discoveryengine.viewer` bindings) and `configure_engine_exclusive_group_iam()` (setting `engines/${GE_APP_ID}:setIamPolicy` exclusively to `group:${GE_APP_ACCESS_GROUP}`).
    - [x] Implement `render_engine_iam_policy_payload()`, `revoke_project_level_ge_access()`, and `configure_engine_exclusive_group_iam()` in `scripts/configure_ge_app.sh` and wire them into `configure_gemini_enterprise_app()`.
    - [x] Run `CI=true ./tests/run_tests.sh` to verify tests pass.

## Phase 3: Post-Deployment Verification & Live Multi-App Rollout (`mohandemo`) [checkpoint: 4652d4e]
- [x] Task 3.1: Add Group & Exclusive Engine IAM Verification Checks (`scripts/verify.sh`) 4652d4e
    - [x] Write failing unit tests in `tests/test_verify.sh` verifying that `scripts/verify.sh` checks Cloud Identity group existence and validates that `engines/${GE_APP_ID}:getIamPolicy` binds only `group:${GE_APP_ACCESS_GROUP}`.
    - [x] Update `scripts/verify.sh` to validate group existence, exclusive Engine-level IAM policy bindings, and absence of broad project-level Discovery Engine user/viewer bindings.
    - [x] Run `CI=true ./tests/run_tests.sh` to verify all unit and integration tests pass.
- [x] Task 3.2: Execute Live Rollout Across All Gemini Enterprise Apps in `mohandemo` 4652d4e
    - [x] Run `./deploy.sh` for `config.env` (`finance-app-01`) and `configs/{hr,marketing,ops,sales,service_desk}.env` to create each app's Cloud Identity group (`<app-id>-users@mohanrajs.altostrat.com`), revoke broad project-level user/viewer access, and bind each Engine's IAM policy exclusively to its group.
    - [x] Verify live state via Cloud Identity API, Engine `:getIamPolicy`, and Project `:getIamPolicy`.
