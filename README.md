# Gemini Enterprise + Microsoft 365 & Entra ID Deployment Template

Reusable, production-grade automation template for deploying **Google Cloud Gemini Enterprise (Discovery Engine)** integrated with **Microsoft 365 Connectors (SharePoint Online, OneDrive, Outlook, Microsoft Teams)** and **Microsoft Entra ID Single Sign-On (SAML 2.0 + 1:1 Group Sync)** in any enterprise organization.

> **Start Here for Customer Implementations:**
> * **Enterprise Infrastructure & Connector Onboarding:** **[Enterprise Deployment Guide (`docs/enterprise-deployment-guide.md`)](./docs/enterprise-deployment-guide.md)**
> * **ADK Agent Deployment & Pinning:** **[Agent Publishing Guide (`docs/agent-publishing-guide.md`)](./docs/agent-publishing-guide.md)**
> * **6-Stage Skill Governance & Multi-App Sharing:** **[Skill Publishing Guide (`docs/skill-publishing-guide.md`)](./docs/skill-publishing-guide.md)**

---

## Key Capabilities

1. **Multi-Department Gemini Enterprise Apps (`./deploy.sh`):**
   * Provisions isolated Gemini Enterprise Engines, Knowledge Data Stores, GCS/BigQuery backing storage, and Assistant instructions via Terraform (`terraform/`) and Discovery Engine REST API (`scripts/configure_ge_app.sh`).
   * Enforces **strict per-app access isolation** using dedicated Cloud Identity groups (`<app-id>-users@<domain>`) bound at the Engine resource level (`:setIamPolicy`).
   * Automatically provisions the least-privilege `geConnectorAuthUser` custom role and Collection-level IAM so non-admin users can authorize M365 connectors without cross-app leakage.
2. **Microsoft 365 Federated & Write-Action Connectors (`./deploy_m365.sh`):**
   * Provisions **SharePoint Online**, **OneDrive**, **Microsoft Outlook**, and **Microsoft Teams** connectors in `FEDERATED` + `ACTIONS` (BAP) mode (`terraform-m365/` and `scripts/configure_m365_connectors.sh`).
   * Stores Entra ID OAuth credentials (`{"tenant_id","client_id","client_secret"}`) in **Google Cloud Secret Manager** (`m365-connector-credentials`) with zero plaintext secrets in Git.
   * Automatically attaches shared M365 connector Data Stores to all Gemini Enterprise apps via `configs/common_connectors.env`.
3. **Microsoft Entra ID to Google Cloud Identity Sync & SAML SSO (`./deploy_identity.sh`):**
   * Queries Microsoft Graph for corporate Entra ID Security Groups and transitive members, syncs them 1:1 into Google Cloud Identity (`terraform-identity/` and `scripts/configure_identity.sh`), and nests them into each Gemini Enterprise app's access group.
   * Automatically provisions the **Cloud Identity Inbound SAML 2.0 SSO Profile** for Microsoft Entra ID so users signing into Gemini Enterprise are redirected directly to `login.microsoftonline.com`.

---

## Quick Start (`gedeploy` Step-by-Step Direct Terraform & Cloud API CLI)

Use `./gedeploy` to execute the **7 Core Onboarding Steps** (or any individual step) directly against Terraform and Google Cloud / Microsoft Entra ID APIs (no web server required). **Agent Publishing** (`--agent-publish`), **Skill Publishing** (`--skill-publish`), **ServiceNow** (`--with-servicenow`), and **Atlassian Jira/Confluence** (`--with-atlassian`) are optional add-on parameters.

```bash
# 0. Verify Workstation CLIs, Terraform & Python Modules
./gedeploy --check-workstation

# 1. List the 7 Core Onboarding Steps and 7 Optional Add-On Modules
./gedeploy --list

# 2. Step-by-Step Core Onboarding Guide (Steps 1 to 7)
./gedeploy --gcp-foundation     --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --google-admin       --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --entra-bootstrap    --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --directory-sync     --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --identity-terraform --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --m365-connectors    --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --ge-apps            --config configs/<CUSTOMER>-onboard.env --dry-run

# 3. 1-Command Full Core Onboarding (Runs Core Steps 1 to 7 by Default)
./gedeploy --onboard --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --onboard --config configs/<CUSTOMER>-onboard.env

# 4. Optional Add-On Parameters (Agent Publishing, Skill Publishing, ServiceNow, Atlassian & Sandbox CSV)
./gedeploy --agent-publish        --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --skill-publish        --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --onboard --with-servicenow --with-atlassian --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --servicenow-bootstrap --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --servicenow-connector --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --atlassian-bootstrap  --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --atlassian-connectors --config configs/<CUSTOMER>-onboard.env --dry-run
./gedeploy --seed-demo-csv        --config configs/<CUSTOMER>-onboard.env --members-csv configs/<CUSTOMER>_users_groups.csv --dry-run
```

### Configuration Layout (`infra/configs/`)

- **`configs/<CUSTOMER>-onboard.env`**: The **single** customer onboarding configuration file used by `gedeploy`.
- **`configs/.generated/`**: Hidden directory where `gedeploy` automatically writes intermediate per-stack configs (`<CUSTOMER>-identity.env`, `<CUSTOMER>-m365.env`, `<CUSTOMER>-*-app.env`, `<CUSTOMER>-servicenow.env`, `<CUSTOMER>-atlassian.env`, SAML certificates, and Directory Sync manifests).
- **`configs/templates/ge-app-master.template.env`**: Master 16-Point Gemini Enterprise App template.
- **`configs/examples/`**: Reference `.env.example` templates (`onboard.env.example`, `identity.env.example`, `m365.env.example`, `servicenow.env.example`, `atlassian.env.example`).

### CLI Modes & Required IAM Roles
All three orchestrators (`./deploy.sh`, `./deploy_m365.sh`, `./deploy_identity.sh`) support `--config <path>`, `--dry-run`, `--terraform-only`, `--curl-only`, `--verify-only`, and `--destroy`. Ensure the deploying principal holds `roles/discoveryengine.admin`, `roles/secretmanager.admin`, `roles/iam.roleAdmin`, and Cloud Identity Groups/SSO Administrator privileges.

---

## Testing & Verification

Run the built-in zero-dependency test suite (syntax checks, unit/integration tests, and line coverage):
```bash
CI=true ./tests/run_tests.sh
```
