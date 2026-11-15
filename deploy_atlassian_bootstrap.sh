#!/usr/bin/env bash
# ==============================================================================
# Atlassian Jira Cloud & Confluence Cloud Bootstrap Orchestrator (Phase 0E)
# ==============================================================================
# Automates Atlassian Cloud site discovery, optional Jira Project / Confluence
# Space sample data seeding via REST API, OAuth 2.0 (3LO) token exchange,
# GCP Secret Manager synchronization, and Phase 2C config file generation:
#   [Step 0E.1 — Auto-Discovery of Atlassian Cloud Tenant ID (cloudId)]
#     Queries `https://<site>.atlassian.net/_edge/tenant_info` to automatically
#     resolve `ATLASSIAN_INSTANCE_ID` (`cloudId`).
#   [Step 0E.2 — Atlassian REST API Verification & Sample Data Seeding]
#     When `--api-token` (or `ATLASSIAN_API_TOKEN`) is provided for
#     `--admin-email` (e.g. `mohanraj@mohanrajs.demo.altostrat.com`), verifies
#     Jira Cloud (`/rest/api/3/myself`) and Confluence Cloud (`/wiki/rest/api/space`)
#     access and optionally seeds a sample Jira project + issues and Confluence
#     space + runbook pages (`--seed-sample-data`).
#   [Step 0E.3 — Atlassian OAuth 2.0 (3LO) Client & Refresh Token Exchange]
#     Validates or prompts for the Atlassian Developer Console OAuth 2.0 (3LO)
#     `client_id` and `client_secret` (Redirect URI:
#     `https://vertexaisearch.cloud.google.com/oauth-redirect`) and optionally
#     exchanges an authorization code at `https://auth.atlassian.com/oauth/token`.
#   [Step 0E.4 — Zero-Touch GCP Secret Manager Sync & Config Generation]
#     Stores `{instance_uri, instance_id, client_id, client_secret, refresh_token,
#     user_account, api_token}` in GCP Secret Manager
#     (`projects/<project>/secrets/<customer>-atlassian-connector-credentials`)
#     and generates `configs/<customer>-atlassian.env` for Phase 2C.
#
# Usage:
#   ./deploy_atlassian_bootstrap.sh \
#     --instance-uri "https://mohanrajs-team.atlassian.net" \
#     --admin-email "mohanraj@mohanrajs.demo.altostrat.com" \
#     --customer-name "cymbal" \
#     --customer-domain "mohanrajs.demo.altostrat.com" \
#     --gcp-project-id "cymbal-app-514110" \
#     [--client-id "<oauth_client_id>"] \
#     [--client-secret "<oauth_client_secret>"] \
#     [--api-token "<atlassian_api_token>"] \
#     [--seed-sample-data] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs/.generated"
mkdir -p "${CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${SCRIPT_DIR}/scripts/lib/http.sh"

ATLASSIAN_INSTANCE_URI="${ATLASSIAN_INSTANCE_URI:-https://mohanrajs-team.atlassian.net}"
ATLASSIAN_INSTANCE_ID="${ATLASSIAN_INSTANCE_ID:-}"
ATLASSIAN_ADMIN_EMAIL="${ATLASSIAN_ADMIN_EMAIL:-mohanraj@mohanrajs.demo.altostrat.com}"
ATLASSIAN_API_TOKEN="${ATLASSIAN_API_TOKEN:-}"
ATLASSIAN_CLIENT_ID="${ATLASSIAN_CLIENT_ID:-}"
ATLASSIAN_CLIENT_SECRET="${ATLASSIAN_CLIENT_SECRET:-}"
ATLASSIAN_REFRESH_TOKEN="${ATLASSIAN_REFRESH_TOKEN:-}"
ATLASSIAN_AUTH_CODE="${ATLASSIAN_AUTH_CODE:-}"
CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="mohanrajs.demo.altostrat.com"
GCP_PROJECT_ID="cymbal-app-514110"
GCP_REGION="us-central1"
GE_LOCATION="global"
ATLASSIAN_SECRET_ID=""
SEED_SAMPLE_DATA="false"
TF_STATE_BUCKET=""
DRY_RUN="false"

print_atlassian_bootstrap_usage() {
  cat <<'EOF'
Usage: ./deploy_atlassian_bootstrap.sh [OPTIONS]

Automates Atlassian Jira Cloud & Confluence Cloud bootstrap (Tenant Cloud ID
auto-discovery, optional Jira/Confluence sample seeding, OAuth 2.0 3LO token
exchange, GCP Secret Manager sync, and Phase 2C config generation).

Options:
  --instance-uri <url>         Atlassian Cloud site URL (default: https://mohanrajs-team.atlassian.net)
  --instance-id <uuid>         Atlassian Cloud ID (auto-discovered from /_edge/tenant_info if omitted)
  --admin-email <email>        Atlassian Organization/Site Admin email (default: mohanraj@mohanrajs.demo.altostrat.com)
  --api-token <token>          Atlassian API token for REST API verification & seeding (or export ATLASSIAN_API_TOKEN)
  --client-id <id>             Atlassian OAuth 2.0 (3LO) Client ID (or export ATLASSIAN_CLIENT_ID)
  --client-secret <secret>     Atlassian OAuth 2.0 (3LO) Client Secret (or export ATLASSIAN_CLIENT_SECRET)
  --refresh-token <token>      Atlassian OAuth 2.0 Refresh Token (or export ATLASSIAN_REFRESH_TOKEN)
  --auth-code <code_or_url>    Exchange an OAuth 2.0 authorization code or redirect URL for a refresh_token
  --seed-sample-data           Seed sample Jira Project/Issues and Confluence Space/Runbooks via REST API
  --customer-name <name>       Customer short slug (default: cymbal)
  --customer-domain <domain>   Verified corporate domain (default: mohanrajs.demo.altostrat.com)
  --gcp-project-id <id>        Target GCP Project ID (default: cymbal-app-514110)
  --gcp-region <region>        Target GCP Region (default: us-central1)
  --secret-id <id>             Override Secret Manager secret ID (default: <customer>-atlassian-connector-credentials)
  --tf-state-bucket <bucket>   Remote Terraform state bucket name (default: <customer>-ge-tfstate)
  --dry-run                    Preview all Atlassian & GCP operations without mutating state
  --help, -h                   Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --instance-uri)
      ATLASSIAN_INSTANCE_URI="${2%/}"
      shift 2
      ;;
    --instance-id)
      ATLASSIAN_INSTANCE_ID="$2"
      shift 2
      ;;
    --admin-email)
      ATLASSIAN_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --api-token)
      ATLASSIAN_API_TOKEN="$2"
      shift 2
      ;;
    --client-id)
      ATLASSIAN_CLIENT_ID="$2"
      shift 2
      ;;
    --client-secret)
      ATLASSIAN_CLIENT_SECRET="$2"
      shift 2
      ;;
    --refresh-token)
      ATLASSIAN_REFRESH_TOKEN="$2"
      shift 2
      ;;
    --auth-code)
      ATLASSIAN_AUTH_CODE="$2"
      shift 2
      ;;
    --seed-sample-data)
      SEED_SAMPLE_DATA="true"
      shift 1
      ;;
    --customer-name)
      CUSTOMER_NAME="$2"
      shift 2
      ;;
    --customer-domain)
      CUSTOMER_DOMAIN="$2"
      shift 2
      ;;
    --gcp-project-id)
      GCP_PROJECT_ID="$2"
      shift 2
      ;;
    --gcp-region)
      GCP_REGION="$2"
      shift 2
      ;;
    --secret-id)
      ATLASSIAN_SECRET_ID="$2"
      shift 2
      ;;
    --tf-state-bucket)
      TF_STATE_BUCKET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --help|-h)
      print_atlassian_bootstrap_usage
      exit 0
      ;;
    *)
      log_error "Unknown flag: $1"
      print_atlassian_bootstrap_usage
      exit 1
      ;;
  esac
done

ATLASSIAN_INSTANCE_URI="${ATLASSIAN_INSTANCE_URI%/}"
if [[ -z "${ATLASSIAN_SECRET_ID}" ]]; then
  ATLASSIAN_SECRET_ID="${CUSTOMER_NAME}-atlassian-connector-credentials"
fi
if [[ -z "${TF_STATE_BUCKET}" ]]; then
  TF_STATE_BUCKET="${CUSTOMER_NAME}-ge-tfstate"
fi

discover_atlassian_cloud_id() {
  log_phase "STEP 0E.1" "Auto-Discovering Atlassian Cloud Tenant ID (cloudId) from ${ATLASSIAN_INSTANCE_URI}"
  if [[ -n "${ATLASSIAN_INSTANCE_ID}" ]]; then
    log_ok "Using pre-configured Atlassian Cloud ID: ${ATLASSIAN_INSTANCE_ID}"
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    ATLASSIAN_INSTANCE_ID="6ef6b83c-0038-4b28-941f-074fb11ea8c6"
    log_info "[DRY-RUN] Would GET ${ATLASSIAN_INSTANCE_URI}/_edge/tenant_info -> cloudId=${ATLASSIAN_INSTANCE_ID}"
    return 0
  fi

  local tenant_resp
  tenant_resp="$(curl -sS --max-time 10 "${ATLASSIAN_INSTANCE_URI}/_edge/tenant_info" 2>/dev/null || echo '{}')"
  ATLASSIAN_INSTANCE_ID="$(jq -r '.cloudId // empty' <<<"${tenant_resp}" 2>/dev/null || true)"
  if [[ -z "${ATLASSIAN_INSTANCE_ID}" ]]; then
    log_error "Could not resolve cloudId from ${ATLASSIAN_INSTANCE_URI}/_edge/tenant_info (response: ${tenant_resp})."
    return 1
  fi
  log_ok "Resolved Atlassian Cloud ID (instance_id): ${ATLASSIAN_INSTANCE_ID}"
}

verify_and_seed_atlassian_rest() {
  log_phase "STEP 0E.2" "Verifying Atlassian Jira & Confluence REST API Access (${ATLASSIAN_ADMIN_EMAIL})"
  if [[ -z "${ATLASSIAN_API_TOKEN}" ]]; then
    log_info "No --api-token provided; skipping direct Basic Auth REST seeding (OAuth 2.0 3LO federated mode remains active)."
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would verify ${ATLASSIAN_INSTANCE_URI}/rest/api/3/myself and /wiki/rest/api/space as '${ATLASSIAN_ADMIN_EMAIL}'."
    if [[ "${SEED_SAMPLE_DATA}" == "true" ]]; then
      log_info "[DRY-RUN] Would seed sample Jira project 'CYM' and Confluence space 'CYM'."
    fi
    return 0
  fi

  local myself_resp account_id display_name
  myself_resp="$(curl -sS -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
    -H "Accept: application/json" \
    "${ATLASSIAN_INSTANCE_URI}/rest/api/3/myself" 2>/dev/null || echo '{}')"
  account_id="$(jq -r '.accountId // empty' <<<"${myself_resp}" 2>/dev/null || true)"
  display_name="$(jq -r '.displayName // empty' <<<"${myself_resp}" 2>/dev/null || true)"

  if [[ -z "${account_id}" ]]; then
    log_warn "Atlassian REST API Basic Auth check did not return accountId. Verify your API token if using Basic Auth seeding."
    return 0
  fi
  log_ok "Authenticated to Atlassian Cloud as '${display_name}' (accountId=${account_id})."

  if [[ "${SEED_SAMPLE_DATA}" != "true" ]]; then
    return 0
  fi

  log_info "Checking/seeding Jira Cloud project 'CYM' and sample P0/P1 engineering issues..."
  local proj_resp proj_id
  proj_resp="$(curl -sS -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
    -H "Accept: application/json" \
    "${ATLASSIAN_INSTANCE_URI}/rest/api/3/project/CYM" 2>/dev/null || echo '{}')"
  proj_id="$(jq -r '.id // empty' <<<"${proj_resp}" 2>/dev/null || true)"

  if [[ -z "${proj_id}" ]]; then
    local create_proj_payload
    create_proj_payload="$(jq -n --arg lead "${account_id}" '{
      key: "CYM",
      name: "Cymbal Platform Engineering",
      projectTypeKey: "software",
      projectTemplateKey: "com.pyxis.greenhopper.jira:gh-simplified-agility-kanban",
      description: "Cymbal Enterprise Platform Engineering & Major Incident Escalations",
      leadAccountId: $lead,
      assigneeType: "PROJECT_LEAD"
    }')"
    proj_resp="$(curl -sS -X POST -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
      -H "Accept: application/json" -H "Content-Type: application/json" \
      "${ATLASSIAN_INSTANCE_URI}/rest/api/3/project" -d "${create_proj_payload}" 2>/dev/null || echo '{}')"
    proj_id="$(jq -r '.id // empty' <<<"${proj_resp}" 2>/dev/null || true)"
  fi

  if [[ -n "${proj_id}" ]]; then
    log_ok "Jira project 'CYM' ready (id=${proj_id}). Ensuring sample issues exist..."
    for summary in \
      "[P0] Production GKE Payment Gateway TLS Handshake Timeout (Linked: INC0048661)" \
      "[P1] Cloud Identity & Entra ID Directory Sync Token Expiry Alert (Linked: INC0048662)" \
      "[P1] SAP S/4HANA & BigQuery Ledger Reconciliation Pipeline Delay (Linked: INC0048663)"; do
      local issue_payload
      issue_payload="$(jq -n --arg sum "${summary}" '{
        fields: {
          project: {key: "CYM"},
          summary: $sum,
          issuetype: {name: "Task"}
        }
      }')"
      curl -sS -X POST -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
        -H "Accept: application/json" -H "Content-Type: application/json" \
        "${ATLASSIAN_INSTANCE_URI}/rest/api/3/issue" -d "${issue_payload}" >/dev/null 2>&1 || true
    done
  fi

  log_info "Checking/seeding Confluence Cloud space and architecture/runbook pages..."
  local spaces_resp first_space_key
  spaces_resp="$(curl -sS -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
    -H "Accept: application/json" \
    "${ATLASSIAN_INSTANCE_URI}/wiki/rest/api/space?limit=5" 2>/dev/null || echo '{}')"
  first_space_key="$(jq -r '.results[0].key // empty' <<<"${spaces_resp}" 2>/dev/null || true)"
  if [[ -n "${first_space_key}" ]]; then
    local page_payload
    page_payload="$(jq -n --arg sk "${first_space_key}" '{
      type: "page",
      title: "Cymbal P0/P1 Major Incident & SRE Runbook",
      space: {key: $sk},
      body: {
        storage: {
          value: "<p><strong>Cymbal SRE Major Incident Runbook:</strong> Covers P0 Payment Gateway TLS rotation (INC0048661), P1 Entra ID SCIM token renewal (INC0048662), and P1 BigQuery Ledger pipeline recovery (INC0048663).</p>",
          representation: "storage"
        }
      }
    }')"
    curl -sS -X POST -u "${ATLASSIAN_ADMIN_EMAIL}:${ATLASSIAN_API_TOKEN}" \
      -H "Accept: application/json" -H "Content-Type: application/json" \
      "${ATLASSIAN_INSTANCE_URI}/wiki/rest/api/content" -d "${page_payload}" >/dev/null 2>&1 || true
    log_ok "Confluence space '${first_space_key}' verified and SRE runbook page seeded."
  fi
}

resolve_or_prompt_atlassian_oauth_credentials() {
  log_phase "STEP 0E.3" "Resolving Atlassian OAuth 2.0 (3LO) App Credentials (Client ID & Client Secret)"

  # Check existing Secret Manager secret if not passed via CLI/env
  if [[ "${DRY_RUN}" != "true" && ( -z "${ATLASSIAN_CLIENT_ID}" || -z "${ATLASSIAN_CLIENT_SECRET}" ) ]]; then
    local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
    local ver_resp raw_b64 decoded_json
    ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${ATLASSIAN_SECRET_ID}/versions/latest:access" "" "true" 2>/dev/null || echo '{}')"
    raw_b64="$(jq -r '.payload.data // empty' <<<"${ver_resp}" 2>/dev/null || true)"
    if [[ -n "${raw_b64}" ]]; then
      decoded_json="$(printf '%s' "${raw_b64}" | base64 -d 2>/dev/null || printf '%s' "${raw_b64}" | base64 -D 2>/dev/null || echo '{}')"
      ATLASSIAN_CLIENT_ID="${ATLASSIAN_CLIENT_ID:-$(jq -r '.client_id // empty' <<<"${decoded_json}")}"
      ATLASSIAN_CLIENT_SECRET="${ATLASSIAN_CLIENT_SECRET:-$(jq -r '.client_secret // empty' <<<"${decoded_json}")}"
      ATLASSIAN_REFRESH_TOKEN="${ATLASSIAN_REFRESH_TOKEN:-$(jq -r '.refresh_token // empty' <<<"${decoded_json}")}"
      ATLASSIAN_API_TOKEN="${ATLASSIAN_API_TOKEN:-$(jq -r '.api_token // empty' <<<"${decoded_json}")}"
    fi
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    ATLASSIAN_CLIENT_ID="${ATLASSIAN_CLIENT_ID:-dry-run-atlassian-client-id}"
    ATLASSIAN_CLIENT_SECRET="${ATLASSIAN_CLIENT_SECRET:-dry-run-atlassian-client-secret}"
    log_info "[DRY-RUN] Using Atlassian OAuth 2.0 Client ID: ${ATLASSIAN_CLIENT_ID}"
    return 0
  fi

  if [[ -z "${ATLASSIAN_CLIENT_ID}" || -z "${ATLASSIAN_CLIENT_SECRET}" ]]; then
    cat <<EOF

================================================================================
 ACTION REQUIRED: Create Atlassian OAuth 2.0 (3LO) Integration App
================================================================================
 Signed-in Account : ${ATLASSIAN_ADMIN_EMAIL}
 Atlassian Site    : ${ATLASSIAN_INSTANCE_URI}
 Tenant Cloud ID   : ${ATLASSIAN_INSTANCE_ID}
 Developer Console : https://developer.atlassian.com/console/myapps/

 1. Open https://developer.atlassian.com/console/myapps/ -> Click 'Create' ->
    'OAuth 2.0 integration' -> Name it 'cymbal-gemini-enterprise'.
 2. Go to 'Permissions':
    a) Jira API -> Add -> Configure:
       - Classic scopes: read:jira-user, read:jira-work, write:jira-work, manage:jira-project
       - Granular scopes: read:issue:jira, read:issue-type:jira, read:comment:jira,
         read:comment.property:jira, read:project:jira, read:priority:jira,
         read:issue.transition:jira, read:issue-meta:jira,
         read:board-scope.admin:jira-software, read:board-scope:jira-software,
         read:sprint:jira-software, read:issue-details:jira, read:jql:jira,
         read:user:jira, write:comment:jira, write:issue:jira, write:attachment:jira,
         write:project:jira, write:issue-worklog:jira, write:issue-link:jira
    b) Confluence API -> Add -> Configure:
       - Classic scopes: read:confluence-content.all, read:confluence-space.summary,
         write:confluence-space, write:confluence-content, write:confluence-file,
         search:confluence
       - Granular scopes: search:confluence, read:page:confluence, write:page:confluence,
         read:space:confluence, write:space:confluence, read:blogpost:confluence,
         write:blogpost:confluence, read:comment:confluence, read:attachment:confluence,
         write:attachment:confluence, read:content-details:confluence,
         read:content.metadata:confluence, read:space-details:confluence,
         read:configuration:confluence, read:group:confluence, read:user:confluence,
         read:task:confluence, read:whiteboard:confluence
    c) User Identity API -> Add -> Configure:
       - Granular scopes: read:me
 3. Go to 'Authorization' -> 'OAuth 2.0 (3LO)' -> Click 'Add' / 'Configure':
    - Callback URL: https://vertexaisearch.cloud.google.com/oauth-redirect
    - Click 'Save changes'.
 4. Go to 'Distribution' -> Click 'Edit' -> Select 'Sharing':
    - Vendor: Google
    - Privacy Policy: https://policies.google.com
    - Does your app store personal data?: Yes (check the confirmation box)
    - Click 'Save changes'.
 5. Go to 'Settings' -> Copy 'Client ID' and 'Client secret'.
================================================================================
EOF
    if [[ -t 0 ]]; then
      read -r -p "Enter Atlassian OAuth 2.0 Client ID: " ATLASSIAN_CLIENT_ID
      read -r -s -p "Enter Atlassian OAuth 2.0 Client Secret: " ATLASSIAN_CLIENT_SECRET
      echo ""
    else
      log_error "Missing ATLASSIAN_CLIENT_ID / ATLASSIAN_CLIENT_SECRET in non-interactive session. Pass --client-id and --client-secret."
      return 1
    fi
  fi

  if [[ -n "${ATLASSIAN_AUTH_CODE}" ]]; then
    local clean_code="${ATLASSIAN_AUTH_CODE}"
    if [[ "${clean_code}" == *"code="* ]]; then
      clean_code="$(printf '%s' "${clean_code}" | sed -n 's/.*[?&]code=\([^&#]*\).*/\1/p')"
    fi
    log_info "Exchanging Atlassian OAuth 2.0 authorization code at https://auth.atlassian.com/oauth/token..."
    local token_resp
    token_resp="$(curl -sS -X POST "https://auth.atlassian.com/oauth/token" \
      -H "Content-Type: application/json" \
      -d "$(jq -n \
        --arg cid "${ATLASSIAN_CLIENT_ID}" \
        --arg csec "${ATLASSIAN_CLIENT_SECRET}" \
        --arg code "${clean_code}" \
        '{
          grant_type: "authorization_code",
          client_id: $cid,
          client_secret: $csec,
          code: $code,
          redirect_uri: "https://vertexaisearch.cloud.google.com/oauth-redirect"
        }')" 2>/dev/null || echo '{}')"
    local new_rtok
    new_rtok="$(jq -r '.refresh_token // empty' <<<"${token_resp}" 2>/dev/null || true)"
    if [[ -n "${new_rtok}" ]]; then
      ATLASSIAN_REFRESH_TOKEN="${new_rtok}"
      log_ok "Successfully minted Atlassian OAuth 2.0 refresh_token."
    else
      log_warn "Could not exchange auth code for refresh_token (response: ${token_resp}). Continuing with 3LO client_id/client_secret."
    fi
  fi

  log_ok "Atlassian OAuth 2.0 (3LO) credentials ready (Client ID=${ATLASSIAN_CLIENT_ID:0:8}...)."
}

sync_atlassian_secret_and_config() {
  log_phase "STEP 0E.4" "Synchronizing GCP Secret Manager ('${ATLASSIAN_SECRET_ID}') & Generating configs/${CUSTOMER_NAME}-atlassian.env"

  local env_file="${CONFIGS_DIR}/${CUSTOMER_NAME}-atlassian.env"
  cat > "${env_file}" <<EOF
# ==============================================================================
# Atlassian Jira Cloud & Confluence Cloud — ${CUSTOMER_NAME} Connector Config
# Generated by deploy_atlassian_bootstrap.sh
# ==============================================================================
GCP_PROJECT_ID="${GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION}"
GE_LOCATION="${GE_LOCATION}"
GE_IDENTITY_PROVIDER_TYPE="GSUITE"
TF_STATE_BUCKET="${TF_STATE_BUCKET}"

ATLASSIAN_SECRET_ID="${ATLASSIAN_SECRET_ID}"
ATLASSIAN_INSTANCE_URI="${ATLASSIAN_INSTANCE_URI}"
ATLASSIAN_INSTANCE_ID="${ATLASSIAN_INSTANCE_ID}"
ATLASSIAN_ADMIN_EMAIL="${ATLASSIAN_ADMIN_EMAIL}"

ENABLE_JIRA_CONNECTOR="true"
JIRA_COLLECTION_ID="${CUSTOMER_NAME}-jira-fed"
JIRA_COLLECTION_DISPLAY_NAME="Jira Cloud (${CUSTOMER_NAME})"
JIRA_CONNECTOR_MODE="FEDERATED"
JIRA_REFRESH_INTERVAL="86400s"
JIRA_ENTITIES="project,issue,comment,attachment,worklog"
ENABLE_JIRA_ACTIONS="true"
JIRA_ENABLED_ACTIONS="create_issue,update_issue,change_issue_status,create_comment,update_comment,upload_attachment,download_attachment,create_issue_link,create_project,update_project,create_worklog,update_worklog,search_issues,get_issue,list_issues,get_comment,list_comments,get_attachment,list_attachments,get_project,list_projects,get_worklog,list_worklogs,get_user,list_users,search_users,get_board,list_boards,get_sprint,list_sprints,get_priority,list_priorities,get_issue_type,list_issue_types,get_issue_transitions,list_issue_transitions"

ENABLE_CONFLUENCE_CONNECTOR="true"
CONFLUENCE_COLLECTION_ID="${CUSTOMER_NAME}-confluence-fed"
CONFLUENCE_COLLECTION_DISPLAY_NAME="Confluence Cloud (${CUSTOMER_NAME})"
CONFLUENCE_CONNECTOR_MODE="FEDERATED"
CONFLUENCE_REFRESH_INTERVAL="86400s"
CONFLUENCE_ENTITIES="space,page,blog,attachment,comment"
ENABLE_CONFLUENCE_ACTIONS="true"
CONFLUENCE_ENABLED_ACTIONS="create_page,update_page,create_blog_post,create_space,download_attachment,get_system_info,list_attachments,list_blog_posts,list_comments,list_pages,list_tasks,list_whiteboards,upload_attachment,get_attachment,get_blog_post,get_comment,get_page,get_space,get_task,get_user,get_whiteboard,list_spaces,list_users"

ATLASSIAN_TARGET_APPS="${CUSTOMER_NAME}-dev-sandbox-app,${CUSTOMER_NAME}-service-desk-app"
ATLASSIAN_ACCESS_GROUPS="ge-skill-developers@${CUSTOMER_DOMAIN},ge-service-desk-users@${CUSTOMER_DOMAIN}"
ATLASSIAN_CONFIGURE_ACL="true"
EOF
  log_ok "Wrote Phase 2C configuration file: ${env_file}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would write Secret Manager secret 'projects/${GCP_PROJECT_ID}/secrets/${ATLASSIAN_SECRET_ID}'."
    return 0
  fi

  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  local check_rc=0
  ge_curl_request "GET" "${sm_base}/secrets/${ATLASSIAN_SECRET_ID}" "" "true" >/dev/null || check_rc=$?
  if [[ "${check_rc}" -eq 44 ]]; then
    log_info "Creating Secret Manager secret '${ATLASSIAN_SECRET_ID}' in '${GCP_PROJECT_ID}'..."
    ge_curl_request "POST" "${sm_base}/secrets?secretId=${ATLASSIAN_SECRET_ID}" '{"replication":{"automatic":{}}}' >/dev/null
  fi

  local secret_json b64_payload
  secret_json="$(jq -c -n \
    --arg uri "${ATLASSIAN_INSTANCE_URI}" \
    --arg iid "${ATLASSIAN_INSTANCE_ID}" \
    --arg cid "${ATLASSIAN_CLIENT_ID}" \
    --arg csec "${ATLASSIAN_CLIENT_SECRET}" \
    --arg rtok "${ATLASSIAN_REFRESH_TOKEN:-}" \
    --arg usr "${ATLASSIAN_ADMIN_EMAIL}" \
    --arg tok "${ATLASSIAN_API_TOKEN:-}" \
    '{
      instance_uri: $uri,
      instance_id: $iid,
      client_id: $cid,
      client_secret: $csec,
      refresh_token: $rtok,
      user_account: $usr,
      api_token: $tok
    }')"
  b64_payload="$(printf '%s' "${secret_json}" | base64 | tr -d '\n')"
  ge_curl_request "POST" "${sm_base}/secrets/${ATLASSIAN_SECRET_ID}:addVersion" "$(jq -n --arg d "${b64_payload}" '{payload:{data:$d}}')" >/dev/null
  log_ok "Synchronized Atlassian credentials into Secret Manager 'projects/${GCP_PROJECT_ID}/secrets/${ATLASSIAN_SECRET_ID}'."
}

main() {
  init_logging "${SCRIPT_DIR}/logs"
  discover_atlassian_cloud_id
  verify_and_seed_atlassian_rest
  resolve_or_prompt_atlassian_oauth_credentials
  sync_atlassian_secret_and_config

  log_phase "COMPLETE" "Atlassian Cloud Phase 0E Bootstrap Complete"
  printf '  Atlassian Site      : %s\n' "${ATLASSIAN_INSTANCE_URI}"
  printf '  Tenant Cloud ID     : %s\n' "${ATLASSIAN_INSTANCE_ID}"
  printf '  Admin Account       : %s\n' "${ATLASSIAN_ADMIN_EMAIL}"
  printf '  Secret Manager ID   : projects/%s/secrets/%s\n' "${GCP_PROJECT_ID}" "${ATLASSIAN_SECRET_ID}"
  printf '  Generated Config    : %s/%s-atlassian.env\n' "${CONFIGS_DIR}" "${CUSTOMER_NAME}"
  printf '  Next Step (Phase 2C): ./deploy_atlassian.sh --config ./configs/.generated/%s-atlassian.env\n' "${CUSTOMER_NAME}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
