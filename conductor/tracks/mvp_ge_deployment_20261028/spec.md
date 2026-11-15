# Specification: MVP — End-to-End Gemini Enterprise App Deployment Automation

## 1. Overview
This track delivers the Minimum Viable Product (MVP) of the **Gemini Enterprise App Deployment Automation** toolkit. It provides a portable, self-contained deployment bundle that customer Cloud Administrators or Solutions Engineers can execute in Google Cloud Shell, Linux, or macOS environments using a single configuration file (`config.env`) and a master executable orchestrator script (`deploy.sh`). The automation uses **Terraform** (`google` and `google-beta` providers) where resources are declaratively supported and bridges gaps with idempotent, authenticated **`curl` REST API** calls against Google Cloud Discovery Engine / Gemini Enterprise endpoints.

## 2. Target Repository & Bundle Structure
```text
.
├── deploy.sh                        # Master executable entrypoint for customer environments
├── config.env.example               # Single-point customer configuration template
├── README.md                        # Enterprise runbook & customer execution guide
├── terraform/                       # Declarative IaC for supported GCP & Discovery Engine resources
│   ├── versions.tf                  # Provider versions (google, google-beta) & optional GCS backend
│   ├── variables.tf                 # Input variables mapped from config.env
│   ├── apis_and_iam.tf              # Required GCP APIs & Service Account / IAM bindings
│   ├── data_stores.tf               # Backing GCS/BigQuery resources & Discovery Engine Data Stores
│   ├── engine.tf                    # Discovery Engine Search / Conversation App Engine
│   └── outputs.tf                   # Resource IDs & metadata exported to curl scripts
├── scripts/
│   ├── lib/
│   │   ├── common.sh                # Logging ([PRE-FLIGHT], [TERRAFORM], [CURL/API], [VERIFY]), error trap, config loader
│   │   └── http.sh                  # Authenticated curl wrapper, retry logic, jq error parser, dry-run printer
│   ├── preflight.sh                 # Validates CLI tools, gcloud auth, active project, and config variables
│   ├── configure_ge_app.sh          # REST API (curl) calls for Gemini Enterprise App/Assistant settings & ACLs
│   ├── register_agents.sh           # REST API (curl) calls for Enterprise Connectors & ADK/Agent registration
│   └── verify.sh                    # Post-deployment curl GET health checks and summary output table
├── payloads/                        # Parameterized JSON payload templates for curl requests
│   ├── app_config.json.tmpl
│   ├── acl_config.json.tmpl
│   └── agent_registration.json.tmpl
└── tests/                           # Automated test suite (Bats / shell test runner + mocks)
    ├── test_helper.sh
    ├── test_preflight.sh
    ├── test_http_wrapper.sh
    ├── test_curl_modules.sh
    └── test_deploy_cli.sh
```

## 3. Functional Requirements

### FR-1: Single-Point Customer Configuration (`config.env.example`)
- Provide a thoroughly documented `config.env.example` covering:
  - **Core GCP Settings:** `GCP_PROJECT_ID`, `GCP_REGION` (e.g., `us-central1`), `GE_LOCATION` (`global`, `us`, or `eu`), optional `TF_STATE_BUCKET`.
  - **Gemini Enterprise App Settings:** `GE_APP_ID`, `GE_APP_DISPLAY_NAME`, `GE_INDUSTRY_VERTICAL` (`GENERIC`), `GE_SOLUTION_TYPE` (`SOLUTION_TYPE_SEARCH` / `SOLUTION_TYPE_CHAT`), `GE_COMPANY_NAME`.
  - **Data Store Settings:** `GE_DATA_STORE_ID`, `GE_DATA_STORE_DISPLAY_NAME`, `GE_DATA_STORE_TYPE` (`GCS`, `BIGQUERY`, `WEBSITE`, or `CONNECTOR`), source URIs.
  - **IAM / Identity & ACLs:** `GE_IDENTITY_PROVIDER_TYPE` (`GSUITE` / `WORKFORCE_IDENTITY`), admin/user principal emails or groups.
  - **Agent & Connector Registration (Optional/Toggleable):** `ENABLE_AGENT_REGISTRATION`, `AGENT_DISPLAY_NAME`, `AGENT_DESCRIPTION`, `AGENT_REASONING_ENGINE_ID` or endpoint URL.
- Automatically export `TF_VAR_*` environment variables from `config.env` so Terraform and `curl` scripts share the exact same single source of truth without duplicate edits.

### FR-2: Master Orchestration Script & CLI Flags (`deploy.sh`)
- Support the following CLI flags:
  - `--config <path>`: Path to the customer configuration file (defaults to `./config.env`).
  - `--dry-run`: Runs pre-flight checks, executes `terraform plan`, and prints the exact rendered `curl` commands and JSON payloads without mutating remote state.
  - `--terraform-only`: Runs only `[PRE-FLIGHT]` and `[TERRAFORM]` phases.
  - `--curl-only`: Runs only `[PRE-FLIGHT]` and `[CURL/API]` phases (reading existing Terraform outputs or configured IDs).
  - `--verify-only`: Runs only `[PRE-FLIGHT]` and `[VERIFY]` phases.
  - `--destroy`: Tears down `curl`-managed registrations and executes `terraform destroy` for clean environment removal.
  - `--help`: Prints usage instructions and examples.

### FR-3: Pre-Flight Validation (`scripts/preflight.sh`)
- Verify presence of required CLI tools (`bash`, `gcloud`, `terraform`, `curl`, `jq`).
- Verify active `gcloud` authentication (`gcloud auth print-access-token`) without leaking the token to logs or stdout.
- Validate that all required variables in `config.env` are non-empty and match valid formats (e.g., `GE_LOCATION` in `global|us|eu`).

### FR-4: Terraform Provisioning (`terraform/`)
- Enable required Google Cloud APIs (`discoveryengine.googleapis.com`, `aiplatform.googleapis.com`, `storage.googleapis.com`, `bigquery.googleapis.com`, `iam.googleapis.com`).
- Provision backing data sources when configured (e.g., GCS staging/docs bucket or BigQuery dataset) and IAM bindings.
- Provision Discovery Engine Data Store (`google_discovery_engine_data_store`) and Discovery Engine Search/Chat Engine (`google_discovery_engine_search_engine` / `google_discovery_engine_chat_engine`) via `hashicorp/google-beta`.
- Support local Terraform state by default, with automatic remote GCS backend initialization (`-backend-config="bucket=${TF_STATE_BUCKET}"`) if `TF_STATE_BUCKET` is set in `config.env`.
- Output created resource IDs (`engine_id`, `data_store_id`, `collection_id`, `project_number`) as JSON for downstream `curl` scripts.

### FR-5: Authenticated `curl` REST API Modules (`scripts/configure_ge_app.sh` & `scripts/register_agents.sh`)
- Construct regional or global Discovery Engine base URLs dynamically (`https://discoveryengine.googleapis.com` for `global`, `https://${GE_LOCATION}-discoveryengine.googleapis.com` for `us`/`eu`).
- Implement idempotent `GET`-then-`POST`/`PATCH` logic using `scripts/lib/http.sh`:
  - Configure Gemini Enterprise App / Assistant settings and widget/ACL configurations not exposed in Terraform.
  - Register custom/ADK Agents (or Enterprise Connectors) against the Gemini Enterprise Engine/Assistant via REST API payloads rendered from `payloads/*.json.tmpl`.
  - Support fallback `curl` creation of the Engine/Data Store if the customer runs with `--curl-only` in an environment where Terraform resource creation is bypassed.

### FR-6: Post-Deployment Verification & Summary (`scripts/verify.sh`)
- Execute authenticated `curl GET` requests to verify that the Gemini Enterprise Engine, Data Store(s), and any registered Agents exist and are in an active/ready state.
- Print a formatted `[SUMMARY]` banner listing created resource names, full GCP resource IDs, direct Google Cloud Console links, and the path to the timestamped log file (`logs/deploy-YYYYMMDD-HHMMSS.log`).

## 4. Non-Functional Requirements
- **Strict Shell Safety:** All scripts must use `set -euo pipefail`.
- **Actionable Error Remediation:** HTTP 4xx/5xx responses from `curl` must be parsed via `jq` to display the API error message along with specific remediation guidance (e.g., required IAM role `roles/discoveryengine.admin` or missing API enablement).
- **Credential Hygiene:** Access tokens must never be echoed to stdout or written to log files, even in `--dry-run` mode (use `$ACCESS_TOKEN` placeholder in printed dry-run commands).
- **Testability & Coverage:** All shell functions and modules must be testable offline via mocked CLI binaries (`gcloud`, `terraform`, `curl`), achieving >80% test coverage.

## 5. Acceptance Criteria
1. Running `./deploy.sh --help` displays clear documentation of all supported flags.
2. Running `./deploy.sh --config config.env --dry-run` validates config, runs `terraform plan` (or mock plan in test mode), and outputs rendered `curl` commands with redacted tokens without mutating any GCP resources.
3. Terraform configuration passes `terraform fmt -check` and `terraform validate`.
4. All Bash scripts pass `shellcheck` with zero warnings/errors.
5. Automated unit/integration test suite (`./tests/run_tests.sh`) passes 100% of test cases covering pre-flight checks, config loading, HTTP wrapper error handling, idempotency (`GET` before `POST`/`PATCH`), dry-run mode, and CLI flag routing.

## 6. Out of Scope (for MVP)
- Graphical Web UI or browser-based deployment portal.
- Custom third-party SaaS OAuth token Dance automation (e.g., interactive browser OAuth flow for Jira/Confluence; connector config accepts pre-created Secret Manager secret versions or parameters).
- Multi-project organization policy (`orgpolicy`) overrides.
