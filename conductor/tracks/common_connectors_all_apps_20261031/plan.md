# Implementation Plan: Centralized Common Connectors Registry & Automatic Multi-App Attachment

## Phase 1: Common Connectors Configuration & Terraform Multi-Data-Store Engine Support [checkpoint: e93e112]
- [x] Task 1.1: Create `configs/common_connectors.env` and Auto-Loader in `scripts/lib/common.sh` 67a1087
    - [x] Write failing unit tests in `tests/test_common.sh` verifying that `load_config` automatically loads `configs/common_connectors.env` (or `configs/common_connectors.env.example`), populates `GE_COMMON_CONNECTOR_COLLECTIONS` and `GE_COMMON_CONNECTOR_DATA_STORE_IDS`, and exports `TF_VAR_common_connector_data_store_ids`.
    - [x] Create `configs/common_connectors.env` and `configs/common_connectors.env.example` with the M365 connectors (`m365-sp`, `m365-od-test`, `m365-ol-test`, `m365-teams-test` and their entity Data Store IDs).
    - [x] Update `load_config()` in `scripts/lib/common.sh` to auto-source `configs/common_connectors.env` (when `GE_ENABLE_COMMON_CONNECTORS != "false"`) and export `TF_VAR_common_connector_data_store_ids`.
    - [x] Run `./tests/test_common.sh` to verify Green phase.
- [x] Task 1.2: Update Terraform Engine Module to Attach Common Connector Data Stores (`terraform/variables.tf`, `terraform/engine.tf`) e93e112
    - [x] Write failing unit tests in `tests/test_terraform.sh` asserting `common_connector_data_store_ids` is declared in `terraform/variables.tf` and combined into `data_store_ids` in `terraform/engine.tf`.
    - [x] Update `terraform/variables.tf` and `terraform/engine.tf` so `google_discovery_engine_search_engine.main` attaches both the app's primary Data Store and all `common_connector_data_store_ids`.
    - [x] Run `terraform fmt -check`, `terraform validate`, and `./tests/test_terraform.sh`.

## Phase 2: Dynamic Common Connector Resolution & Engine Multi-Data-Store Upgrade (`scripts/configure_ge_app.sh`) [checkpoint: 270e20a]
- [x] Task 2.1: Implement Common Connector Resolution & Multi-Data-Store Engine Attachment (`scripts/configure_ge_app.sh`) 270e20a
    - [x] Write failing unit tests in `tests/test_curl_modules.sh` verifying `resolve_common_connector_datastore_ids()`, multi-datastore `render_engine_payload()`, and `ensure_engine_common_connectors_attached()` (including automatic single-to-multi-datastore Engine upgrade when needed).
    - [x] Implement `resolve_common_connector_datastore_ids()`, update `render_engine_payload()`, and implement `ensure_engine_common_connectors_attached()` in `scripts/configure_ge_app.sh`.
    - [x] Run `./tests/test_curl_modules.sh` and `CI=true ./tests/run_tests.sh`.

## Phase 3: Verification Updates & Live Multi-App Rollout (`scripts/verify.sh` & `mohandemo`) [checkpoint: ef6fc5e]
- [x] Task 3.1: Update `scripts/verify.sh` to Report & Verify Common Connectors c616a11
    - [x] Write failing unit tests in `tests/test_verify.sh` asserting `[SUMMARY]` displays `Common Connectors` and verifies Engine `dataStoreIds`.
    - [x] Update `scripts/verify.sh` to print `Common Connectors` in `print_deployment_summary()`.
    - [x] Run `./tests/test_verify.sh` and `CI=true ./tests/run_tests.sh`.
- [x] Task 3.2: Roll Out Common M365 Connectors Across All 6 Departmental Apps in `mohandemo` 63541c4
    - [x] Execute `./deploy.sh --config <cfg> --curl-only` for `config.env` (`finance-app-01`) and `configs/{hr,marketing,ops,sales,service_desk}.env` to attach all M365 common connectors (`m365-sp`, `m365-od-test`, `m365-ol-test`, `m365-teams-test`), upgrading single-datastore engines to multi-datastore engines and preserving Assistant and exclusive Group IAM settings.
    - [x] Verify live `dataStoreIds` and `:getIamPolicy` across all 6 apps via REST API.
