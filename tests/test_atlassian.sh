#!/usr/bin/env bash
# ==============================================================================
# Unit & Dry-Run Integration Tests for Atlassian Jira & Confluence Automation
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
  local actual="$1"
  local expected="$2"
  local msg="$3"
  if [[ "${actual}" == "${expected}" ]]; then
    echo "  [PASS] ${msg}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  [FAIL] ${msg} (expected='${expected}', actual='${actual}')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if grep -qF "${needle}" <<<"${haystack}"; then
    echo "  [PASS] ${msg}"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  [FAIL] ${msg} (missing '${needle}')"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "=================================================================="
echo " Running Atlassian Jira Cloud & Confluence Cloud Test Suite"
echo "=================================================================="

# 1. Test deploy_atlassian_bootstrap.sh --dry-run
echo ">>> [1/5] Testing deploy_atlassian_bootstrap.sh --dry-run..."
BOOT_OUT="$("${INFRA_DIR}/deploy_atlassian_bootstrap.sh" \
  --instance-uri "https://mohanrajs-team.atlassian.net" \
  --admin-email "mohanraj@mohanrajs.demo.altostrat.com" \
  --customer-name "cymbal" \
  --customer-domain "mohanrajs.demo.altostrat.com" \
  --gcp-project-id "cymbal-app-514110" \
  --dry-run 2>&1)"
assert_contains "${BOOT_OUT}" "6ef6b83c-0038-4b28-941f-074fb11ea8c6" "Bootstrap dry-run resolves Cloud ID 6ef6b83c-0038-4b28-941f-074fb11ea8c6"
assert_contains "${BOOT_OUT}" "Wrote Phase 2C configuration file" "Bootstrap generates configs/cymbal-atlassian.env"

# 2. Test render_jira_connector_payload & render_confluence_connector_payload
echo ">>> [2/5] Testing Jira & Confluence setUpDataConnectorV2 JSON payload rendering..."
# shellcheck source=../scripts/lib/common.sh
source "${INFRA_DIR}/scripts/lib/common.sh"
# shellcheck source=../scripts/lib/http.sh
source "${INFRA_DIR}/scripts/lib/http.sh"
# shellcheck source=../scripts/configure_atlassian_connectors.sh
source "${INFRA_DIR}/scripts/configure_atlassian_connectors.sh"

export DRY_RUN="true"
load_atlassian_config "${INFRA_DIR}/configs/.generated/cymbal-atlassian.env"
export ATLASSIAN_CLIENT_ID="test-jira-conf-client-id"
export ATLASSIAN_CLIENT_SECRET="test-jira-conf-client-secret"
export ATLASSIAN_REFRESH_TOKEN="test-jira-conf-refresh-token"

JIRA_JSON="$(render_jira_connector_payload)"
assert_eq "$(jq -r '.dataSource' <<<"${JIRA_JSON}")" "jira" "Jira payload dataSource is 'jira'"
assert_eq "$(jq -r '.connectorModes | join(",")' <<<"${JIRA_JSON}")" "FEDERATED,ACTIONS" "Jira payload connectorModes is FEDERATED,ACTIONS"
assert_eq "$(jq -r '.params.instance_uri' <<<"${JIRA_JSON}")" "https://mohanrajs-team.atlassian.net" "Jira payload params.instance_uri matches mohanrajs-team.atlassian.net"
assert_eq "$(jq -r '.params.instance_id' <<<"${JIRA_JSON}")" "6ef6b83c-0038-4b28-941f-074fb11ea8c6" "Jira payload params.instance_id matches Cloud ID"
assert_eq "$(jq -r '.params.auth_type' <<<"${JIRA_JSON}")" "OAUTH" "Jira payload params.auth_type is OAUTH"
assert_eq "$(jq -r '[.entities[].entityName] | join(",")' <<<"${JIRA_JSON}")" "project,issue,comment,attachment,worklog" "Jira payload entities match project,issue,comment,attachment,worklog"
assert_eq "$(jq -r '.actionConfig.isActionConfigured' <<<"${JIRA_JSON}")" "true" "Jira payload actionConfig.isActionConfigured is true"
assert_contains "$(jq -r '.bapConfig.enabledActions | join(",")' <<<"${JIRA_JSON}")" "create_issue,update_issue,change_issue_status,create_comment,update_comment,upload_attachment,download_attachment,create_issue_link,create_project,update_project,create_worklog,update_worklog,search_issues,get_issue,list_issues" "Jira payload enabledActions include all Standard and Read-only actions"

CONF_JSON="$(render_confluence_connector_payload)"
assert_eq "$(jq -r '.dataSource' <<<"${CONF_JSON}")" "confluence" "Confluence payload dataSource is 'confluence'"
assert_eq "$(jq -r '.connectorModes | join(",")' <<<"${CONF_JSON}")" "FEDERATED,ACTIONS" "Confluence payload connectorModes is FEDERATED,ACTIONS"
assert_eq "$(jq -r '.params.instance_uri' <<<"${CONF_JSON}")" "https://mohanrajs-team.atlassian.net" "Confluence payload params.instance_uri matches mohanrajs-team.atlassian.net"
assert_eq "$(jq -r '.params.instance_id' <<<"${CONF_JSON}")" "6ef6b83c-0038-4b28-941f-074fb11ea8c6" "Confluence payload params.instance_id matches Cloud ID"
assert_eq "$(jq -r '[.entities[].entityName] | join(",")' <<<"${CONF_JSON}")" "space,page,blog,attachment,comment" "Confluence payload entities match space,page,blog,attachment,comment"
assert_eq "$(jq -r '.bapConfig.enabledActions | length' <<<"${CONF_JSON}")" "23" "Confluence payload enabledActions include all 23 Standard and Read-only actions"

# 3. Test deploy_atlassian.sh --curl-only --dry-run
echo ">>> [3/5] Testing deploy_atlassian.sh --curl-only --dry-run..."
DEPLOY_OUT="$("${INFRA_DIR}/deploy_atlassian.sh" --config "${INFRA_DIR}/configs/.generated/cymbal-atlassian.env" --curl-only --dry-run 2>&1)"
assert_contains "${DEPLOY_OUT}" "cymbal-jira-fed" "deploy_atlassian.sh dry-run provisions cymbal-jira-fed"
assert_contains "${DEPLOY_OUT}" "cymbal-confluence-fed" "deploy_atlassian.sh dry-run provisions cymbal-confluence-fed"
assert_contains "${DEPLOY_OUT}" "cymbal-dev-sandbox-app" "deploy_atlassian.sh dry-run attaches to cymbal-dev-sandbox-app"
assert_contains "${DEPLOY_OUT}" "cymbal-service-desk-app" "deploy_atlassian.sh dry-run attaches to cymbal-service-desk-app"

# 4. Test onboard_customer.sh --only-phases 0E,2C --dry-run
echo ">>> [4/5] Testing onboard_customer.sh --only-phases 0E,2C --dry-run..."
ONBOARD_OUT="$("${INFRA_DIR}/onboard_customer.sh" --config "${INFRA_DIR}/configs/cymbal-onboard.env" --only-phases 0E,2C --dry-run 2>&1)"
assert_contains "${ONBOARD_OUT}" "[ENABLED] Phase 0E : Atlassian Cloud Bootstrap" "onboard_customer.sh enables Phase 0E"
assert_contains "${ONBOARD_OUT}" "[ENABLED] Phase 2C : Shared Atlassian Connectors" "onboard_customer.sh enables Phase 2C"
assert_contains "${ONBOARD_OUT}" "[SKIPPED] Phase 2  : Shared M365 Connectors" "onboard_customer.sh skips other phases when --only-phases 0E,2C"

# 5. Test Terraform syntax in terraform-atlassian/
echo ">>> [5/5] Validating Terraform HCL in infra/terraform-atlassian/..."
terraform -chdir="${INFRA_DIR}/terraform-atlassian" init -backend=false -input=false >/dev/null
TF_VAL_OUT="$(terraform -chdir="${INFRA_DIR}/terraform-atlassian" validate -json)"
assert_eq "$(jq -r '.valid' <<<"${TF_VAL_OUT}")" "true" "terraform-atlassian/ HCL validation passes"

echo "=================================================================="
echo " Atlassian Test Summary: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "=================================================================="
[[ "${FAIL_COUNT}" -eq 0 ]]
