# Product Guidelines: Gemini Enterprise App Deployment Automation

## 1. Brand, Voice & Documentation Tone
- **Enterprise Runbook & Audit-Ready Style:** All documentation (`README.md`, operator runbooks, and architecture notes) must be authoritative, concise, and operational.
- **Transparency for Security & Admin Review:** Customer Cloud Administrators and Security teams must be able to inspect every script, Terraform module, and `curl` payload before running it. Avoid obfuscated one-liners; document why each API call or IAM role is required.
- **Self-Documenting Configuration:** The single configuration file must include clear inline comments for every variable, specifying expected formats, allowed values (e.g., regions like `global`, `us`, `eu`), and concrete examples.
- **Copy-Paste Readiness:** Commands in documentation must be directly executable without hidden prerequisites.

## 2. CLI & Script User Experience (UX) Principles
- **Structured Step-by-Step Console Output:**
  - Group execution into clear, visually distinct lifecycle phases:
    - `[PRE-FLIGHT]` — Environment, CLI dependency (`gcloud`, `terraform`, `curl`, `jq`), authentication, and config validation.
    - `[TERRAFORM]` — Declarative provisioning of supported GCP and Discovery Engine resources.
    - `[CURL/API]` — REST API provisioning/configuration for Gemini Enterprise features not covered by Terraform.
    - `[VERIFY]` — Post-deployment health checks and resource verification.
    - `[SUMMARY]` — Final output table of created App IDs, Data Store IDs, Agent registrations, and GCP Console URLs.
- **Consistent Status Indicators:** Use standard, readable severity prefixes (`[INFO]`, `[OK]`, `[WARN]`, `[ERROR]`) with ANSI color support (and graceful fallback when `NO_COLOR` is set or running in non-interactive shells).
- **Persistent Timestamped Logging:** Automatically tee all execution output (including Terraform logs and raw HTTP response bodies on failure) to a timestamped log file (e.g., `logs/deploy-YYYYMMDD-HHMMSS.log`) for customer audit and support escalation.

## 3. Error Handling & Reliability Standards
- **Fail-Fast Execution:** Scripts must run with strict shell safety (`set -euo pipefail`) and halt immediately when a critical step fails to prevent cascading errors or inconsistent state.
- **Actionable Remediation Guidance:**
  - Never fail with a raw, unformatted JSON blob or cryptic HTTP exit code alone.
  - Capture HTTP status codes and parse Discovery Engine / GCP error payloads using `jq`.
  - Provide specific remediation hints alongside errors (e.g., *"HTTP 403 Permission Denied: Verify that the active principal holds `roles/discoveryengine.admin` and that `discoveryengine.googleapis.com` is enabled in project `<PROJECT_ID>`"*).
- **Idempotency & Safe Re-Runs:**
  - Before executing `POST` requests via `curl`, check if the target Gemini Enterprise resource already exists (via `GET`/`LIST`) and either skip creation or perform a `PATCH` update so operators can safely re-run the script after fixing a transient issue.
- **Secret & Token Hygiene:** Never print raw OAuth2 access tokens (`gcloud auth print-access-token`) or sensitive credentials to stdout or log files.
