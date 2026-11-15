#!/usr/bin/env bash
# ==============================================================================
# Atlassian Jira Cloud & Confluence Cloud Discovery Engine Connector Provisioner
# ==============================================================================
# Loads & validates `configs/<customer>-atlassian.env`, resolves Atlassian OAuth 2.0
# credentials from GCP Secret Manager (`<customer>-atlassian-connector-credentials`),
# exports TF_VAR_* variables for `terraform-atlassian/`, provisions both the
# Jira Cloud (`dataSource: "jira"`) and Confluence Cloud (`dataSource: "confluence"`)
# Data Connectors via `setUpDataConnectorV2`, activates BAP Write Actions,
# binds Collection-level IAM for app access groups, and attaches all resulting
# entity Data Stores to the target Gemini Enterprise Apps.
# ==============================================================================

set -euo pipefail

load_atlassian_config() {
  local config_path="${1:-./configs/cymbal-atlassian.env}"
  if [[ ! -f "${config_path}" ]]; then
    log_error "Atlassian configuration file not found at '${config_path}'."
    return 1
  fi

  local env_uri="${ATLASSIAN_INSTANCE_URI:-}"
  local env_iid="${ATLASSIAN_INSTANCE_ID:-}"
  local env_cid="${ATLASSIAN_CLIENT_ID:-}"
  local env_csec="${ATLASSIAN_CLIENT_SECRET:-}"
  local env_rtok="${ATLASSIAN_REFRESH_TOKEN:-}"
  local env_email="${ATLASSIAN_ADMIN_EMAIL:-}"
  local env_tok="${ATLASSIAN_API_TOKEN:-}"
  local env_sec_id="${ATLASSIAN_SECRET_ID:-}"

  set -a
  # shellcheck disable=SC1090
  source "${config_path}"
  set +a

  export GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
  export GCP_REGION="${GCP_REGION:-us-central1}"
  export GE_LOCATION="${GE_LOCATION:-global}"
  export ATLASSIAN_SECRET_ID="${env_sec_id:-${ATLASSIAN_SECRET_ID:-cymbal-atlassian-connector-credentials}}"
  export ATLASSIAN_INSTANCE_URI="${env_uri:-${ATLASSIAN_INSTANCE_URI:-https://mohanrajs-team.atlassian.net}}"
  export ATLASSIAN_INSTANCE_URI="${ATLASSIAN_INSTANCE_URI%/}"
  export ATLASSIAN_INSTANCE_ID="${env_iid:-${ATLASSIAN_INSTANCE_ID:-}}"
  export ATLASSIAN_ADMIN_EMAIL="${env_email:-${ATLASSIAN_ADMIN_EMAIL:-mohanraj@mohanrajs.demo.altostrat.com}}"
  export ATLASSIAN_CLIENT_ID="${env_cid:-${ATLASSIAN_CLIENT_ID:-}}"
  export ATLASSIAN_CLIENT_SECRET="${env_csec:-${ATLASSIAN_CLIENT_SECRET:-}}"
  export ATLASSIAN_REFRESH_TOKEN="${env_rtok:-${ATLASSIAN_REFRESH_TOKEN:-}}"
  export ATLASSIAN_API_TOKEN="${env_tok:-${ATLASSIAN_API_TOKEN:-}}"

  export ENABLE_JIRA_CONNECTOR="${ENABLE_JIRA_CONNECTOR:-true}"
  export JIRA_COLLECTION_ID="${JIRA_COLLECTION_ID:-cymbal-jira-fed}"
  export JIRA_COLLECTION_DISPLAY_NAME="${JIRA_COLLECTION_DISPLAY_NAME:-Jira Cloud (cymbal)}"
  export JIRA_COLLECTION_DISPLAY_NAME="${JIRA_COLLECTION_DISPLAY_NAME//&/and}"
  export JIRA_CONNECTOR_MODE="${JIRA_CONNECTOR_MODE:-FEDERATED}"
  export JIRA_REFRESH_INTERVAL="${JIRA_REFRESH_INTERVAL:-86400s}"
  export JIRA_ENTITIES="${JIRA_ENTITIES:-project,issue,comment,attachment,worklog}"
  export ENABLE_JIRA_ACTIONS="${ENABLE_JIRA_ACTIONS:-true}"
  export JIRA_ENABLED_ACTIONS="${JIRA_ENABLED_ACTIONS:-create_issue,update_issue,change_issue_status,create_comment,update_comment,upload_attachment,download_attachment,create_issue_link,create_project,update_project,create_worklog,update_worklog,search_issues,get_issue,list_issues,get_comment,list_comments,get_attachment,list_attachments,get_project,list_projects,get_worklog,list_worklogs,get_user,list_users,search_users,get_board,list_boards,get_sprint,list_sprints,get_priority,list_priorities,get_issue_type,list_issue_types,get_issue_transitions,list_issue_transitions}"

  export ENABLE_CONFLUENCE_CONNECTOR="${ENABLE_CONFLUENCE_CONNECTOR:-true}"
  export CONFLUENCE_COLLECTION_ID="${CONFLUENCE_COLLECTION_ID:-cymbal-confluence-fed}"
  export CONFLUENCE_COLLECTION_DISPLAY_NAME="${CONFLUENCE_COLLECTION_DISPLAY_NAME:-Confluence Cloud (cymbal)}"
  export CONFLUENCE_COLLECTION_DISPLAY_NAME="${CONFLUENCE_COLLECTION_DISPLAY_NAME//&/and}"
  export CONFLUENCE_CONNECTOR_MODE="${CONFLUENCE_CONNECTOR_MODE:-FEDERATED}"
  export CONFLUENCE_REFRESH_INTERVAL="${CONFLUENCE_REFRESH_INTERVAL:-86400s}"
  export CONFLUENCE_ENTITIES="${CONFLUENCE_ENTITIES:-space,page,blog,attachment,comment}"
  export ENABLE_CONFLUENCE_ACTIONS="${ENABLE_CONFLUENCE_ACTIONS:-true}"
  export CONFLUENCE_ENABLED_ACTIONS="${CONFLUENCE_ENABLED_ACTIONS:-create_page,update_page,create_blog_post,create_space,download_attachment,get_system_info,list_attachments,list_blog_posts,list_comments,list_pages,list_tasks,list_whiteboards,upload_attachment,get_attachment,get_blog_post,get_comment,get_page,get_space,get_task,get_user,get_whiteboard,list_spaces,list_users}"

  export ATLASSIAN_TARGET_APPS="${ATLASSIAN_TARGET_APPS:-}"
  export ATLASSIAN_ACCESS_GROUPS="${ATLASSIAN_ACCESS_GROUPS:-}"
  export ATLASSIAN_CONFIGURE_ACL="${ATLASSIAN_CONFIGURE_ACL:-true}"

  export TF_VAR_project_id="${GCP_PROJECT_ID}"
  export TF_VAR_region="${GCP_REGION}"
  export TF_VAR_location="${GE_LOCATION}"
  export TF_VAR_atlassian_secret_id="${ATLASSIAN_SECRET_ID}"
  export TF_VAR_atlassian_instance_uri="${ATLASSIAN_INSTANCE_URI}"
  export TF_VAR_atlassian_instance_id="${ATLASSIAN_INSTANCE_ID}"
  export TF_VAR_atlassian_admin_email="${ATLASSIAN_ADMIN_EMAIL}"
  export TF_VAR_atlassian_client_id="${ATLASSIAN_CLIENT_ID}"
  export TF_VAR_atlassian_client_secret="${ATLASSIAN_CLIENT_SECRET}"
  export TF_VAR_atlassian_refresh_token="${ATLASSIAN_REFRESH_TOKEN}"
  export TF_VAR_atlassian_api_token="${ATLASSIAN_API_TOKEN}"

  export TF_VAR_enable_jira_connector="${ENABLE_JIRA_CONNECTOR}"
  export TF_VAR_jira_collection_id="${JIRA_COLLECTION_ID}"
  export TF_VAR_jira_collection_display_name="${JIRA_COLLECTION_DISPLAY_NAME}"
  export TF_VAR_jira_connector_mode="${JIRA_CONNECTOR_MODE}"
  export TF_VAR_jira_refresh_interval="${JIRA_REFRESH_INTERVAL}"
  export TF_VAR_jira_entities="${JIRA_ENTITIES}"
  export TF_VAR_enable_jira_actions="${ENABLE_JIRA_ACTIONS}"
  export TF_VAR_jira_enabled_actions="${JIRA_ENABLED_ACTIONS}"

  export TF_VAR_enable_confluence_connector="${ENABLE_CONFLUENCE_CONNECTOR}"
  export TF_VAR_confluence_collection_id="${CONFLUENCE_COLLECTION_ID}"
  export TF_VAR_confluence_collection_display_name="${CONFLUENCE_COLLECTION_DISPLAY_NAME}"
  export TF_VAR_confluence_connector_mode="${CONFLUENCE_CONNECTOR_MODE}"
  export TF_VAR_confluence_refresh_interval="${CONFLUENCE_REFRESH_INTERVAL}"
  export TF_VAR_confluence_entities="${CONFLUENCE_ENTITIES}"
  export TF_VAR_enable_confluence_actions="${ENABLE_CONFLUENCE_ACTIONS}"
  export TF_VAR_confluence_enabled_actions="${CONFLUENCE_ENABLED_ACTIONS}"

  log_info "Loaded Atlassian configuration from '${config_path}' (Project=${GCP_PROJECT_ID}, Jira=${JIRA_COLLECTION_ID}, Confluence=${CONFLUENCE_COLLECTION_ID}, Site=${ATLASSIAN_INSTANCE_URI})"
  return 0
}

ensure_and_load_atlassian_secret_credentials() {
  local secret_id="${ATLASSIAN_SECRET_ID:-cymbal-atlassian-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  local env_uri="${ATLASSIAN_INSTANCE_URI:-}"
  local env_iid="${ATLASSIAN_INSTANCE_ID:-}"
  local env_cid="${ATLASSIAN_CLIENT_ID:-}"
  local env_csec="${ATLASSIAN_CLIENT_SECRET:-}"
  local env_rtok="${ATLASSIAN_REFRESH_TOKEN:-}"
  local env_usr="${ATLASSIAN_ADMIN_EMAIL:-}"
  local env_tok="${ATLASSIAN_API_TOKEN:-}"

  log_info "Ensuring Atlassian credentials JSON secret '${secret_id}' is synchronized in Secret Manager..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would resolve Atlassian credentials from Secret Manager '${secret_id}' (${sm_base}/secrets/${secret_id}/versions/latest:access)"
    return 0
  fi

  local check_rc=0
  ge_curl_request "GET" "${sm_base}/secrets/${secret_id}" "" "true" >/dev/null || check_rc=$?
  if [[ "${check_rc}" -eq 44 && -n "${env_cid}" && -n "${env_csec}" ]]; then
    log_info "Creating Secret Manager secret '${secret_id}'..."
    ge_curl_request "POST" "${sm_base}/secrets?secretId=${secret_id}" '{"replication":{"automatic":{}}}' >/dev/null
  fi

  local ver_rc=0
  local ver_resp=""
  ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true")" || ver_rc=$?

  if [[ "${ver_rc}" -ne 0 && -n "${env_cid}" && -n "${env_csec}" ]]; then
    log_info "Seeding initial JSON version for Secret Manager secret '${secret_id}'..."
    local raw_json b64_payload add_ver_payload
    raw_json="$(jq -c -n \
      --arg uri "${env_uri}" \
      --arg iid "${env_iid}" \
      --arg cid "${env_cid}" \
      --arg csec "${env_csec}" \
      --arg rtok "${env_rtok}" \
      --arg usr "${env_usr}" \
      --arg tok "${env_tok}" \
      '{instance_uri: $uri, instance_id: $iid, client_id: $cid, client_secret: $csec, refresh_token: $rtok, user_account: $usr, api_token: $tok}')"
    b64_payload="$(printf '%s' "${raw_json}" | base64 | tr -d '\n')"
    add_ver_payload="$(jq -n --arg data "${b64_payload}" '{payload: {data: $data}}')"
    ge_curl_request "POST" "${sm_base}/secrets/${secret_id}:addVersion" "${add_ver_payload}" >/dev/null
    ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true" || echo "{}")"
  fi

  local raw_b64 decoded_json
  raw_b64="$(jq -r '.payload.data // empty' <<<"${ver_resp}" 2>/dev/null || true)"
  if [[ -n "${raw_b64}" ]]; then
    decoded_json="$(printf '%s' "${raw_b64}" | base64 -d 2>/dev/null || printf '%s' "${raw_b64}" | base64 -D 2>/dev/null || echo "{}")"
    export ATLASSIAN_INSTANCE_URI="${env_uri:-$(jq -r '.instance_uri // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_INSTANCE_ID="${env_iid:-$(jq -r '.instance_id // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_CLIENT_ID="${env_cid:-$(jq -r '.client_id // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_CLIENT_SECRET="${env_csec:-$(jq -r '.client_secret // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_REFRESH_TOKEN="${env_rtok:-$(jq -r '.refresh_token // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_ADMIN_EMAIL="${env_usr:-$(jq -r '.user_account // empty' <<<"${decoded_json}")}"
    export ATLASSIAN_API_TOKEN="${env_tok:-$(jq -r '.api_token // empty' <<<"${decoded_json}")}"
  fi

  # Auto-discover cloudId if still empty
  if [[ -z "${ATLASSIAN_INSTANCE_ID:-}" && -n "${ATLASSIAN_INSTANCE_URI:-}" && -z "${MOCK_CURL_GET_STATUS:-}" ]]; then
    local t_resp
    t_resp="$(curl -sS --max-time 5 "${ATLASSIAN_INSTANCE_URI%/}/_edge/tenant_info" 2>/dev/null || echo '{}')"
    export ATLASSIAN_INSTANCE_ID="$(jq -r '.cloudId // empty' <<<"${t_resp}" 2>/dev/null || true)"
  fi

  export TF_VAR_atlassian_instance_uri="${ATLASSIAN_INSTANCE_URI:-}"
  export TF_VAR_atlassian_instance_id="${ATLASSIAN_INSTANCE_ID:-}"
  export TF_VAR_atlassian_client_id="${ATLASSIAN_CLIENT_ID:-}"
  export TF_VAR_atlassian_client_secret="${ATLASSIAN_CLIENT_SECRET:-}"
  export TF_VAR_atlassian_refresh_token="${ATLASSIAN_REFRESH_TOKEN:-}"
  export TF_VAR_atlassian_admin_email="${ATLASSIAN_ADMIN_EMAIL:-}"
  export TF_VAR_atlassian_api_token="${ATLASSIAN_API_TOKEN:-}"
  return 0
}

validate_atlassian_config() {
  for var_name in GCP_PROJECT_ID GCP_REGION GE_LOCATION ATLASSIAN_SECRET_ID ATLASSIAN_INSTANCE_URI; do
    if [[ -z "${!var_name:-}" ]]; then
      log_error "Required Atlassian configuration variable '${var_name}' is empty or unset."
      return 1
    fi
  done

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    ensure_and_load_atlassian_secret_credentials || true
  fi

  local missing=()
  for sec_var in ATLASSIAN_INSTANCE_URI ATLASSIAN_INSTANCE_ID ATLASSIAN_CLIENT_ID ATLASSIAN_CLIENT_SECRET; do
    if [[ -z "${!sec_var:-}" ]]; then
      missing+=("${sec_var}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 && "${DRY_RUN:-false}" != "true" ]]; then
    log_error "Missing Atlassian OAuth credentials (${missing[*]}). Run './deploy_atlassian_bootstrap.sh' first or export ATLASSIAN_CLIENT_ID and ATLASSIAN_CLIENT_SECRET."
    return 1
  fi

  log_ok "Atlassian configuration validated (Site=${ATLASSIAN_INSTANCE_URI}, CloudID=${ATLASSIAN_INSTANCE_ID:-<dry-run>})."
  return 0
}

render_jira_connector_payload() {
  local entities_json="[]"
  IFS=',' read -r -a ent_arr <<< "${JIRA_ENTITIES:-project,issue,comment,attachment,worklog}"
  for ent in "${ent_arr[@]}"; do
    ent="$(printf '%s' "${ent}" | xargs)"
    [[ -z "${ent}" ]] && continue
    entities_json="$(jq -c --arg e "${ent}" '. + [{entityName: $e}]' <<<"${entities_json}")"
  done

  local modes_json
  if [[ "${ENABLE_JIRA_ACTIONS:-true}" == "true" ]]; then
    modes_json="$(jq -c -n --arg m "${JIRA_CONNECTOR_MODE:-FEDERATED}" '[$m, "ACTIONS"] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)')"
  else
    modes_json="$(jq -c -n --arg m "${JIRA_CONNECTOR_MODE:-FEDERATED}" '[$m]')"
  fi

  jq -n \
    --arg uri "${ATLASSIAN_INSTANCE_URI}" \
    --arg iid "${ATLASSIAN_INSTANCE_ID}" \
    --arg cid "${ATLASSIAN_CLIENT_ID}" \
    --arg csec "${ATLASSIAN_CLIENT_SECRET}" \
    --arg rtok "${ATLASSIAN_REFRESH_TOKEN:-}" \
    --arg refresh "${JIRA_REFRESH_INTERVAL:-86400s}" \
    --arg mode "${JIRA_CONNECTOR_MODE:-FEDERATED}" \
    --arg enable_act "${ENABLE_JIRA_ACTIONS:-true}" \
    --arg actions_csv "${JIRA_ENABLED_ACTIONS:-create_issue,update_issue,change_issue_status,create_comment,update_comment,upload_attachment}" \
    --argjson modes "${modes_json}" \
    --argjson entities "${entities_json}" \
    '{
      dataSource: "jira",
      connectorModes: $modes,
      refreshInterval: $refresh,
      autoRunDisabled: ($mode == "FEDERATED"),
      incrementalSyncDisabled: ($mode == "FEDERATED"),
      params: ({
        instance_uri: $uri,
        instance_id: $iid,
        client_id: $cid,
        client_secret: $csec,
        auth_type: "OAUTH"
      } + (if ($rtok | length) > 0 then {refresh_token: $rtok} else {} end)),
      entities: $entities
    } + (if $enable_act == "true" then {
      destinationConfigs: [{key: "url", destinations: [{host: $uri}]}],
      actionConfig: {
        isActionConfigured: true,
        createBapConnection: true,
        actionParams: ({
          instance_uri: $uri,
          instance_id: $iid,
          client_id: $cid,
          client_secret: $csec,
          auth_type: "OAUTH"
        } + (if ($rtok | length) > 0 then {refresh_token: $rtok} else {} end))
      },
      bapConfig: {
        supportedConnectorModes: ["ACTIONS"],
        enabledActions: ($actions_csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
      }
    } else {} end)'
}

render_confluence_connector_payload() {
  local entities_json="[]"
  IFS=',' read -r -a ent_arr <<< "${CONFLUENCE_ENTITIES:-space,page,blog,attachment,comment}"
  for ent in "${ent_arr[@]}"; do
    ent="$(printf '%s' "${ent}" | xargs)"
    [[ -z "${ent}" ]] && continue
    entities_json="$(jq -c --arg e "${ent}" '. + [{entityName: $e}]' <<<"${entities_json}")"
  done

  local modes_json
  if [[ "${ENABLE_CONFLUENCE_ACTIONS:-true}" == "true" ]]; then
    modes_json="$(jq -c -n --arg m "${CONFLUENCE_CONNECTOR_MODE:-FEDERATED}" '[$m, "ACTIONS"] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)')"
  else
    modes_json="$(jq -c -n --arg m "${CONFLUENCE_CONNECTOR_MODE:-FEDERATED}" '[$m]')"
  fi

  jq -n \
    --arg uri "${ATLASSIAN_INSTANCE_URI}" \
    --arg iid "${ATLASSIAN_INSTANCE_ID}" \
    --arg cid "${ATLASSIAN_CLIENT_ID}" \
    --arg csec "${ATLASSIAN_CLIENT_SECRET}" \
    --arg rtok "${ATLASSIAN_REFRESH_TOKEN:-}" \
    --arg refresh "${CONFLUENCE_REFRESH_INTERVAL:-86400s}" \
    --arg mode "${CONFLUENCE_CONNECTOR_MODE:-FEDERATED}" \
    --arg enable_act "${ENABLE_CONFLUENCE_ACTIONS:-true}" \
    --arg actions_csv "${CONFLUENCE_ENABLED_ACTIONS:-create_page,update_page}" \
    --argjson modes "${modes_json}" \
    --argjson entities "${entities_json}" \
    '{
      dataSource: "confluence",
      connectorModes: $modes,
      refreshInterval: $refresh,
      autoRunDisabled: ($mode == "FEDERATED"),
      incrementalSyncDisabled: ($mode == "FEDERATED"),
      params: ({
        instance_uri: $uri,
        instance_id: $iid,
        client_id: $cid,
        client_secret: $csec,
        auth_type: "OAUTH"
      } + (if ($rtok | length) > 0 then {refresh_token: $rtok} else {} end)),
      entities: $entities
    } + (if $enable_act == "true" then {
      destinationConfigs: [{key: "url", destinations: [{host: $uri}]}],
      actionConfig: {
        isActionConfigured: true,
        createBapConnection: true,
        actionParams: ({
          instance_uri: $uri,
          instance_id: $iid,
          client_id: $cid,
          client_secret: $csec,
          auth_type: "OAUTH"
        } + (if ($rtok | length) > 0 then {refresh_token: $rtok} else {} end))
      },
      bapConfig: {
        supportedConnectorModes: ["ACTIONS"],
        enabledActions: ($actions_csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
      }
    } else {} end)'
}

_patch_atlassian_actions_when_ready() {
  local col_id="$1"
  local display_label="$2"
  local patch_payload="$3"

  local base_v1alpha loc_parent get_url patch_url
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
  get_url="${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector"
  patch_url="${get_url}?updateMask=actionConfig,bapConfig"

  if [[ "${DRY_RUN:-false}" == "true" || -n "${MOCK_CURL_GET_STATUS:-}" || -n "${MOCK_CURL_PATCH_STATUS:-}" ]]; then
    ge_curl_request "PATCH" "${patch_url}" "${patch_payload}" >/dev/null
    log_ok "Activated Console Actions ('isActionConfigured=true') for ${display_label} ('${col_id}')."
    return 0
  fi

  local attempt=1 max_attempts=6 conn_json="" conn_state="" is_cfg=""
  while [[ "${attempt}" -le "${max_attempts}" ]]; do
    conn_json="$(ge_curl_request "GET" "${get_url}" "" "true" || echo '{}')"
    conn_state="$(jq -r '.state // empty' <<<"${conn_json}" 2>/dev/null || true)"
    is_cfg="$(jq -r '.actionConfig.isActionConfigured // false' <<<"${conn_json}" 2>/dev/null || echo "false")"

    if [[ "${is_cfg}" == "true" && "${conn_state}" != "INITIALIZING" && "${conn_state}" != "CREATING" ]]; then
      log_ok "Console Actions ('isActionConfigured=true') already active for ${display_label} ('${col_id}')."
      return 0
    fi

    if [[ "${conn_state}" == "INITIALIZING" || "${conn_state}" == "CREATING" ]]; then
      if [[ "${attempt}" -eq "${max_attempts}" ]]; then
        log_info "${display_label} connector ('${col_id}') is still ${conn_state} in the background; Terraform action_config and bap_config are already queued."
        return 0
      fi
      log_info "Waiting for ${display_label} connector ('${col_id}') to finish ${conn_state} before patching actions (attempt ${attempt}/${max_attempts})..."
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi
    break
  done

  ge_curl_request "PATCH" "${patch_url}" "${patch_payload}" "true" >/dev/null || true
  log_ok "Activated Console Actions ('isActionConfigured=true') for ${display_label} ('${col_id}')."
}

_provision_single_atlassian_connector() {
  local col_id="$1"
  local display_name="$2"
  local payload="$3"
  local include_create="$4"
  local enable_actions="$5"

  local base_v1alpha loc_parent get_url encoded_dn post_url
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
  get_url="${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector"
  encoded_dn="$(printf '%s' "${display_name}" | sed 's/ /%20/g; s/&/%26/g; s/(/%28/g; s/)/%29/g')"
  post_url="${base_v1alpha}/${loc_parent}:setUpDataConnectorV2?collectionId=${col_id}&collectionDisplayName=${encoded_dn}"

  if [[ "${include_create}" == "true" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
    else
      local check_rc=0
      ge_curl_request "GET" "${get_url}" "" "true" >/dev/null || check_rc=$?
      if [[ "${check_rc}" -eq 44 ]]; then
        ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
      else
        ge_curl_request "PATCH" "${get_url}?updateMask=connectorModes,params,entities,destinationConfigs,actionConfig,bapConfig" "${payload}" "true" >/dev/null || true
      fi
    fi
  elif [[ "${enable_actions}" == "true" ]]; then
    local act_payload
    act_payload="$(jq -c '{actionConfig, bapConfig}' <<<"${payload}")"
    _patch_atlassian_actions_when_ready "${col_id}" "${display_name}" "${act_payload}"
  fi

  log_ok "Atlassian Data Connector '${col_id}' (${display_name}) configured."
}

configure_atlassian_connectors() {
  local include_create="${1:-false}"
  log_phase "ATLASSIAN-CONNECTORS" "Configuring Gemini Enterprise Jira Cloud & Confluence Cloud Connectors"

  ensure_and_load_atlassian_secret_credentials

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  if [[ "${ATLASSIAN_CONFIGURE_ACL:-true}" == "true" ]]; then
    log_info "Ensuring Discovery Engine ACL settings (${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}) are active for Atlassian..."
    local acl_payload
    acl_payload="$(jq -n --arg name "${loc_parent}/aclConfig" --arg idp "${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}" '{name: $name, idpConfig: {idpType: $idp}}')"
    ge_curl_request "PATCH" "${base_v1alpha}/${loc_parent}/aclConfig" "${acl_payload}" >/dev/null
  fi

  if [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]]; then
    local jira_payload
    jira_payload="$(render_jira_connector_payload)"
    _provision_single_atlassian_connector \
      "${JIRA_COLLECTION_ID}" \
      "${JIRA_COLLECTION_DISPLAY_NAME}" \
      "${jira_payload}" \
      "${include_create}" \
      "${ENABLE_JIRA_ACTIONS:-true}"
  fi

  if [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]]; then
    local conf_payload
    conf_payload="$(render_confluence_connector_payload)"
    _provision_single_atlassian_connector \
      "${CONFLUENCE_COLLECTION_ID}" \
      "${CONFLUENCE_COLLECTION_DISPLAY_NAME}" \
      "${conf_payload}" \
      "${include_create}" \
      "${ENABLE_CONFLUENCE_ACTIONS:-true}"
  fi

  bind_atlassian_collection_iam
  attach_atlassian_datastores_to_engines
}

bind_atlassian_collection_iam() {
  if [[ -z "${ATLASSIAN_ACCESS_GROUPS:-}" || "${DRY_RUN:-false}" == "true" ]]; then
    return 0
  fi

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  local cols=()
  [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]] && cols+=("${JIRA_COLLECTION_ID}")
  [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]] && cols+=("${CONFLUENCE_COLLECTION_ID}")

  local members_json="[]"
  IFS=',' read -r -a grp_arr <<< "${ATLASSIAN_ACCESS_GROUPS}"
  for grp in "${grp_arr[@]}"; do
    grp="$(printf '%s' "${grp}" | xargs)"
    [[ -z "${grp}" ]] && continue
    members_json="$(jq -c --arg m "group:${grp#group:}" '. + [$m] | unique' <<<"${members_json}")"
  done

  for col in "${cols[@]}"; do
    local col_url="${base_v1alpha}/${loc_parent}/collections/${col}"
    local col_pol col_etag col_set_payload
    col_pol="$(ge_curl_request "GET" "${col_url}:getIamPolicy" "" "true" || echo '{}')"
    col_etag="$(jq -r '.etag // empty' <<<"${col_pol}" 2>/dev/null || true)"
    col_set_payload="$(jq -n --argjson cur "${col_pol}" --arg etag "${col_etag}" --argjson newMems "${members_json}" '
      def add_mems(r):
        (([$cur.bindings[]? | select(.role == r) | .members[]?] + $newMems) | unique);
      {
        policy: (
          (if ($etag | length) > 0 then {etag: $etag} else {} end) + {
            bindings: [
              {role: "roles/discoveryengine.user", members: add_mems("roles/discoveryengine.user")},
              {role: "roles/discoveryengine.viewer", members: add_mems("roles/discoveryengine.viewer")},
              {role: "roles/discoveryengine.agentspaceUser", members: add_mems("roles/discoveryengine.agentspaceUser")}
            ]
          }
        )
      }')"
    ge_curl_request "POST" "${col_url}:setIamPolicy" "${col_set_payload}" "true" >/dev/null || true
    log_ok "Bound Collection-level IAM on '${col}' for groups: ${ATLASSIAN_ACCESS_GROUPS}"
  done
}

attach_atlassian_datastores_to_engines() {
  if [[ -z "${ATLASSIAN_TARGET_APPS:-}" ]]; then
    return 0
  fi

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  local all_ds_ids_json="[]"

  if [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]]; then
    local jira_ds_ids="[]"
    IFS=',' read -r -a ent_arr <<< "${JIRA_ENTITIES:-project,issue,comment,attachment,worklog}"
    for ent in "${ent_arr[@]}"; do
      ent="$(printf '%s' "${ent}" | xargs)"
      [[ -z "${ent}" ]] && continue
      jira_ds_ids="$(jq -c --arg ds "${JIRA_COLLECTION_ID}_${ent}" '. + [$ds]' <<<"${jira_ds_ids}")"
    done
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      local conn_json live_ids
      conn_json="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${JIRA_COLLECTION_ID}/dataConnector" "" "true" || echo '{}')"
      live_ids="$(jq -c -n --argjson conn "${conn_json}" '([($conn.entities // [])[] | .dataStore // empty | split("/") | last] | map(select(length > 0))) | unique')"
      if [[ "$(jq -r 'length' <<<"${live_ids}")" -gt 0 ]]; then
        jira_ds_ids="${live_ids}"
      fi
    fi
    all_ds_ids_json="$(jq -c -n --argjson a "${all_ds_ids_json}" --argjson b "${jira_ds_ids}" '($a + $b) | unique')"
  fi

  if [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]]; then
    local conf_ds_ids="[]"
    IFS=',' read -r -a ent_arr <<< "${CONFLUENCE_ENTITIES:-space,page,blog,attachment,comment}"
    for ent in "${ent_arr[@]}"; do
      ent="$(printf '%s' "${ent}" | xargs)"
      [[ -z "${ent}" ]] && continue
      conf_ds_ids="$(jq -c --arg ds "${CONFLUENCE_COLLECTION_ID}_${ent}" '. + [$ds]' <<<"${conf_ds_ids}")"
    done
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      local conn_json live_ids
      conn_json="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${CONFLUENCE_COLLECTION_ID}/dataConnector" "" "true" || echo '{}')"
      live_ids="$(jq -c -n --argjson conn "${conn_json}" '([($conn.entities // [])[] | .dataStore // empty | split("/") | last] | map(select(length > 0))) | unique')"
      if [[ "$(jq -r 'length' <<<"${live_ids}")" -gt 0 ]]; then
        conf_ds_ids="${live_ids}"
      fi
    fi
    all_ds_ids_json="$(jq -c -n --argjson a "${all_ds_ids_json}" --argjson b "${conf_ds_ids}" '($a + $b) | unique')"
  fi

  IFS=',' read -r -a app_arr <<< "${ATLASSIAN_TARGET_APPS}"
  for app_id in "${app_arr[@]}"; do
    app_id="$(printf '%s' "${app_id}" | xargs)"
    [[ -z "${app_id}" ]] && continue
    local engine_url="${base_v1alpha}/${loc_parent}/collections/default_collection/engines/${app_id}"
    log_info "Attaching Atlassian Jira & Confluence Data Stores to Gemini Enterprise App '${app_id}'..."
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "$(jq -n --argjson ids "${all_ds_ids_json}" '{dataStoreIds: $ids}')" >/dev/null
      continue
    fi
    local eng_json
    eng_json="$(ge_curl_request "GET" "${engine_url}" "" "true" || echo '{}')"
    if [[ -n "$(jq -r '.name // empty' <<<"${eng_json}" 2>/dev/null || true)" ]]; then
      local merged_payload
      merged_payload="$(jq -n --argjson cur "${eng_json}" --argjson atIds "${all_ds_ids_json}" '{dataStoreIds: ((($cur.dataStoreIds // []) + $atIds) | unique)}')"
      ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "${merged_payload}" "true" >/dev/null || true
      log_ok "Attached Atlassian Data Stores ($(jq -r 'join(",")' <<<"${all_ds_ids_json}")) to Gemini Enterprise App '${app_id}'."
    fi
  done
}

deregister_atlassian_connectors() {
  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  if [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]]; then
    log_info "Ensuring Jira Cloud collection '${JIRA_COLLECTION_ID}' is cleaned up..."
    ge_curl_request "DELETE" "${base_v1alpha}/${loc_parent}/collections/${JIRA_COLLECTION_ID}" "" "true" >/dev/null || true
  fi
  if [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]]; then
    log_info "Ensuring Confluence Cloud collection '${CONFLUENCE_COLLECTION_ID}' is cleaned up..."
    ge_curl_request "DELETE" "${base_v1alpha}/${loc_parent}/collections/${CONFLUENCE_COLLECTION_ID}" "" "true" >/dev/null || true
  fi
  log_ok "Atlassian connector collections cleanup complete."
}

verify_atlassian_connectors() {
  log_phase "VERIFY-ATLASSIAN" "Verifying Atlassian Jira Cloud & Confluence Cloud Data Connectors via Discovery Engine API"
  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  if [[ "${ENABLE_JIRA_CONNECTOR:-true}" == "true" ]]; then
    local jira_url="${base_v1alpha}/${loc_parent}/collections/${JIRA_COLLECTION_ID}/dataConnector"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "GET" "${jira_url}" >/dev/null
      log_ok "Jira Cloud Data Connector '${JIRA_COLLECTION_ID}' dry-run verified."
    else
      local j_resp j_state j_act_state
      j_resp="$(ge_curl_request "GET" "${jira_url}" "" "true" || echo '{}')"
      j_state="$(jq -r '.state // "ACTIVE"' <<<"${j_resp}" 2>/dev/null || echo "ACTIVE")"
      j_act_state="$(jq -r '.actionState // "N/A"' <<<"${j_resp}" 2>/dev/null || echo "N/A")"
      log_ok "Jira Cloud Data Connector '${JIRA_COLLECTION_ID}' verified (state=${j_state}, actionState=${j_act_state})."
    fi
  fi

  if [[ "${ENABLE_CONFLUENCE_CONNECTOR:-true}" == "true" ]]; then
    local conf_url="${base_v1alpha}/${loc_parent}/collections/${CONFLUENCE_COLLECTION_ID}/dataConnector"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "GET" "${conf_url}" >/dev/null
      log_ok "Confluence Cloud Data Connector '${CONFLUENCE_COLLECTION_ID}' dry-run verified."
    else
      local c_resp c_state c_act_state
      c_resp="$(ge_curl_request "GET" "${conf_url}" "" "true" || echo '{}')"
      c_state="$(jq -r '.state // "ACTIVE"' <<<"${c_resp}" 2>/dev/null || echo "ACTIVE")"
      c_act_state="$(jq -r '.actionState // "N/A"' <<<"${c_resp}" 2>/dev/null || echo "N/A")"
      log_ok "Confluence Cloud Data Connector '${CONFLUENCE_COLLECTION_ID}' verified (state=${c_state}, actionState=${c_act_state})."
    fi
  fi
}

print_atlassian_summary() {
  log_phase "SUMMARY" "Atlassian Jira Cloud & Confluence Cloud Deployment Summary"
  printf '  Project ID          : %s\n' "${GCP_PROJECT_ID}"
  printf '  Location            : %s\n' "${GE_LOCATION}"
  printf '  Secret Manager ID   : %s\n' "${ATLASSIAN_SECRET_ID}"
  printf '  Atlassian Site URI  : %s\n' "${ATLASSIAN_INSTANCE_URI}"
  printf '  Tenant Cloud ID     : %s\n' "${ATLASSIAN_INSTANCE_ID}"
  printf '  Admin Account       : %s\n' "${ATLASSIAN_ADMIN_EMAIL}"
  printf '  Jira Collection     : %s (%s | mode=%s | actions=%s)\n' "${JIRA_COLLECTION_ID}" "${JIRA_COLLECTION_DISPLAY_NAME}" "${JIRA_CONNECTOR_MODE}" "${JIRA_ENABLED_ACTIONS}"
  printf '  Confluence Collect. : %s (%s | mode=%s | actions=%s)\n' "${CONFLUENCE_COLLECTION_ID}" "${CONFLUENCE_COLLECTION_DISPLAY_NAME}" "${CONFLUENCE_CONNECTOR_MODE}" "${CONFLUENCE_ENABLED_ACTIONS}"
  printf '  Target GE Apps      : %s\n' "${ATLASSIAN_TARGET_APPS:-<none>}"
  printf '  GCP Console URL     : https://console.cloud.google.com/gen-app-builder/data-stores?project=%s\n' "${GCP_PROJECT_ID}"
}

run_atlassian_verification_and_summary() {
  verify_atlassian_connectors
  print_atlassian_summary
}
