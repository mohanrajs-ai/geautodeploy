# Specification: Centralized Common Connectors Registry & Automatic Multi-App Attachment

## 1. Overview
Organizations deploying multiple departmental Gemini Enterprise Apps (such as Finance, HR, Marketing, Ops, Sales, and Service Desk) often have a shared set of **Common Enterprise Connectors**—most notably **Microsoft 365** (`SharePoint Online`, `OneDrive`, `Outlook`, and `Microsoft Teams`)—that should be available in every Gemini Enterprise App alongside each app's dedicated knowledge base Data Store.

Because Google Cloud Discovery Engine allows a single Data Connector's entity Data Stores (`<collection_id>_<entityName>`) to be attached to multiple Multi-Data-Store Engines (`1-to-Many`), this feature introduces a centralized Common Connectors configuration (`configs/common_connectors.env`) and updates both the Terraform module and `curl` REST API scripts so that:
1. Every newly created or updated Gemini Enterprise App automatically attaches its primary Data Store **plus** all configured Common Connectors.
2. Existing single-datastore Gemini Enterprise Apps (`finance-app-01`, `hr-app-01`, `marketing-app-01`, `ops-app-01`, `sales-app-01`, `service-desk-app-01`) are seamlessly upgraded to Multi-Data-Store Engines containing their primary Data Store + all Common Connectors (`m365-sp`, `m365-od-test`, `m365-ol-test`, `m365-teams-test`), while preserving their Assistant system instructions and exclusive per-app Cloud Identity group IAM bindings.

## 2. Functional Requirements

### FR-1: Centralized Common Connectors Registry (`configs/common_connectors.env` & `scripts/lib/common.sh`)
- Create `configs/common_connectors.env` (and `configs/common_connectors.env.example`) defining:
  - `GE_ENABLE_COMMON_CONNECTORS="true"`
  - `GE_COMMON_CONNECTOR_COLLECTIONS="m365-sp,m365-od-test,m365-ol-test,m365-teams-test"`
  - `GE_COMMON_CONNECTOR_DATA_STORE_IDS="m365-sp_file,m365-sp_page,m365-od-test_file,m365-ol-test_mail,m365-ol-test_mail-attachment,m365-ol-test_calendar,m365-ol-test_contact,m365-teams-test_channel-message,m365-teams-test_chat-message"`
- Update `load_config()` in `scripts/lib/common.sh` to automatically source `configs/common_connectors.env` (if present and `GE_ENABLE_COMMON_CONNECTORS != "false"`) before loading the app-specific config file (allowing individual apps to override if needed), and export `TF_VAR_common_connector_data_store_ids`.

### FR-2: Terraform Multi-Data-Store Engine Support (`terraform/variables.tf` & `terraform/engine.tf`)
- Add `variable "common_connector_data_store_ids"` (comma-separated string, default `""`) in `terraform/variables.tf`.
- Update `google_discovery_engine_search_engine.main` in `terraform/engine.tf` so `data_store_ids` combines `[google_discovery_engine_data_store.main.data_store_id]` with all non-empty IDs from `var.common_connector_data_store_ids`.

### FR-3: Dynamic Common Connector Resolution & Engine Attachment / Upgrade (`scripts/configure_ge_app.sh`)
- Implement `resolve_common_connector_datastore_ids()` in `scripts/configure_ge_app.sh`.
- Update `render_engine_payload()` in `scripts/configure_ge_app.sh` to include the combined array of `[GE_DATA_STORE_ID, <common_connector_datastore_ids...>]` in `.dataStoreIds`.
- Implement `ensure_engine_common_connectors_attached()` in `scripts/configure_ge_app.sh` to attach common connector Data Stores to the Engine and automatically upgrade legacy single-datastore Engines to multi-datastore Engines when needed.

### FR-4: Verification & Live Multi-App Rollout (`scripts/verify.sh` & `mohandemo`)
- Update `scripts/verify.sh` to display the attached Common Connectors in `[SUMMARY]`.
- Roll out the update across all 6 departmental Gemini Enterprise Apps in `mohandemo` (`finance-app-01`, `hr-app-01`, `marketing-app-01`, `ops-app-01`, `sales-app-01`, `service-desk-app-01`).

## 3. Acceptance Criteria
- [ ] `configs/common_connectors.env` defines the shared M365 connectors (`m365-sp`, `m365-od-test`, `m365-ol-test`, `m365-teams-test`) and is automatically loaded for every app.
- [ ] All 6 departmental apps in `mohandemo` have their primary Data Store **plus** the M365 connector entity Data Stores attached in `dataStoreIds`.
- [ ] Exclusive per-app Cloud Identity group IAM bindings remain intact on every app.
- [ ] Automated test suite (`CI=true ./tests/run_tests.sh`) passes with >80% line coverage.
