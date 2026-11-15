#!/usr/bin/env bash
# ==============================================================================
# Atlassian Jira Cloud & Confluence Cloud — Master Entrypoint (Phase 2C)
# ==============================================================================
# Provisions, updates, verifies, or destroys the shared Atlassian Jira Cloud
# (`<customer>-jira-fed`) and Confluence Cloud (`<customer>-confluence-fed`)
# Data Connectors in Discovery Engine via Terraform (`terraform-atlassian/`)
# and REST API (`configure_atlassian_connectors.sh`).
#
# Usage:
#   ./deploy_atlassian.sh --config ./configs/cymbal-atlassian.env
# ==============================================================================

set -euo pipefail

DEPLOY_AT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="${DEPLOY_AT_ROOT}"
export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

# shellcheck source=scripts/lib/common.sh
source "${DEPLOY_AT_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${DEPLOY_AT_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/preflight.sh
source "${DEPLOY_AT_ROOT}/scripts/preflight.sh"
# shellcheck source=scripts/configure_atlassian_connectors.sh
source "${DEPLOY_AT_ROOT}/scripts/configure_atlassian_connectors.sh"

print_atlassian_usage() {
  cat <<'EOF'
Usage: ./deploy_atlassian.sh [OPTIONS]

Master orchestrator for the Gemini Enterprise Atlassian Jira Cloud & Confluence Cloud Connectors (Phase 2C).

Options:
  --config <path>          Path to Atlassian config file (default: ./configs/cymbal-atlassian.env)
  --dry-run                Validate config and run 'terraform plan' without mutating state
  --terraform-only         Execute only Pre-Flight and Terraform provisioning phases
  --curl-only              Execute only Pre-Flight and REST API provisioning phases
  --verify-only            Execute only Pre-Flight and Verification phases
  --destroy                Destroy the Jira Cloud and Confluence Cloud Data Connector collections
  --help, -h               Show this help message and exit
EOF
}

import_existing_atlassian_resources() {
  local tf_dir="$1"
  if [[ "${DRY_RUN:-false}" == "true" || -z "${GCP_PROJECT_ID:-}" ]]; then
    return 0
  fi

  log_info "Reconciling existing Secret Manager & Atlassian Data Connector resources into Terraform state..."
  local state_list
  state_list="$(terraform -chdir="${tf_dir}" state list 2>/dev/null || true)"

  local secret_id="${ATLASSIAN_SECRET_ID:-cymbal-atlassian-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"

  if ! grep -qF "google_secret_manager_secret.atlassian_credentials" <<<"${state_list}"; then
    local sec_resp sec_name
    sec_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}" "" "true" || echo '{}')"
    sec_name="$(jq -r '.name // empty' <<<"${sec_resp}" 2>/dev/null || true)"
    if [[ -n "${sec_name}" ]]; then
      log_info "Importing existing Secret Manager secret '${secret_id}' -> google_secret_manager_secret.atlassian_credentials"
      terraform -chdir="${tf_dir}" import -input=false "google_secret_manager_secret.atlassian_credentials" "projects/${GCP_PROJECT_ID}/secrets/${secret_id}" >/dev/null 2>&1 || true
    fi
  fi

  if ! grep -qF "google_secret_manager_secret_version.atlassian_credentials_initial" <<<"${state_list}"; then
    local ver_meta ver_name
    ver_meta="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest" "" "true" || echo '{}')"
    ver_name="$(jq -r '.name // empty' <<<"${ver_meta}" 2>/dev/null || true)"
    if [[ -n "${ver_name}" ]]; then
      log_info "Importing existing Secret Manager secret version '${ver_name}' -> google_secret_manager_secret_version.atlassian_credentials_initial"
      terraform -chdir="${tf_dir}" import -input=false "google_secret_manager_secret_version.atlassian_credentials_initial" "${ver_name}" >/dev/null 2>&1 || true
    fi
  fi

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  if [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]] && ! grep -qF "google_discovery_engine_data_connector.jira" <<<"${state_list}"; then
    local conn_resp conn_name
    conn_resp="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${JIRA_COLLECTION_ID}/dataConnector" "" "true" || echo '{}')"
    conn_name="$(jq -r '.name // empty' <<<"${conn_resp}" 2>/dev/null || true)"
    if [[ -n "${conn_name}" ]]; then
      log_info "Importing existing Jira Cloud connector '${JIRA_COLLECTION_ID}' -> google_discovery_engine_data_connector.jira[0]"
      terraform -chdir="${tf_dir}" import -input=false "google_discovery_engine_data_connector.jira[0]" "${loc_parent}/collections/${JIRA_COLLECTION_ID}/dataConnector" >/dev/null 2>&1 || true
    fi
  fi

  if [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]] && ! grep -qF "google_discovery_engine_data_connector.confluence" <<<"${state_list}"; then
    local conn_resp conn_name
    conn_resp="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${CONFLUENCE_COLLECTION_ID}/dataConnector" "" "true" || echo '{}')"
    conn_name="$(jq -r '.name // empty' <<<"${conn_resp}" 2>/dev/null || true)"
    if [[ -n "${conn_name}" ]]; then
      log_info "Importing existing Confluence Cloud connector '${CONFLUENCE_COLLECTION_ID}' -> google_discovery_engine_data_connector.confluence[0]"
      terraform -chdir="${tf_dir}" import -input=false "google_discovery_engine_data_connector.confluence[0]" "${loc_parent}/collections/${CONFLUENCE_COLLECTION_ID}/dataConnector" >/dev/null 2>&1 || true
    fi
  fi
}

run_atlassian_terraform_phase() {
  local action="${1:-apply}"
  local tf_dir="${TF_AT_DIR_OVERRIDE:-${DEPLOY_AT_ROOT}/terraform-atlassian}"
  local workspace="${TF_WORKSPACE_OVERRIDE:-atlassian-global-${JIRA_COLLECTION_ID}}"
  log_phase "TERRAFORM-ATLASSIAN" "Executing Terraform workflow (${action}) in ${tf_dir}"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token --quiet 2>/dev/null || gcloud auth print-access-token --quiet)"
  fi

  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    cat > "${tf_dir}/backend_override.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "${TF_STATE_PREFIX:-ge-apphub/03c-atlassian-connectors/${workspace}}"
  }
}
EOF
  else
    rm -f "${tf_dir}/backend_override.tf"
  fi

  rm -f "${tf_dir}/.terraform/environment"
  terraform -chdir="${tf_dir}" init -reconfigure -input=false >/dev/null
  terraform -chdir="${tf_dir}" workspace select -or-create "${workspace}" >/dev/null
  terraform -chdir="${tf_dir}" validate >/dev/null

  if [[ "${action}" != "destroy" ]]; then
    import_existing_atlassian_resources "${tf_dir}"
  fi

  if [[ "${action}" == "destroy" ]]; then
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      terraform -chdir="${tf_dir}" destroy -auto-approve -input=false >/dev/null
    fi
    rm -f "${tf_dir}/backend_override.tf"
    log_ok "Atlassian Terraform destroy phase complete."
    return 0
  fi

  terraform -chdir="${tf_dir}" plan -out=tfplan -input=false >/dev/null
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    terraform -chdir="${tf_dir}" apply -auto-approve -input=false tfplan >/dev/null
  fi
  rm -f "${tf_dir}/backend_override.tf"
  log_ok "Atlassian Terraform phase complete."
}

deploy_atlassian_main() {
  local config_file="${DEPLOY_AT_ROOT}/configs/.generated/cymbal-atlassian.env"
  export DRY_RUN="false"
  local mode="full"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --dry-run)
        export DRY_RUN="true"
        shift
        ;;
      --terraform-only)
        mode="terraform-only"
        shift
        ;;
      --curl-only)
        mode="curl-only"
        shift
        ;;
      --verify-only)
        mode="verify-only"
        shift
        ;;
      --destroy)
        mode="destroy"
        shift
        ;;
      --help|-h)
        print_atlassian_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_atlassian_usage
        return 1
        ;;
    esac
  done

  init_logging "${DEPLOY_AT_ROOT}/logs"
  load_atlassian_config "${config_file}"
  check_cli_dependencies
  validate_atlassian_config
  check_gcloud_auth

  case "${mode}" in
    terraform-only)
      run_atlassian_terraform_phase "apply"
      ;;
    curl-only)
      configure_atlassian_connectors "true"
      run_atlassian_verification_and_summary
      ;;
    verify-only)
      run_atlassian_verification_and_summary
      ;;
    destroy)
      deregister_atlassian_connectors
      run_atlassian_terraform_phase "destroy"
      ;;
    full)
      run_atlassian_terraform_phase "apply"
      configure_atlassian_connectors "false"
      run_atlassian_verification_and_summary
      ;;
  esac

  log_ok "Atlassian Jira Cloud & Confluence Cloud workflow ('${mode}') completed successfully."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_atlassian_main "$@"
fi
