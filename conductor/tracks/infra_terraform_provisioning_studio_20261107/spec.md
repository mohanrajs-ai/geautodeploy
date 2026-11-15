# Specification: Infrastructure & Admin Self-Service Terraform Provisioning Studio

## 1. Overview
Unify the Gemini Enterprise Terraform automation stacks (`infra/stacks/01-identity-foundation`, `02-ge-app-instance`, `03-m365-connectors`) inside the `geapphub` monorepo and expose them via an RBAC-protected **Admin Provisioning Studio** (`ProvisioningStudio.tsx` + `/api/v1/admin/provisioning`).

## 2. Scope & Subsections Covered
- **`infra/` Monorepo Subsection:**
  - Stack 01 (`01-identity-foundation` / `infra/terraform-identity`): Workforce Identity Pool, OIDC/SAML Provider, Entra ID to Cloud Identity GCDS/SCIM preparation, and Location ACL configuration.
  - Stack 02 (`02-ge-app-instance` / `infra/terraform`): Discovery Engine `SEARCH_AND_ASSISTANT` Engine creation, GCS/BigQuery data store binding, and assistant setup with per-app workspace isolation (`<location>-<engine_id>`).
  - Stack 03 (`03-m365-connectors` / `infra/terraform-m365`): Microsoft 365 Federated Graph Connectors (SharePoint Online, Outlook/Exchange, Microsoft Teams, OneDrive).
- **`backend/app/routers/provisioning.py` & `services/terraform_runner.py`:**
  - Admin-only (`require_admin`) endpoints to validate, dry-run (`--dry-run` / `terraform plan`), and execute (`terraform apply`) stacks asynchronously.
  - Ephemeral `TF_VAR_*` secret injection (`m365_client_secret`, `wif_oidc_client_secret`) with strict log redaction.
  - Automatic `CatalogSyncService.run_sync()` trigger upon successful App or M365 Connector provisioning so the new engine and `data_store_ids` appear immediately in AppHub and the 6-Stage Skill Readiness Matrix.
- **`frontend/src/components/ProvisioningStudio.tsx`:**
  - 3-Tab Wizard (**1. Create GE App**, **2. Setup Identity & WIF**, **3. Connect Microsoft 365**) with Dry-Run preview and real-time Server-Sent Events (SSE) console output.
