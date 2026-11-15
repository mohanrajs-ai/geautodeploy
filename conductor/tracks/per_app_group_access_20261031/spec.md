# Specification: Per-App Cloud Identity Group Creation & Exclusive App Access Control

## 1. Overview
Currently, Gemini Enterprise App access in the automation toolkit is granted via additive, project-level IAM bindings (`google_project_iam_member.ge_viewers` with `roles/discoveryengine.viewer` and project-level `roles/discoveryengine.user`). Because Google Cloud IAM is hierarchical and additive, any user or workforce pool granted `roles/discoveryengine.user` or `roles/discoveryengine.viewer` at the project level automatically inherits access to **all** Gemini Enterprise Apps (Engines) in the project.

This feature introduces strict, per-application group-based access isolation:
1. Automatically provisions a dedicated Google Cloud Identity group for each Gemini Enterprise App (`<GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>`, e.g., `finance-app-01-users@mohanrajs.altostrat.com`) and manages its initial group members.
2. Configures the Engine-level IAM policy (`/v1alpha/projects/{project}/locations/{location}/collections/{collection}/engines/{engine_id}:setIamPolicy`) on each Gemini Enterprise App so that **only** its dedicated group (`group:<app-group-email>`) is bound to `roles/discoveryengine.user` and `roles/discoveryengine.viewer`.
3. Removes project-wide Discovery Engine user/viewer IAM bindings (`roles/discoveryengine.user` and `roles/discoveryengine.viewer`) so that users outside an app's group have zero access to that app.

## 2. Functional Requirements

### FR-1: Single-Point Group & Domain Configuration (`config.env` & `configs/*.env`)
- Add group access control parameters to `config.env`, `config.env.example`, and all app environment files in `configs/` (`hr.env`, `marketing.env`, `ops.env`, `sales.env`, `service_desk.env`):
  - `GE_CUSTOMER_DOMAIN` (default: `"mohanrajs.altostrat.com"`)
  - `GE_CLOUD_IDENTITY_CUSTOMER_ID` (optional; auto-discovered from `organizations:search` as `customers/C00x1gdg6` or configured explicitly)
  - `GE_APP_ACCESS_GROUP` (optional override; defaults to `"${GE_APP_ID}-users@${GE_CUSTOMER_DOMAIN}"`)
  - `GE_APP_GROUP_MEMBERS` (comma-separated list of user emails to add as `MEMBER` in the app's group)
- Update `scripts/lib/common.sh` to compute default `GE_APP_ACCESS_GROUP="${GE_APP_ID}-users@${GE_CUSTOMER_DOMAIN}"` when not explicitly overridden and export the corresponding `TF_VAR_*` variables.

### FR-2: Per-App Cloud Identity Group & Membership Provisioning (Hybrid Terraform + REST API)
- **API Enablement:** Enable `cloudidentity.googleapis.com` in `terraform/apis_and_iam.tf`.
- **Terraform Provisioning:**
  - Define `google_cloud_identity_group` in `terraform/apis_and_iam.tf` (when `cloud_identity_customer_id` is provided) to create `<GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>` with discussion forum / security group labels and `google_cloud_identity_group_membership` for configured group members.
- **REST API Provisioning & Idempotent Sync (`scripts/configure_ge_app.sh`):**
  - Implement `ensure_app_cloud_identity_group()` in `scripts/configure_ge_app.sh` using the Cloud Identity v1 REST API (`https://cloudidentity.googleapis.com/v1/groups`):
    1. Auto-discover `directoryCustomerId` via Cloud Resource Manager `organizations:search` if `GE_CLOUD_IDENTITY_CUSTOMER_ID` is not set.
    2. Look up the group via `GET /v1/groups:lookup?groupKey.id=<group_email>`.
    3. Create the group via `POST /v1/groups?initialGroupConfig=WITH_INITIAL_OWNER` if it does not exist.
    4. Reconcile configured `GE_APP_GROUP_MEMBERS` via `POST /v1/{group_name}/memberships` (ignoring `409 ALREADY_EXISTS`).

### FR-3: Exclusive Engine-Level IAM Access & Removal of Broad Project-Level Access
- **Remove Project-Level Viewer/User Grants in Terraform:**
  - Remove `google_project_iam_member.ge_viewers` from `terraform/apis_and_iam.tf` so that `roles/discoveryengine.viewer` is never granted at the project level.
- **Revoke Broad Project-Level Discovery Engine User/Viewer Bindings via REST API:**
  - Implement `revoke_project_level_ge_access()` in `scripts/configure_ge_app.sh` (invoked during app configuration) that inspects the project IAM policy (`projects/{project}:getIamPolicy`) and removes non-service-account bindings for `roles/discoveryengine.user`, `roles/discoveryengine.viewer`, `roles/discoveryengine.agentspaceUser`, and `roles/discoveryengine.agentspaceViewer` at the project level (`projects/{project}:setIamPolicy`), ensuring no user inherits blanket access to all apps.
- **Enforce Exclusive Engine-Level IAM Policy:**
  - Implement `configure_engine_exclusive_group_iam()` in `scripts/configure_ge_app.sh` that calls:
    `POST https://discoveryengine.googleapis.com/v1alpha/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID}/engines/${GE_APP_ID}:setIamPolicy`
  - Overwrites the Engine's IAM policy bindings so that **only** `group:${GE_APP_ACCESS_GROUP}` holds `roles/discoveryengine.user` and `roles/discoveryengine.viewer` on that Engine (`${GE_APP_ID}`). Any other user or group bindings on the Engine are removed.

### FR-4: Verification & Live Deployment Across All Apps
- Update `scripts/verify.sh` to verify:
  1. The app's dedicated Cloud Identity group (`${GE_APP_ACCESS_GROUP}`) exists and is active.
  2. The Engine's IAM policy (`engines/${GE_APP_ID}:getIamPolicy`) binds `group:${GE_APP_ACCESS_GROUP}` and contains no unauthorized user bindings.
  3. No broad project-level `roles/discoveryengine.user` or `roles/discoveryengine.viewer` bindings exist.
- Execute the updated automation against all configured Gemini Enterprise Apps in `mohandemo` (`finance-app-01`, `hr-app-01`, `marketing-app-01`, `ops-app-01`, `sales-app-01`, `service-desk-app-01`).

## 3. Non-Functional Requirements
- **Idempotency:** Re-running `./deploy.sh` must safely converge existing groups, group memberships, and Engine IAM policies without failing on `409 ALREADY_EXISTS`.
- **Non-Interactive Execution:** Must use Application Default Credentials (`gcloud auth application-default print-access-token --quiet`) to avoid interactive CBA password prompts.
- **Test Coverage:** Unit and dry-run tests in `tests/` must achieve >80% coverage of all new group creation, Engine IAM policy enforcement, and project IAM cleanup functions.

## 4. Acceptance Criteria
- [ ] Each Gemini Enterprise App (`finance-app-01`, `hr-app-01`, `marketing-app-01`, `ops-app-01`, `sales-app-01`, `service-desk-app-01`) has its own dedicated Cloud Identity group `<app_id>-users@mohanrajs.altostrat.com`.
- [ ] Calling `GET .../engines/<app_id>:getIamPolicy` on each app shows **only** `group:<app_id>-users@mohanrajs.altostrat.com` granted `roles/discoveryengine.user` and `roles/discoveryengine.viewer`.
- [ ] Project-level IAM policy on `mohandemo` has no `roles/discoveryengine.user` or `roles/discoveryengine.viewer` bindings that would leak access across apps.
- [ ] Automated test suite (`CI=true ./tests/run_tests.sh`) passes with 100% pass rate.

## 5. Out of Scope
- Modifying document-level ACLs inside third-party data sources (SharePoint/OneDrive item ACLs remain governed by their source connector ACLs).
- Deleting project owner/editor administrative roles unrelated to Discovery Engine end-user app access.
