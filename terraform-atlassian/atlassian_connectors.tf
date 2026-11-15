# Atlassian Jira Cloud & Confluence Cloud Discovery Engine Data Connectors & BAP Actions

resource "google_project_service" "discoveryengine" {
  project            = var.project_id
  service            = "discoveryengine.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_secret_manager_secret" "atlassian_credentials" {
  project   = var.project_id
  secret_id = var.atlassian_secret_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "atlassian_credentials_initial" {
  secret = google_secret_manager_secret.atlassian_credentials.id
  secret_data = jsonencode({
    instance_uri  = var.atlassian_instance_uri
    instance_id   = var.atlassian_instance_id
    client_id     = var.atlassian_client_id
    client_secret = var.atlassian_client_secret
    refresh_token = var.atlassian_refresh_token
    user_account  = var.atlassian_admin_email
    api_token     = var.atlassian_api_token
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "google_secret_manager_secret_version" "atlassian_credentials_latest" {
  project    = var.project_id
  secret     = google_secret_manager_secret.atlassian_credentials.secret_id
  version    = "latest"
  depends_on = [google_secret_manager_secret_version.atlassian_credentials_initial]
}

locals {
  at_secret_json          = jsondecode(data.google_secret_manager_secret_version.atlassian_credentials_latest.secret_data)
  effective_instance_uri  = var.atlassian_instance_uri != "" ? var.atlassian_instance_uri : try(local.at_secret_json.instance_uri, "")
  effective_instance_id   = var.atlassian_instance_id != "" ? var.atlassian_instance_id : try(local.at_secret_json.instance_id, "")
  effective_client_id     = var.atlassian_client_id != "" ? var.atlassian_client_id : try(local.at_secret_json.client_id, "")
  effective_client_secret = var.atlassian_client_secret != "" ? var.atlassian_client_secret : try(local.at_secret_json.client_secret, "")
  effective_refresh_token = var.atlassian_refresh_token != "" ? var.atlassian_refresh_token : try(local.at_secret_json.refresh_token, "")

  jira_entity_list = [
    for e in split(",", var.jira_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  jira_action_list = [
    for a in split(",", var.jira_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  jira_supports_actions = var.enable_jira_actions == "true"

  confluence_entity_list = [
    for e in split(",", var.confluence_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  confluence_action_list = [
    for a in split(",", var.confluence_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  confluence_supports_actions = var.enable_confluence_actions == "true"
}

resource "google_discovery_engine_data_connector" "jira" {
  count                     = var.enable_jira_connector == "true" ? 1 : 0
  project                   = var.project_id
  location                  = var.location
  collection_id             = var.jira_collection_id
  collection_display_name   = replace(var.jira_collection_display_name, "&", "and")
  data_source               = "jira"
  connector_modes           = local.jira_supports_actions ? distinct([var.jira_connector_mode, "ACTIONS"]) : [var.jira_connector_mode]
  refresh_interval          = var.jira_refresh_interval
  auto_run_disabled         = var.jira_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.jira_connector_mode == "FEDERATED"

  json_params = jsonencode(merge(
    {
      instance_uri  = local.effective_instance_uri
      instance_id   = local.effective_instance_id
      client_id     = local.effective_client_id
      client_secret = local.effective_client_secret
      auth_type     = "OAUTH"
    },
    local.effective_refresh_token != "" ? { refresh_token = local.effective_refresh_token } : {}
  ))

  dynamic "entities" {
    for_each = local.jira_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "destination_configs" {
    for_each = local.jira_supports_actions ? [1] : []
    content {
      key = "url"
      destinations {
        host = local.effective_instance_uri
      }
    }
  }

  dynamic "action_config" {
    for_each = local.jira_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = merge(
        {
          instance_uri  = local.effective_instance_uri
          instance_id   = local.effective_instance_id
          client_id     = local.effective_client_id
          client_secret = local.effective_client_secret
          auth_type     = "OAUTH"
        },
        local.effective_refresh_token != "" ? { refresh_token = local.effective_refresh_token } : {}
      )
    }
  }

  dynamic "bap_config" {
    for_each = local.jira_supports_actions && length(local.jira_action_list) > 0 ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.jira_action_list
    }
  }

  lifecycle {
    ignore_changes = [collection_display_name, connector_modes, refresh_interval, bap_config, tag, static_ip_enabled, entities, json_params, action_config, destination_configs, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [
    google_project_service.discoveryengine,
    data.google_secret_manager_secret_version.atlassian_credentials_latest,
  ]
}

resource "google_discovery_engine_data_connector" "confluence" {
  count                     = var.enable_confluence_connector == "true" ? 1 : 0
  project                   = var.project_id
  location                  = var.location
  collection_id             = var.confluence_collection_id
  collection_display_name   = replace(var.confluence_collection_display_name, "&", "and")
  data_source               = "confluence"
  connector_modes           = local.confluence_supports_actions ? distinct([var.confluence_connector_mode, "ACTIONS"]) : [var.confluence_connector_mode]
  refresh_interval          = var.confluence_refresh_interval
  auto_run_disabled         = var.confluence_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.confluence_connector_mode == "FEDERATED"

  json_params = jsonencode(merge(
    {
      instance_uri  = local.effective_instance_uri
      instance_id   = local.effective_instance_id
      client_id     = local.effective_client_id
      client_secret = local.effective_client_secret
      auth_type     = "OAUTH"
    },
    local.effective_refresh_token != "" ? { refresh_token = local.effective_refresh_token } : {}
  ))

  dynamic "entities" {
    for_each = local.confluence_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "destination_configs" {
    for_each = local.confluence_supports_actions ? [1] : []
    content {
      key = "url"
      destinations {
        host = local.effective_instance_uri
      }
    }
  }

  dynamic "action_config" {
    for_each = local.confluence_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = merge(
        {
          instance_uri  = local.effective_instance_uri
          instance_id   = local.effective_instance_id
          client_id     = local.effective_client_id
          client_secret = local.effective_client_secret
          auth_type     = "OAUTH"
        },
        local.effective_refresh_token != "" ? { refresh_token = local.effective_refresh_token } : {}
      )
    }
  }

  dynamic "bap_config" {
    for_each = local.confluence_supports_actions && length(local.confluence_action_list) > 0 ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.confluence_action_list
    }
  }

  lifecycle {
    ignore_changes = [collection_display_name, connector_modes, refresh_interval, bap_config, tag, static_ip_enabled, entities, json_params, action_config, destination_configs, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [
    google_project_service.discoveryengine,
    data.google_secret_manager_secret_version.atlassian_credentials_latest,
  ]
}
