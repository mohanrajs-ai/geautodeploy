# Implementation Plan: MVP — End-to-End Gemini Enterprise App Deployment Automation

## Phase 1: Project Scaffolding, Configuration Schema & Core Shell Libraries [checkpoint: b49fbf9]
Establish the repository structure, single-point customer configuration file (`config.env.example`), logging/error-handling utilities (`scripts/lib/common.sh`), authenticated `curl` HTTP wrapper (`scripts/lib/http.sh`), and the automated test harness (`tests/`).

- [x] Task: Set up automated test runner and mock CLI test helpers (`tests/run_tests.sh`, `tests/test_helper.sh`) a1d8907
  - [x] Create `tests/test_helper.sh` with assertion helpers and mock stubs for `gcloud`, `terraform`, `curl`, and `jq`
  - [x] Create `tests/run_tests.sh` to execute all test suites and report pass/fail metrics and line coverage
- [x] Task: Create customer configuration template (`config.env.example`) and config loader (`scripts/lib/common.sh`) f59ef1c
  - [x] Write failing unit tests in `tests/test_common.sh` for structured logging (`[PRE-FLIGHT]`, `[TERRAFORM]`, `[CURL/API]`, `[VERIFY]`), timestamped log file setup, `config.env` parsing, and automatic `TF_VAR_*` export
  - [x] Implement `config.env.example` with comprehensive inline comments for all GCP, Gemini Enterprise App, Data Store, ACL, and Agent variables
  - [x] Implement `scripts/lib/common.sh` to pass all unit tests and `shellcheck`
- [x] Task: Build authenticated `curl` HTTP wrapper and error parser (`scripts/lib/http.sh`) 2f30271
  - [x] Write failing unit tests in `tests/test_http_wrapper.sh` covering regional/global Discovery Engine URL construction, token redaction in `--dry-run` and logs, `jq` HTTP 4xx/5xx error parsing with actionable remediation hints, and idempotent `GET`-then-`POST`/`PATCH` helpers
  - [x] Implement `scripts/lib/http.sh` to pass all unit tests and `shellcheck`
- [x] Task: Build Pre-Flight Validation module (`scripts/preflight.sh`) b49fbf9
  - [x] Write failing unit tests in `tests/test_preflight.sh` testing CLI dependency checks (`gcloud`, `terraform`, `curl`, `jq`), active `gcloud` authentication checks, and required variable validation (including valid `GE_LOCATION` values `global|us|eu`)
  - [x] Implement `scripts/preflight.sh` to pass all unit tests and `shellcheck`
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) b49fbf9

## Phase 2: Modular Terraform Infrastructure for Gemini Enterprise (`terraform/`) [checkpoint: cf31eb8]
Implement declarative Terraform configurations (`google` and `google-beta` providers) for GCP APIs, IAM bindings, backing storage, Discovery Engine Data Stores, and the base Search/Chat App Engine.

- [x] Task: Create Terraform provider configuration, variables, and outputs (`terraform/versions.tf`, `terraform/variables.tf`, `terraform/outputs.tf`) 505614d
  - [x] Write failing validation tests in `tests/test_terraform.sh` verifying variable mappings from `TF_VAR_*`, local vs. optional GCS remote backend initialization, and required outputs (`engine_id`, `data_store_id`, `collection_id`, `project_number`)
  - [x] Implement `terraform/versions.tf`, `terraform/variables.tf`, and `terraform/outputs.tf`
- [x] Task: Implement GCP APIs, IAM bindings, Data Stores, and Gemini Enterprise Engine (`terraform/apis_and_iam.tf`, `terraform/data_stores.tf`, `terraform/engine.tf`) cf31eb8
  - [x] Expand `tests/test_terraform.sh` to assert valid HCL syntax, `terraform fmt -check`, `terraform validate`, and resource definitions for `google_project_service`, `google_discovery_engine_data_store`, and `google_discovery_engine_search_engine` / `google_discovery_engine_chat_engine`
  - [x] Implement `terraform/apis_and_iam.tf`, `terraform/data_stores.tf`, and `terraform/engine.tf` to pass all validation tests
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) cf31eb8

## Phase 3: Authenticated `curl` REST API Provisioning & Verification Modules (`scripts/` & `payloads/`) [checkpoint: 3110929]
Implement the parameterized JSON payload templates and `curl` execution scripts that bridge Terraform provider gaps for Gemini Enterprise App/Assistant configuration, ACLs, fallback engine/data store creation, Agent registration, and post-deployment verification.

- [x] Task: Implement Gemini Enterprise App & ACL configuration via `curl` (`scripts/configure_ge_app.sh` & `payloads/`) cdf5d61
  - [x] Write failing unit tests in `tests/test_curl_modules.sh` testing JSON payload rendering (`payloads/app_config.json.tmpl`, `payloads/acl_config.json.tmpl`), idempotent `GET`-before-`POST`/`PATCH` execution, fallback `--curl-only` engine/data store creation, and `--dry-run` output
  - [x] Create JSON templates in `payloads/app_config.json.tmpl` and `payloads/acl_config.json.tmpl` and implement `scripts/configure_ge_app.sh` to pass all tests
- [x] Task: Implement Agent & Connector registration via `curl` (`scripts/register_agents.sh` & `payloads/agent_registration.json.tmpl`) 19d26bb
  - [x] Expand `tests/test_curl_modules.sh` with unit tests for conditional agent registration (`ENABLE_AGENT_REGISTRATION=true/false`), payload templating, idempotency, and `--destroy` deregistration
  - [x] Create `payloads/agent_registration.json.tmpl` and implement `scripts/register_agents.sh` to pass all tests
- [x] Task: Implement Post-Deployment Verification & Summary Reporter (`scripts/verify.sh`) 3110929
  - [x] Write failing unit tests in `tests/test_verify.sh` testing `curl GET` health checks for Engine, Data Store, and Agent resources and `[SUMMARY]` console table rendering with GCP Console URLs
  - [x] Implement `scripts/verify.sh` to pass all unit tests and `shellcheck`
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) 3110929

## Phase 4: Master Executable Entrypoint (`deploy.sh`) & Enterprise Runbook (`README.md`) [checkpoint: 4c8032b]
Integrate all phases into the customer-facing `deploy.sh` orchestrator script and author the comprehensive customer runbook.

- [x] Task: Implement master executable orchestrator script (`deploy.sh`) f0684ab
  - [x] Write failing end-to-end CLI tests in `tests/test_deploy_cli.sh` covering `--help`, `--config <file>`, `--dry-run`, `--terraform-only`, `--curl-only`, `--verify-only`, `--destroy`, and full end-to-end execution flow
  - [x] Implement `deploy.sh` (`chmod +x`) integrating `preflight.sh`, Terraform orchestration (`init`, `plan`, `apply`, `output -json`, `destroy`), `configure_ge_app.sh`, `register_agents.sh`, and `verify.sh`
- [x] Task: Author Enterprise Customer Runbook (`README.md`) and update `conductor/workflow.md` development commands 4c8032b
  - [x] Write documentation verification checks in `tests/test_deploy_cli.sh` ensuring `README.md` documents prerequisites, IAM roles, `config.env` parameters, all CLI flags, and troubleshooting steps
  - [x] Write `README.md` in Enterprise Runbook style and update `conductor/workflow.md` with project-specific test/lint commands
- [x] Task: Phase Verification & Checkpoint (Refer to workflow.md) 4c8032b
