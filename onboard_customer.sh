#!/usr/bin/env bash
# ==============================================================================
# Master End-to-End Customer Onboarding Orchestrator (onboard_customer.sh)
# ==============================================================================
# Chains all 14 modular onboarding phases for any enterprise customer (e.g., Cymbal),
# controlled via a phase configuration file (`configs/<customer>-onboard.env`) or CLI flags:
#   - Phase 0C: GCP APIs & Remote Terraform State Bucket (ENABLE_PHASE_0C_GCP_FOUNDATION)
#   - Phase 0B: Google Admin & Cloud Identity Bootstrap (ENABLE_PHASE_0B_GOOGLE_ADMIN)
#   - Phase 0A: Microsoft Entra ID OAuth + 49 Scopes + SAML Gallery App (ENABLE_PHASE_0A_ENTRA_BOOTSTRAP)
#   - Phase 0D: ServiceNow Instance Bootstrap — User, Roles, OAuth 2.0 & Secret Sync (ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP)
#   - Phase 0E: Atlassian Cloud Bootstrap — Tenant Cloud ID, OAuth 2.0 3LO & Secret Sync (ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP)
#   - Phase 1A: GCP Directory Sync Config & GE License Sync (ENABLE_PHASE_1A_DIRECTORY_SYNC)
#   - Phase 1B: Cloud Identity Per-App Group Nesting & SAML Handshake (ENABLE_PHASE_1B_IDENTITY_TERRAFORM)
#   - Phase 1C: Optional Sandbox CSV Group Membership Seeding (ENABLE_PHASE_1C_DEMO_CSV_SEED)
#   - Phase 2 : Shared M365 Connectors — SharePoint, OneDrive, Outlook, Teams (ENABLE_PHASE_2_M365_CONNECTORS)
#   - Phase 2B: Shared ServiceNow Connector — KB, Incidents, Catalog Items & Actions (ENABLE_PHASE_2B_SERVICENOW_CONNECTOR)
#   - Phase 2C: Shared Atlassian Connectors — Jira Cloud, Confluence Cloud & Actions (ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS)
#   - Phase 3 : Departmental Gemini Enterprise Apps — Dev, Service Desk, Finance, HR (ENABLE_PHASE_3_GE_APPS)
#   - Phase 4 : Universal ADK Skill Orchestrator Deploy & Pin (ENABLE_PHASE_4_UNIVERSAL_AGENT)
#   - Phase 5 : 6-Rubric Benchmark Gate, GCS Upload & Multi-App Skill Sharing (ENABLE_PHASE_5_SKILL_SHARING)
#
# Usage:
#   # 1. Run using the phase configuration file:
#   ./onboard_customer.sh --config ./configs/cymbal-onboard.env
#
#   # 2. Run only specific phases (overrides config toggles):
#   ./onboard_customer.sh --config ./configs/cymbal-onboard.env --only-phases 3,4,5
#
#   # 3. Skip specific phases (overrides config toggles):
#   ./onboard_customer.sh --config ./configs/cymbal-onboard.env --skip-phases 0C,0B,0A,1A,1B,2
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
GENERATED_CONFIGS_DIR="${CONFIGS_DIR}/.generated"
mkdir -p "${CONFIGS_DIR}" "${GENERATED_CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

# Default Customer & Cloud Parameters
ONBOARD_CONFIG_FILE=""
CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
GCP_REGION="us-central1"
ENTRA_TENANT_ID=""
DNS_PROJECT_ID=""
DNS_ZONE_NAME=""
MEMBERS_CSV=""
ENTRA_MODE="terraform"
SERVICENOW_INSTANCE_URI=""
SERVICENOW_ADMIN_USER="admin"
SERVICENOW_ADMIN_PASSWORD="${SN_ADMIN_PASSWORD:-}"
ATLASSIAN_INSTANCE_URI=""
ATLASSIAN_INSTANCE_ID=""
ATLASSIAN_ADMIN_EMAIL=""
ATLASSIAN_CLIENT_ID="${ATLASSIAN_CLIENT_ID:-}"
ATLASSIAN_CLIENT_SECRET="${ATLASSIAN_CLIENT_SECRET:-}"
ATLASSIAN_API_TOKEN="${ATLASSIAN_API_TOKEN:-}"
DRY_RUN="false"

# Default Phase Enablement Toggles (ServiceNow, Atlassian, Universal Agent & Skill Sharing are optional add-ons: false by default)
ENABLE_PHASE_0C_GCP_FOUNDATION="true"
ENABLE_PHASE_0B_GOOGLE_ADMIN="true"
ENABLE_PHASE_0A_ENTRA_BOOTSTRAP="true"
ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP="false"
ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP="false"
ENABLE_PHASE_1A_DIRECTORY_SYNC="true"
ENABLE_PHASE_1B_IDENTITY_TERRAFORM="true"
ENABLE_PHASE_1C_DEMO_CSV_SEED="false"
ENABLE_PHASE_2_M365_CONNECTORS="true"
ENABLE_PHASE_2B_SERVICENOW_CONNECTOR="false"
ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS="false"
ENABLE_PHASE_3_GE_APPS="true"
PHASE_3_TARGET_APPS=""
ENABLE_PHASE_4_UNIVERSAL_AGENT="false"
PHASE_4_DEPLOY_REASONING_ENGINE="true"
ENABLE_PHASE_5_SKILL_SHARING="false"

# CLI Override Trackers
CLI_WITH_SERVICENOW=""
CLI_WITH_ATLASSIAN=""
CLI_WITH_UNIVERSAL_AGENT=""
CLI_WITH_SKILL_SHARING=""
CLI_CUSTOMER_NAME=""
CLI_CUSTOMER_DOMAIN=""
CLI_GCP_PROJECT_ID=""
CLI_GCP_REGION=""
CLI_ENTRA_TENANT_ID=""
CLI_DNS_PROJECT_ID=""
CLI_DNS_ZONE_NAME=""
CLI_MEMBERS_CSV=""
CLI_SEED_DEMO_CSV=""
CLI_ENTRA_MODE=""
CLI_SN_INSTANCE_URI=""
CLI_SN_ADMIN_USER=""
CLI_SN_ADMIN_PASSWORD=""
CLI_AT_INSTANCE_URI=""
CLI_AT_INSTANCE_ID=""
CLI_AT_ADMIN_EMAIL=""
CLI_AT_CLIENT_ID=""
CLI_AT_CLIENT_SECRET=""
CLI_AT_API_TOKEN=""
CLI_TARGET_APPS=""
CLI_SKIP_REASONING_ENGINE_DEPLOY=""
CLI_TF_STATE_BUCKET=""
CLI_ONLY_PHASES=""
CLI_SKIP_PHASES=""

_append_only_phase() {
  local p="$1"
  if [[ -z "${CLI_ONLY_PHASES}" ]]; then
    CLI_ONLY_PHASES="${p}"
  else
    CLI_ONLY_PHASES="${CLI_ONLY_PHASES},${p}"
  fi
}

print_onboard_usage() {
  cat <<'EOF'
Usage: ./onboard_customer.sh [OPTIONS]

Master End-to-End Customer Onboarding Orchestrator with Per-Phase Config Toggles.

Options:
  --config <path>              Path to onboarding config file (default: configs/<customer>-onboard.env if present)
  --only-phases <list>         Comma-separated list of phases to run (e.g. "0D,0E,2B,2C" or "3,4,5")
  --skip-phases <list>         Comma-separated list of phases to skip (e.g. "0C,0B,0A,1A,1B,2")
  --customer-name <name>       Customer short name (e.g. "cymbal")
  --customer-domain <dom>      Verified corporate domain (e.g. "mohanrajs.demo.altostrat.com")
  --gcp-project-id <id>        Target Google Cloud Project ID
  --gcp-region <region>        Target GCP Region for Vertex AI Reasoning Engine (default: us-central1)
  --entra-tenant-id <uuid>     Microsoft Entra ID Tenant UUID
  --dns-project-id <id>        Cloud DNS Project ID (defaults to --gcp-project-id)
  --dns-zone-name <zone>       Cloud DNS Managed Zone name
  --entra-mode <mode>          Entra bootstrap mode: terraform (default) or az-graph
  --servicenow-instance-uri    ServiceNow Instance URL for Phase 0D/2B (e.g. https://gcpconnector3.service-now.com)
  --servicenow-admin-user      ServiceNow admin username for Phase 0D (default: admin)
  --servicenow-admin-password  ServiceNow admin password for Phase 0D (or export SN_ADMIN_PASSWORD)
  --atlassian-instance-uri     Atlassian Cloud Site URL for Phase 0E/2C (e.g. https://mohanrajs-team.atlassian.net)
  --atlassian-instance-id      Atlassian Tenant Cloud ID (auto-discovered if omitted)
  --atlassian-admin-email      Atlassian Admin Email for Phase 0E/2C
  --atlassian-client-id        Atlassian OAuth 2.0 (3LO) Client ID for Phase 0E
  --atlassian-client-secret    Atlassian OAuth 2.0 (3LO) Client Secret for Phase 0E
  --atlassian-api-token        Optional Atlassian API Token for REST verification/seeding in Phase 0E
  --seed-demo-csv              Enable Phase 1C sandbox CSV group membership seeding
  --members-csv <path>         Custom CSV path for Phase 1C sandbox seeding
  --dry-run                    Preview all enabled phases without mutating remote state
  --help, -h                   Show this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      ONBOARD_CONFIG_FILE="$2"
      shift 2
      ;;
    --only-phases|--only|--only-steps)
      CLI_ONLY_PHASES="$2"
      shift 2
      ;;
    --skip-phases|--skip|--skip-steps)
      CLI_SKIP_PHASES="$2"
      shift 2
      ;;
    --gcp-foundation|--step-0c)
      _append_only_phase "gcp-foundation"
      shift 1
      ;;
    --google-admin|--step-0b)
      _append_only_phase "google-admin"
      shift 1
      ;;
    --entra-bootstrap|--step-0a)
      _append_only_phase "entra-bootstrap"
      shift 1
      ;;
    --servicenow-bootstrap|--step-0d)
      _append_only_phase "servicenow-bootstrap"
      shift 1
      ;;
    --atlassian-bootstrap|--step-0e)
      _append_only_phase "atlassian-bootstrap"
      shift 1
      ;;
    --directory-sync|--step-1a)
      _append_only_phase "directory-sync"
      shift 1
      ;;
    --identity-terraform|--cloud-identity-groups|--step-1b)
      _append_only_phase "identity-terraform"
      shift 1
      ;;
    --m365-connectors|--step-2)
      _append_only_phase "m365-connectors"
      shift 1
      ;;
    --servicenow-connector|--step-2b)
      _append_only_phase "servicenow-connector"
      shift 1
      ;;
    --atlassian-connectors|--step-2c)
      _append_only_phase "atlassian-connectors"
      shift 1
      ;;
    --ge-apps|--step-3)
      _append_only_phase "ge-apps"
      shift 1
      ;;
    --agent-publish|--universal-agent|--step-4)
      _append_only_phase "universal-agent"
      shift 1
      ;;
    --skill-publish|--skill-sharing|--step-5)
      _append_only_phase "skill-sharing"
      shift 1
      ;;
    --with-servicenow)
      CLI_WITH_SERVICENOW="true"
      shift 1
      ;;
    --with-atlassian)
      CLI_WITH_ATLASSIAN="true"
      shift 1
      ;;
    --with-agent-publish|--with-universal-agent)
      CLI_WITH_UNIVERSAL_AGENT="true"
      shift 1
      ;;
    --with-skill-publish|--with-skill-sharing)
      CLI_WITH_SKILL_SHARING="true"
      shift 1
      ;;
    --target-apps)
      CLI_TARGET_APPS="$2"
      shift 2
      ;;
    --skip-reasoning-engine-deploy)
      CLI_SKIP_REASONING_ENGINE_DEPLOY="true"
      shift 1
      ;;
    --tf-state-bucket)
      CLI_TF_STATE_BUCKET="$2"
      shift 2
      ;;
    --customer-name)
      CLI_CUSTOMER_NAME="$2"
      CUSTOMER_NAME="$2"
      shift 2
      ;;
    --customer-domain)
      CLI_CUSTOMER_DOMAIN="$2"
      shift 2
      ;;
    --gcp-project-id)
      CLI_GCP_PROJECT_ID="$2"
      shift 2
      ;;
    --gcp-region)
      CLI_GCP_REGION="$2"
      shift 2
      ;;
    --entra-tenant-id|--tenant-id)
      CLI_ENTRA_TENANT_ID="$2"
      shift 2
      ;;
    --dns-project-id)
      CLI_DNS_PROJECT_ID="$2"
      shift 2
      ;;
    --dns-zone-name)
      CLI_DNS_ZONE_NAME="$2"
      shift 2
      ;;
    --members-csv)
      CLI_MEMBERS_CSV="$2"
      CLI_SEED_DEMO_CSV="true"
      shift 2
      ;;
    --seed-demo-csv)
      CLI_SEED_DEMO_CSV="true"
      shift 1
      ;;
    --entra-mode)
      CLI_ENTRA_MODE="$2"
      shift 2
      ;;
    --servicenow-instance-uri)
      CLI_SN_INSTANCE_URI="$2"
      shift 2
      ;;
    --servicenow-admin-user)
      CLI_SN_ADMIN_USER="$2"
      shift 2
      ;;
    --servicenow-admin-password)
      CLI_SN_ADMIN_PASSWORD="$2"
      shift 2
      ;;
    --atlassian-instance-uri)
      CLI_AT_INSTANCE_URI="$2"
      shift 2
      ;;
    --atlassian-instance-id)
      CLI_AT_INSTANCE_ID="$2"
      shift 2
      ;;
    --atlassian-admin-email)
      CLI_AT_ADMIN_EMAIL="$2"
      shift 2
      ;;
    --atlassian-client-id)
      CLI_AT_CLIENT_ID="$2"
      shift 2
      ;;
    --atlassian-client-secret)
      CLI_AT_CLIENT_SECRET="$2"
      shift 2
      ;;
    --atlassian-api-token)
      CLI_AT_API_TOKEN="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    --help|-h)
      print_onboard_usage
      exit 0
      ;;
    *)
      echo "Unknown flag: $1"
      print_onboard_usage
      exit 1
      ;;
  esac
done

# Auto-discover configs/<customer>-onboard.env if --config was not explicitly passed
if [[ -z "${ONBOARD_CONFIG_FILE}" && -f "${CONFIGS_DIR}/${CUSTOMER_NAME}-onboard.env" ]]; then
  ONBOARD_CONFIG_FILE="${CONFIGS_DIR}/${CUSTOMER_NAME}-onboard.env"
fi

if [[ -n "${ONBOARD_CONFIG_FILE}" ]]; then
  if [[ ! -f "${ONBOARD_CONFIG_FILE}" ]]; then
    echo "ERROR: Onboarding configuration file not found: ${ONBOARD_CONFIG_FILE}"
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  source "${ONBOARD_CONFIG_FILE}"
  set +a
fi

# Re-apply explicit CLI overrides on top of config file values
[[ -n "${CLI_CUSTOMER_NAME}" ]] && CUSTOMER_NAME="${CLI_CUSTOMER_NAME}"
[[ -n "${CLI_CUSTOMER_DOMAIN}" ]] && CUSTOMER_DOMAIN="${CLI_CUSTOMER_DOMAIN}"
[[ -n "${CLI_GCP_PROJECT_ID}" ]] && GCP_PROJECT_ID="${CLI_GCP_PROJECT_ID}"
[[ -n "${CLI_GCP_REGION}" ]] && GCP_REGION="${CLI_GCP_REGION}"
[[ -n "${CLI_ENTRA_TENANT_ID}" ]] && ENTRA_TENANT_ID="${CLI_ENTRA_TENANT_ID}"
[[ -n "${CLI_DNS_PROJECT_ID}" ]] && DNS_PROJECT_ID="${CLI_DNS_PROJECT_ID}"
[[ -n "${CLI_DNS_ZONE_NAME}" ]] && DNS_ZONE_NAME="${CLI_DNS_ZONE_NAME}"
[[ -n "${CLI_MEMBERS_CSV}" ]] && MEMBERS_CSV="${CLI_MEMBERS_CSV}"
[[ -n "${CLI_SEED_DEMO_CSV}" ]] && ENABLE_PHASE_1C_DEMO_CSV_SEED="${CLI_SEED_DEMO_CSV}"
[[ -n "${CLI_ENTRA_MODE}" ]] && ENTRA_MODE="${CLI_ENTRA_MODE}"
[[ -n "${CLI_SN_INSTANCE_URI}" ]] && SERVICENOW_INSTANCE_URI="${CLI_SN_INSTANCE_URI}"
[[ -n "${CLI_SN_ADMIN_USER}" ]] && SERVICENOW_ADMIN_USER="${CLI_SN_ADMIN_USER}"
[[ -n "${CLI_SN_ADMIN_PASSWORD}" ]] && SERVICENOW_ADMIN_PASSWORD="${CLI_SN_ADMIN_PASSWORD}"
[[ -n "${CLI_AT_INSTANCE_URI}" ]] && ATLASSIAN_INSTANCE_URI="${CLI_AT_INSTANCE_URI}"
[[ -n "${CLI_AT_INSTANCE_ID}" ]] && ATLASSIAN_INSTANCE_ID="${CLI_AT_INSTANCE_ID}"
[[ -n "${CLI_AT_ADMIN_EMAIL}" ]] && ATLASSIAN_ADMIN_EMAIL="${CLI_AT_ADMIN_EMAIL}"
[[ -n "${CLI_AT_CLIENT_ID}" ]] && ATLASSIAN_CLIENT_ID="${CLI_AT_CLIENT_ID}"
[[ -n "${CLI_AT_CLIENT_SECRET}" ]] && ATLASSIAN_CLIENT_SECRET="${CLI_AT_CLIENT_SECRET}"
[[ -n "${CLI_AT_API_TOKEN}" ]] && ATLASSIAN_API_TOKEN="${CLI_AT_API_TOKEN}"
[[ -n "${CLI_TARGET_APPS}" ]] && PHASE_3_TARGET_APPS="${CLI_TARGET_APPS}"
[[ "${CLI_SKIP_REASONING_ENGINE_DEPLOY}" == "true" ]] && PHASE_4_DEPLOY_REASONING_ENGINE="false"
if [[ "${CLI_WITH_SERVICENOW}" == "true" ]]; then
  ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP="true"
  ENABLE_PHASE_2B_SERVICENOW_CONNECTOR="true"
fi
if [[ "${CLI_WITH_ATLASSIAN}" == "true" ]]; then
  ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP="true"
  ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS="true"
fi
if [[ "${CLI_WITH_UNIVERSAL_AGENT}" == "true" ]]; then
  ENABLE_PHASE_4_UNIVERSAL_AGENT="true"
fi
if [[ "${CLI_WITH_SKILL_SHARING}" == "true" ]]; then
  ENABLE_PHASE_5_SKILL_SHARING="true"
fi

_set_phase_toggle() {
  local phase_code
  phase_code="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | tr '_' '-' | xargs)"
  phase_code="${phase_code#--}"
  local val="$2"
  case "${phase_code}" in
    0C|STEP-0C|GCP-FOUNDATION) ENABLE_PHASE_0C_GCP_FOUNDATION="${val}" ;;
    0B|STEP-0B|GOOGLE-ADMIN) ENABLE_PHASE_0B_GOOGLE_ADMIN="${val}" ;;
    0A|STEP-0A|ENTRA-BOOTSTRAP) ENABLE_PHASE_0A_ENTRA_BOOTSTRAP="${val}" ;;
    0D|STEP-0D|SERVICENOW-BOOTSTRAP) ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP="${val}" ;;
    0E|STEP-0E|ATLASSIAN-BOOTSTRAP) ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP="${val}" ;;
    1A|STEP-1A|DIRECTORY-SYNC) ENABLE_PHASE_1A_DIRECTORY_SYNC="${val}" ;;
    1B|STEP-1B|IDENTITY-TERRAFORM|CLOUD-IDENTITY-GROUPS) ENABLE_PHASE_1B_IDENTITY_TERRAFORM="${val}" ;;
    1C|STEP-1C|SEED-DEMO-CSV) ENABLE_PHASE_1C_DEMO_CSV_SEED="${val}" ;;
    1)
      ENABLE_PHASE_1A_DIRECTORY_SYNC="${val}"
      ENABLE_PHASE_1B_IDENTITY_TERRAFORM="${val}"
      ;;
    2|STEP-2|M365-CONNECTORS)  ENABLE_PHASE_2_M365_CONNECTORS="${val}" ;;
    2B|STEP-2B|SERVICENOW-CONNECTOR) ENABLE_PHASE_2B_SERVICENOW_CONNECTOR="${val}" ;;
    2C|STEP-2C|ATLASSIAN-CONNECTORS) ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS="${val}" ;;
    3|STEP-3|GE-APPS)  ENABLE_PHASE_3_GE_APPS="${val}" ;;
    4|STEP-4|UNIVERSAL-AGENT|AGENT-PUBLISH|AGENT-PUBLISHING)  ENABLE_PHASE_4_UNIVERSAL_AGENT="${val}" ;;
    5|STEP-5|SKILL-SHARING|SKILL-PUBLISH|SKILL-PUBLISHING)  ENABLE_PHASE_5_SKILL_SHARING="${val}" ;;
    *)
      echo "ERROR: Unknown onboarding module '${phase_code}' (valid: gcp-foundation, google-admin, entra-bootstrap, servicenow-bootstrap, atlassian-bootstrap, directory-sync, identity-terraform, seed-demo-csv, m365-connectors, servicenow-connector, atlassian-connectors, ge-apps, universal-agent, skill-sharing)"
      exit 1
      ;;
  esac
}

if [[ -n "${CLI_ONLY_PHASES}" ]]; then
  ENABLE_PHASE_0C_GCP_FOUNDATION="false"
  ENABLE_PHASE_0B_GOOGLE_ADMIN="false"
  ENABLE_PHASE_0A_ENTRA_BOOTSTRAP="false"
  ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP="false"
  ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP="false"
  ENABLE_PHASE_1A_DIRECTORY_SYNC="false"
  ENABLE_PHASE_1B_IDENTITY_TERRAFORM="false"
  ENABLE_PHASE_1C_DEMO_CSV_SEED="false"
  ENABLE_PHASE_2_M365_CONNECTORS="false"
  ENABLE_PHASE_2B_SERVICENOW_CONNECTOR="false"
  ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS="false"
  ENABLE_PHASE_3_GE_APPS="false"
  ENABLE_PHASE_4_UNIVERSAL_AGENT="false"
  ENABLE_PHASE_5_SKILL_SHARING="false"
  IFS=',' read -r -a only_arr <<< "${CLI_ONLY_PHASES}"
  for p in "${only_arr[@]}"; do
    [[ -n "${p}" ]] && _set_phase_toggle "${p}" "true"
  done
fi

if [[ -n "${CLI_SKIP_PHASES}" ]]; then
  IFS=',' read -r -a skip_arr <<< "${CLI_SKIP_PHASES}"
  for p in "${skip_arr[@]}"; do
    [[ -n "${p}" ]] && _set_phase_toggle "${p}" "false"
  done
fi

if [[ -z "${ENTRA_TENANT_ID}" ]] && [[ "${ENABLE_PHASE_0B_GOOGLE_ADMIN}" == "true" || "${ENABLE_PHASE_0A_ENTRA_BOOTSTRAP}" == "true" ]]; then
  echo "ERROR: --entra-tenant-id <UUID> (or ENTRA_TENANT_ID in ${ONBOARD_CONFIG_FILE:-config}) is required."
  exit 1
fi

if [[ -z "${DNS_PROJECT_ID}" ]]; then
  DNS_PROJECT_ID="${GCP_PROJECT_ID}"
fi

TF_STATE_BUCKET="${CLI_TF_STATE_BUCKET:-${TF_STATE_BUCKET:-${CUSTOMER_NAME}-ge-tfstate}}"
M365_SECRET_ID="${CUSTOMER_NAME}-m365-connector-credentials"
DRY_RUN_FLAG=()
if [[ "${DRY_RUN}" == "true" ]]; then
  DRY_RUN_FLAG=(--dry-run)
fi

_phase_badge() {
  if [[ "$1" == "true" ]]; then
    printf "ENABLED"
  else
    printf "SKIPPED"
  fi
}

echo "=================================================================="
echo " Master End-to-End Customer Onboarding: ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})"
echo "------------------------------------------------------------------"
echo " Config File     : ${ONBOARD_CONFIG_FILE:-<CLI flags only>}"
echo " App GCP Project : ${GCP_PROJECT_ID} (${GCP_REGION})"
echo " DNS GCP Project : ${DNS_PROJECT_ID} (${DNS_ZONE_NAME:-<none>})"
echo " Dry-Run Mode    : ${DRY_RUN}"
echo "------------------------------------------------------------------"
echo " Phase Execution Matrix:"
echo "   [$(_phase_badge "${ENABLE_PHASE_0C_GCP_FOUNDATION}")] Phase 0C : GCP APIs & Terraform State Bucket (gs://${TF_STATE_BUCKET}) [--gcp-foundation]"
echo "   [$(_phase_badge "${ENABLE_PHASE_0B_GOOGLE_ADMIN}")] Phase 0B : Google Admin Console & Domain DNS Verification [--google-admin]"
echo "   [$(_phase_badge "${ENABLE_PHASE_0A_ENTRA_BOOTSTRAP}")] Phase 0A : Microsoft Entra ID OAuth + 49 Scopes + SAML App [--entra-bootstrap]"
echo "   [$(_phase_badge "${ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP}")] Phase 0D : ServiceNow Instance Bootstrap (User, Roles, OAuth 2.0 & Secret Sync) [--servicenow-bootstrap]"
echo "   [$(_phase_badge "${ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP}")] Phase 0E : Atlassian Cloud Bootstrap (Tenant Cloud ID, OAuth 2.0 & Secret Sync) [--atlassian-bootstrap]"
echo "   [$(_phase_badge "${ENABLE_PHASE_1A_DIRECTORY_SYNC}")] Phase 1A : GCP Directory Sync & GE UserStore License Sync [--directory-sync]"
echo "   [$(_phase_badge "${ENABLE_PHASE_1B_IDENTITY_TERRAFORM}")] Phase 1B : Cloud Identity Per-App Group Nesting & SAML SSO [--identity-terraform]"
echo "   [$(_phase_badge "${ENABLE_PHASE_1C_DEMO_CSV_SEED}")] Phase 1C : Optional Sandbox CSV Group Membership Seeding [--seed-demo-csv]"
echo "   [$(_phase_badge "${ENABLE_PHASE_2_M365_CONNECTORS}")] Phase 2  : Shared M365 Connectors (SharePoint, OneDrive, Outlook, Teams) [--m365-connectors]"
echo "   [$(_phase_badge "${ENABLE_PHASE_2B_SERVICENOW_CONNECTOR}")] Phase 2B : Shared ServiceNow Connector (KB, Incidents, Catalog Items & Actions) [--servicenow-connector]"
echo "   [$(_phase_badge "${ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS}")] Phase 2C : Shared Atlassian Connectors (Jira Cloud, Confluence Cloud & Actions) [--atlassian-connectors]"
echo "   [$(_phase_badge "${ENABLE_PHASE_3_GE_APPS}")] Phase 3  : Departmental Gemini Enterprise Apps (${PHASE_3_TARGET_APPS:-all 4 apps}) [--ge-apps]"
echo "   [$(_phase_badge "${ENABLE_PHASE_4_UNIVERSAL_AGENT}")] Phase 4  : Universal ADK Skill Orchestrator Deploy & Pin (DeployEngine=${PHASE_4_DEPLOY_REASONING_ENGINE}) [--universal-agent]"
echo "   [$(_phase_badge "${ENABLE_PHASE_5_SKILL_SHARING}")] Phase 5  : 6-Rubric Skill Benchmark, GCS Upload & Multi-App Sharing [--skill-sharing]"
echo "=================================================================="

# ------------------------------------------------------------------------------
# Phase 0C: GCP APIs & Remote Terraform State Bucket
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_0C_GCP_FOUNDATION}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 0C] Preparing GCP Project (${GCP_PROJECT_ID}) & State Bucket (gs://${TF_STATE_BUCKET})..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would enable Cloud Resource Manager, Service Usage, Discovery Engine, Cloud Identity, Admin SDK, Secret Manager, Vertex AI & Agent Registry APIs on '${GCP_PROJECT_ID}'"
    if [[ "${DNS_PROJECT_ID}" != "${GCP_PROJECT_ID}" || -n "${DNS_ZONE_NAME}" ]]; then
      echo "[DRY-RUN] Would enable Cloud DNS API (dns.googleapis.com) on DNS project '${DNS_PROJECT_ID}'"
    fi
    echo "[DRY-RUN] Would create versioned GCS bucket gs://${TF_STATE_BUCKET}"
  else
    gcloud services enable \
      cloudresourcemanager.googleapis.com \
      serviceusage.googleapis.com \
      discoveryengine.googleapis.com \
      cloudidentity.googleapis.com \
      admin.googleapis.com \
      siteverification.googleapis.com \
      secretmanager.googleapis.com \
      aiplatform.googleapis.com \
      agentregistry.googleapis.com \
      iam.googleapis.com \
      iamcredentials.googleapis.com \
      sts.googleapis.com \
      storage.googleapis.com \
      bigquery.googleapis.com \
      --project="${GCP_PROJECT_ID}"

    if [[ "${DNS_PROJECT_ID}" != "${GCP_PROJECT_ID}" || -n "${DNS_ZONE_NAME}" ]]; then
      echo ">>> [Phase 0C] Enabling Cloud DNS & Resource Manager APIs on DNS Project (${DNS_PROJECT_ID})..."
      gcloud services enable \
        cloudresourcemanager.googleapis.com \
        serviceusage.googleapis.com \
        dns.googleapis.com \
        --project="${DNS_PROJECT_ID}"
    fi

    gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || \
      gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
        --project="${GCP_PROJECT_ID}" \
        --location="${GCP_REGION}" \
        --uniform-bucket-level-access
    gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning
  fi
fi

# ------------------------------------------------------------------------------
# Phase 0B: Google Admin Console & Cloud Identity Bootstrap
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_0B_GOOGLE_ADMIN}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 0B] Running Google Admin & Cloud Identity Bootstrap..."
  "${SCRIPT_DIR}/deploy_google_admin_bootstrap.sh" \
    --customer-name "${CUSTOMER_NAME}" \
    --customer-domain "${CUSTOMER_DOMAIN}" \
    --gcp-project-id "${GCP_PROJECT_ID}" \
    --entra-tenant-id "${ENTRA_TENANT_ID}" \
    --dns-project-id "${DNS_PROJECT_ID}" \
    --dns-zone-name "${DNS_ZONE_NAME}" \
    --tf-state-bucket "${TF_STATE_BUCKET}" \
    ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
fi

# ------------------------------------------------------------------------------
# Phase 0A: Microsoft Entra ID Bootstrap (Step 0A.1 OAuth + Step 0A.2 SAML)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_0A_ENTRA_BOOTSTRAP}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 0A] Running Microsoft Entra ID OAuth & SAML Gallery Bootstrap..."
  "${SCRIPT_DIR}/deploy_entra_bootstrap.sh" \
    --tenant-id "${ENTRA_TENANT_ID}" \
    --customer-name "${CUSTOMER_NAME}" \
    --customer-domain "${CUSTOMER_DOMAIN}" \
    --gcp-project-id "${GCP_PROJECT_ID}" \
    --secret-id "${M365_SECRET_ID}" \
    --mode "${ENTRA_MODE}" \
    ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
fi

# ------------------------------------------------------------------------------
# Phase 0D: ServiceNow Instance Bootstrap (Integration User, Roles, OAuth 2.0, Secret Manager)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_0D_SERVICENOW_BOOTSTRAP}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 0D] Running ServiceNow Instance Bootstrap (deploy_servicenow_bootstrap.sh)..."
  SN_BOOTSTRAP_ARGS=(
    --instance-uri "${SERVICENOW_INSTANCE_URI:-https://dev123456.service-now.com}"
    --admin-user "${SERVICENOW_ADMIN_USER:-admin}"
    --customer-name "${CUSTOMER_NAME}"
    --customer-domain "${CUSTOMER_DOMAIN}"
    --gcp-project-id "${GCP_PROJECT_ID}"
    --gcp-region "${GCP_REGION}"
    --tf-state-bucket "${TF_STATE_BUCKET}"
  )
  if [[ -n "${SERVICENOW_ADMIN_PASSWORD:-}" ]]; then
    SN_BOOTSTRAP_ARGS+=(--admin-password "${SERVICENOW_ADMIN_PASSWORD}")
  fi
  "${SCRIPT_DIR}/deploy_servicenow_bootstrap.sh" \
    "${SN_BOOTSTRAP_ARGS[@]}" \
    ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
fi

# ------------------------------------------------------------------------------
# Phase 0E: Atlassian Cloud Bootstrap (Tenant Cloud ID, OAuth 2.0 3LO, Secret Manager)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_0E_ATLASSIAN_BOOTSTRAP}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 0E] Running Atlassian Cloud Bootstrap (deploy_atlassian_bootstrap.sh)..."
  AT_BOOTSTRAP_ARGS=(
    --instance-uri "${ATLASSIAN_INSTANCE_URI:-https://mohanrajs-team.atlassian.net}"
    --admin-email "${ATLASSIAN_ADMIN_EMAIL:-mohanraj@${CUSTOMER_DOMAIN}}"
    --customer-name "${CUSTOMER_NAME}"
    --customer-domain "${CUSTOMER_DOMAIN}"
    --gcp-project-id "${GCP_PROJECT_ID}"
    --gcp-region "${GCP_REGION}"
    --tf-state-bucket "${TF_STATE_BUCKET}"
  )
  [[ -n "${ATLASSIAN_INSTANCE_ID:-}" ]] && AT_BOOTSTRAP_ARGS+=(--instance-id "${ATLASSIAN_INSTANCE_ID}")
  [[ -n "${ATLASSIAN_CLIENT_ID:-}" ]] && AT_BOOTSTRAP_ARGS+=(--client-id "${ATLASSIAN_CLIENT_ID}")
  [[ -n "${ATLASSIAN_CLIENT_SECRET:-}" ]] && AT_BOOTSTRAP_ARGS+=(--client-secret "${ATLASSIAN_CLIENT_SECRET}")
  [[ -n "${ATLASSIAN_API_TOKEN:-}" ]] && AT_BOOTSTRAP_ARGS+=(--api-token "${ATLASSIAN_API_TOKEN}")
  "${SCRIPT_DIR}/deploy_atlassian_bootstrap.sh" \
    "${AT_BOOTSTRAP_ARGS[@]}" \
    ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
fi

# ------------------------------------------------------------------------------
# Phase 1A: Google Cloud Identity Directory Sync Configuration & License Sync
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_1A_DIRECTORY_SYNC}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 1A] Configuring & Validating GCP Directory Sync (deploy_gcp_directory_sync.sh)..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: ./deploy_gcp_directory_sync.sh --config configs/.generated/${CUSTOMER_NAME}-identity.env --manifest-out configs/.generated/${CUSTOMER_NAME}-gcp-directory-sync.json --dry-run"
  else
    "${SCRIPT_DIR}/deploy_gcp_directory_sync.sh" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env" \
      --manifest-out "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-gcp-directory-sync.json"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 1B: Cloud Identity Per-App Group Nesting & SAML Handshake (Terraform)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_1B_IDENTITY_TERRAFORM}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 1B] Running Stack 01: Cloud Identity Per-App Group Nesting & SAML Handshake..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: TF_WORKSPACE_OVERRIDE=id-${CUSTOMER_NAME}-com ./deploy_identity.sh --config configs/.generated/${CUSTOMER_NAME}-identity.env --sync-mode GCP_DIRECTORY_SYNC --dns-project-id ${DNS_PROJECT_ID}"
  else
    TF_WORKSPACE_OVERRIDE="id-${CUSTOMER_NAME}-com" "${SCRIPT_DIR}/deploy_identity.sh" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env" \
      --sync-mode "GCP_DIRECTORY_SYNC" \
      --dns-project-id "${DNS_PROJECT_ID}"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 1C: Optional Sandbox CSV Group Membership Seeding
# ------------------------------------------------------------------------------
RESOLVED_MEMBERS_CSV="${MEMBERS_CSV:-${CONFIGS_DIR}/${CUSTOMER_NAME}-group-memberships.csv}"
if [[ "${ENABLE_PHASE_1C_DEMO_CSV_SEED}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 1C] Seeding Sandbox Group Memberships from ${RESOLVED_MEMBERS_CSV}..."
  if [[ -f "${RESOLVED_MEMBERS_CSV}" ]]; then
    "${SCRIPT_DIR}/sync_group_members_from_csv.sh" \
      --csv "${RESOLVED_MEMBERS_CSV}" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env" \
      ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
  elif [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: ./sync_group_members_from_csv.sh --csv ${RESOLVED_MEMBERS_CSV} --config configs/.generated/${CUSTOMER_NAME}-identity.env --dry-run"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 2: Shared M365 Connectors (SharePoint, OneDrive, Outlook, Teams)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_2_M365_CONNECTORS}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 2] Running Stack 03: Shared M365 Connectors (${CUSTOMER_NAME}-m365-sp/od/ol/teams)..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would generate configs/.generated/${CUSTOMER_NAME}-m365.env and run: TF_WORKSPACE_OVERRIDE=m365-global-${CUSTOMER_NAME}-m365 ./deploy_m365.sh"
  else
    SP_TENANT_PREFIX="${CUSTOMER_NAME}"
    if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
      INIT_DOM="$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/domains" --query "value[?isInitial].id | [0]" -o tsv 2>/dev/null || true)"
      if [[ -n "${INIT_DOM}" && "${INIT_DOM}" == *.onmicrosoft.com ]]; then
        SP_TENANT_PREFIX="${INIT_DOM%.onmicrosoft.com}"
      fi
    fi
    cat > "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-m365.env" <<EOF
GCP_PROJECT_ID="${GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION}"
GE_LOCATION="global"
TF_STATE_BUCKET="${TF_STATE_BUCKET}"
TF_STATE_PREFIX="ge-apphub/03-m365-connectors/m365-global-${CUSTOMER_NAME}-m365"
M365_COLLECTION_PREFIX="${CUSTOMER_NAME}-m365"
M365_SECRET_ID="${M365_SECRET_ID}"
M365_CONNECTOR_MODE="FEDERATED"
ENABLE_M365_ACTIONS="true"
ENABLE_SHAREPOINT_CONNECTOR="true"
M365_SHAREPOINT_COLLECTION_ID="${CUSTOMER_NAME}-m365-sp"
M365_SHAREPOINT_INSTANCE_URI="https://${SP_TENANT_PREFIX}.sharepoint.com"
M365_SHAREPOINT_ENTITIES="file,page"
ENABLE_ONEDRIVE_CONNECTOR="true"
M365_ONEDRIVE_COLLECTION_ID="${CUSTOMER_NAME}-m365-od"
M365_ONEDRIVE_INSTANCE_URI="https://${SP_TENANT_PREFIX}-my.sharepoint.com"
M365_ONEDRIVE_ENTITIES="file"
ENABLE_OUTLOOK_CONNECTOR="true"
M365_OUTLOOK_COLLECTION_ID="${CUSTOMER_NAME}-m365-ol"
M365_OUTLOOK_INSTANCE_URI="https://outlook.office365.com"
M365_OUTLOOK_ENTITIES="mail,mail-attachment,calendar,contact"
ENABLE_TEAMS_CONNECTOR="true"
M365_TEAMS_COLLECTION_ID="${CUSTOMER_NAME}-m365-teams"
M365_TEAMS_INSTANCE_URI="https://teams.microsoft.com"
M365_TEAMS_ENTITIES="channel-message,chat-message"
EOF
    TF_WORKSPACE_OVERRIDE="m365-global-${CUSTOMER_NAME}-m365" "${SCRIPT_DIR}/deploy_m365.sh" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-m365.env"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 2B: Shared ServiceNow Connector (Knowledge Base, Incidents, Catalog Items & Actions)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_2B_SERVICENOW_CONNECTOR}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 2B] Running Stack 03B: Shared ServiceNow Connector (${CUSTOMER_NAME}-servicenow)..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: TF_WORKSPACE_OVERRIDE=sn-global-${CUSTOMER_NAME}-servicenow ./deploy_servicenow.sh --config configs/.generated/${CUSTOMER_NAME}-servicenow.env --dry-run"
  else
    TF_WORKSPACE_OVERRIDE="sn-global-${CUSTOMER_NAME}-servicenow" "${SCRIPT_DIR}/deploy_servicenow.sh" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-servicenow.env"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 2C: Shared Atlassian Jira Cloud & Confluence Cloud Connectors & Actions
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 2C] Running Stack 03C: Shared Atlassian Jira & Confluence Connectors (${CUSTOMER_NAME}-jira-fed / ${CUSTOMER_NAME}-confluence-fed)..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: TF_WORKSPACE_OVERRIDE=atlassian-global-${CUSTOMER_NAME}-jira-fed ./deploy_atlassian.sh --config configs/.generated/${CUSTOMER_NAME}-atlassian.env --dry-run"
  else
    TF_WORKSPACE_OVERRIDE="atlassian-global-${CUSTOMER_NAME}-jira-fed" "${SCRIPT_DIR}/deploy_atlassian.sh" \
      --config "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-atlassian.env"
  fi
fi

# ------------------------------------------------------------------------------
# Phase 3: Departmental Gemini Enterprise Apps (16-Point Master Template)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_3_GE_APPS}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 3] Running Stack 02: Departmental Gemini Enterprise Apps (create_app_from_template.sh)..."
  for SPEC in \
    "${CUSTOMER_NAME}-dev-sandbox-app|${CUSTOMER_NAME} AI Skill Dev Sandbox|ge-skill-developers@${CUSTOMER_DOMAIN}" \
    "${CUSTOMER_NAME}-service-desk-app|${CUSTOMER_NAME} Service Desk Assistant|ge-service-desk-users@${CUSTOMER_DOMAIN}" \
    "${CUSTOMER_NAME}-finance-app|${CUSTOMER_NAME} Finance & Accounting Assistant|ge-finance-users@${CUSTOMER_DOMAIN}" \
    "${CUSTOMER_NAME}-hr-app|${CUSTOMER_NAME} People & HR Assistant|ge-hr-users@${CUSTOMER_DOMAIN}"; do
    IFS="|" read -r APP_ID APP_NAME ACCESS_GROUP <<< "${SPEC}"
    if [[ -n "${PHASE_3_TARGET_APPS:-}" ]] && [[ ",${PHASE_3_TARGET_APPS}," != *",${APP_ID},"* ]]; then
      echo "    [SKIP] Skipping App '${APP_ID}' (not in PHASE_3_TARGET_APPS='${PHASE_3_TARGET_APPS}')"
      continue
    fi
    WORKSPACE_KEY="app-global-${APP_ID}"
    EXTRA_APP_FLAGS=()
    if [[ "${ENABLE_PHASE_2B_SERVICENOW_CONNECTOR}" == "true" || -f "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-servicenow.env" ]]; then
      if [[ "${APP_ID}" == "${CUSTOMER_NAME}-service-desk-app" || "${APP_ID}" == "${CUSTOMER_NAME}-dev-sandbox-app" ]]; then
        EXTRA_APP_FLAGS+=(--include-servicenow)
      fi
    fi
    if [[ "${ENABLE_PHASE_2C_ATLASSIAN_CONNECTORS}" == "true" || -f "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-atlassian.env" ]]; then
      if [[ "${APP_ID}" == "${CUSTOMER_NAME}-service-desk-app" || "${APP_ID}" == "${CUSTOMER_NAME}-dev-sandbox-app" ]]; then
        EXTRA_APP_FLAGS+=(--include-atlassian)
      fi
    fi
    if [[ "${DRY_RUN}" == "true" ]]; then
      "${SCRIPT_DIR}/create_app_from_template.sh" \
        --app-id "${APP_ID}" \
        --app-display-name "${APP_NAME}" \
        --customer-name "${CUSTOMER_NAME}" \
        --customer-company-name "${CUSTOMER_NAME}" \
        --customer-domain "${CUSTOMER_DOMAIN}" \
        --gcp-project-id "${GCP_PROJECT_ID}" \
        --access-group "${ACCESS_GROUP}" \
        ${EXTRA_APP_FLAGS[@]+"${EXTRA_APP_FLAGS[@]}"} \
        --render-only
      echo "[DRY-RUN] Rendered 16-Point Template configs/.generated/${APP_ID}.env and would provision in isolated workspace '${WORKSPACE_KEY}'"
    else
      "${SCRIPT_DIR}/create_app_from_template.sh" \
        --app-id "${APP_ID}" \
        --app-display-name "${APP_NAME}" \
        --customer-name "${CUSTOMER_NAME}" \
        --customer-company-name "${CUSTOMER_NAME}" \
        --customer-domain "${CUSTOMER_DOMAIN}" \
        --gcp-project-id "${GCP_PROJECT_ID}" \
        --access-group "${ACCESS_GROUP}" \
        ${EXTRA_APP_FLAGS[@]+"${EXTRA_APP_FLAGS[@]}"}
    fi
  done
fi

# ------------------------------------------------------------------------------
# Phase 4: Universal ADK Skill Orchestrator Deploy & Pin (agents-cli + publish_universal_agent.sh)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_4_UNIVERSAL_AGENT}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 4] Deploying & Pinning Universal ADK Skill Orchestrator across ${CUSTOMER_NAME} GE Apps..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    if [[ "${PHASE_4_DEPLOY_REASONING_ENGINE:-true}" == "true" ]]; then
      echo "[DRY-RUN] Would run 'agents-cli deploy --project ${GCP_PROJECT_ID} --region ${GCP_REGION}' in agents/universal_skill_orchestrator"
    else
      echo "[DRY-RUN] Skipping 'agents-cli deploy' (PHASE_4_DEPLOY_REASONING_ENGINE=false); would only register/pin existing ReasoningEngine."
    fi
    "${SCRIPT_DIR}/publish_universal_agent.sh" \
      --gcp-project-id "${GCP_PROJECT_ID}" \
      --region "${GCP_REGION}" \
      --all-apps \
      --dry-run
  else
    if [[ "${PHASE_4_DEPLOY_REASONING_ENGINE:-true}" == "true" ]]; then
      (
        cd "${REPO_ROOT}/agents/universal_skill_orchestrator"
        agents-cli deploy --project "${GCP_PROJECT_ID}" --region "${GCP_REGION}" --no-wait
      )
    fi
    "${SCRIPT_DIR}/publish_universal_agent.sh" \
      --gcp-project-id "${GCP_PROJECT_ID}" \
      --region "${GCP_REGION}" \
      --all-apps
  fi
fi

# ------------------------------------------------------------------------------
# Phase 5: 6-Rubric Benchmark Gate, GCS Upload & Multi-App Skill Sharing (publish_m365_skills.sh)
# ------------------------------------------------------------------------------
if [[ "${ENABLE_PHASE_5_SKILL_SHARING}" == "true" ]]; then
  echo ""
  echo ">>> [Phase 5] Running 6-Rubric Skill Benchmark Gate, GCS Catalog Sync & Multi-App Skill Sharing..."
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would run: ./publish_m365_skills.sh --env configs/.generated/${CUSTOMER_NAME}-identity.env"
  else
    "${SCRIPT_DIR}/publish_m365_skills.sh" \
      --env "${GENERATED_CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env"
  fi
fi

echo ""
echo "=================================================================="
echo " End-to-End Onboarding Complete for ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})!"
echo "=================================================================="
