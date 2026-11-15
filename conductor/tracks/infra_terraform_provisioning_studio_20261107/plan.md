# Implementation Plan: Infrastructure & Admin Self-Service Terraform Provisioning Studio

## Phase 1: Migrate Terraform Stacks & Verify Infra Test Suite (`infra/`)
- [x] Task 1.1: Migrate `terraform/`, `terraform-identity/`, `terraform-m365/`, `scripts/`, `configs/`, `payloads/`, `docs/`, `tests/`, and `deploy*.sh` into `geapphub/infra/`.
- [x] Task 1.2: Create modular stack & module aliases in `infra/stacks/` (`01-identity-foundation`, `02-ge-app-instance`, `03-m365-connectors`) and `infra/modules/`, and update `.gitignore` to exclude `.terraform/`, `*.tfstate*`, `*.tfvars`, and `.env` secrets.
- [x] Task 1.3: Verify all 10 infrastructure test suites (254 assertions) pass via `infra/tests/run_tests.sh`.

## Phase 2: Backend Provisioning Runner & Admin Router (`backend/app/`)
- [x] Task 2.1: Add `ProvisioningJobRecord` SQLAlchemy model in `backend/app/db_models.py` and Pydantic request/response schemas (`GeAppProvisionRequest`, `IdentityProvisionRequest`, `M365ConnectorProvisionRequest`, `ProvisioningJobItem`, `ProvisioningJobListResponse`) in `backend/app/models.py`.
- [x] Task 2.2: Implement `TerraformProvisioningService` (`backend/app/services/terraform_runner.py`) with per-engine Terraform workspace isolation (`<location>-<engine_id>`), workspace concurrency lock mutex (`acquire_workspace_lock`), Plan-Before-Apply approval gate (`PENDING_APPROVAL` $\rightarrow$ `approve_and_apply`), ephemeral `TF_VAR_*` secret injection, and log redaction.
- [x] Task 2.3: Implement `/api/v1/admin/provisioning` router (`backend/app/routers/provisioning.py`) with `POST /ge-app`, `POST /identity`, `POST /m365`, `POST /jobs/{job_id}/approve`, `POST /jobs/{job_id}/reject`, `GET /jobs`, `GET /jobs/{job_id}/stream` (SSE), and post-success catalog sync.
- [x] Task 2.4: Write unit tests in `backend/tests/test_provisioning.py` verifying Admin RBAC, workspace isolation, state lock mutex (`409 Conflict`), Plan-Before-Apply gate, and secret redaction.

## Phase 3: Frontend Admin Provisioning Studio (`frontend/`)
- [x] Task 3.1: Add Admin-only `Infra Provisioning` navigation item in `Sidebar.tsx` and `App.tsx`.
- [x] Task 3.2: Build `ProvisioningStudio.tsx` with the 3-Tab Wizard (**Stack 02: Create GE App**, **Stack 01: Identity & WIF**, **Stack 03: M365 Connectors**), Plan-Before-Apply approval gate, active workspace locks counter, and live terminal viewer.
- [x] Task 3.3: Add Vitest component tests in `frontend/src/__tests__/ProvisioningStudio.test.tsx`.
