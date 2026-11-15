# Implementation Plan: Microsoft Entra ID to Google Cloud Identity Entity Sync & SSO (`entra_cloud_identity_sync_20261103`)

## Phase 1: Separate Terraform Module (`terraform-identity/`) & Secret Manager / Cloud DNS Integration [checkpoint: 3566410]
- [x] Task: Update `conductor/tech-stack.md` and `conductor/product.md` to document Microsoft Graph API, Admin SDK Directory API, Cloud Identity Inbound SSO, and the `terraform-identity/` module 664d04a
    - [x] Document Microsoft Graph REST API (`/v1.0/users`, `/v1.0/groups`, `/v1.0/groups/{id}/transitiveMembers`) and Cloud DNS (`mohan-dns` / `mohanrajs-demo`) integration in `conductor/tech-stack.md`
    - [x] Document Entra ID to Cloud Identity synchronization and shared domain (`mohanrajs.demo.altostrat.com`) capabilities in `conductor/product.md`
- [x] Task: Create standalone Terraform module in `terraform-identity/` with TDD validation tests 3566410
    - [x] Write failing Terraform validation & schema assertions in `tests/test_identity.sh` (Red Phase)
    - [x] Implement `terraform-identity/versions.tf`, `terraform-identity/variables.tf`, `terraform-identity/identity.tf` (`data.google_secret_manager_secret_version.m365_credentials_latest`, `google_dns_record_set`, `google_cloud_identity_group`, `google_cloud_identity_group_membership`, `data.google_cloud_identity_group_lookup`), and `terraform-identity/outputs.tf` (Green Phase)
    - [x] Run `terraform -chdir=terraform-identity init -backend=false`, `terraform fmt -check`, and `terraform validate`
- [x] Task: Conductor - User Manual Verification 'Phase 1: Separate Terraform Module (terraform-identity/) & Secret Manager / Cloud DNS Integration' (Protocol in workflow.md) 3566410

## Phase 2: Identity Sync Script (`scripts/configure_identity.sh`), Standalone Orchestrator (`deploy_identity.sh`), and Configs (`configs/identity.env`) [checkpoint: a3c32e2]
- [x] Task: Implement Secret Manager JSON credential resolution, Entra Bulk UPN Migration, and Microsoft Graph -> Cloud Identity entity sync in `scripts/configure_identity.sh`, `deploy_identity.sh`, and `configs/identity.env` 9d4e99a
    - [x] Write failing unit and dry-run tests in `tests/test_identity.sh` for `ensure_and_load_identity_secret_credentials`, `bulk_update_entra_upn_domain`, `sync_entra_entities_to_cloud_identity`, `configure_cloud_identity_sso_and_acl`, and `deploy_identity.sh --dry-run` (Red Phase)
    - [x] Create `configs/identity.env.example` and `configs/identity.env` for `mohandemo` / `mohanrajs.demo.altostrat.com` without plaintext secrets (Green Phase)
    - [x] Implement `scripts/configure_identity.sh` and `deploy_identity.sh` with Secret Manager JSON lookup, Microsoft Graph OAuth2 token exchange, Bulk UPN domain rewrite (`@1771sp.onmicrosoft.com` -> `@mohanrajs.demo.altostrat.com`), Cloud Identity user/group sync, `identity_entities.auto.tfvars.json` generation, and Discovery Engine `aclConfig` verification (Green Phase)
    - [x] Register `tests/test_identity.sh` in `tests/run_tests.sh` and verify >80% line coverage
- [x] Task: Documentation & Live Readiness Verification in `mohandemo` a3c32e2
    - [x] Update `README.md` and `docs/entra-cloud-identity-design.md` with complete CLI usage and Entra/Google Admin Portal instructions
    - [x] Execute dry-run and live readiness checks against `mohandemo`, `mohan-dns`, and `customers/C00x1gdg6`
- [x] Task: Conductor - User Manual Verification 'Phase 2: Identity Sync Script, Standalone Orchestrator, and Live Readiness Verification' (Protocol in workflow.md) a3c32e2
