output "jira_connector_name" {
  description = "Full resource name of the Jira Cloud Discovery Engine Data Connector."
  value       = try(google_discovery_engine_data_connector.jira[0].name, "")
}

output "jira_collection_id" {
  description = "Collection ID hosting the Jira Cloud entity data stores."
  value       = try(google_discovery_engine_data_connector.jira[0].collection_id, "")
}

output "confluence_connector_name" {
  description = "Full resource name of the Confluence Cloud Discovery Engine Data Connector."
  value       = try(google_discovery_engine_data_connector.confluence[0].name, "")
}

output "confluence_collection_id" {
  description = "Collection ID hosting the Confluence Cloud entity data stores."
  value       = try(google_discovery_engine_data_connector.confluence[0].collection_id, "")
}

output "atlassian_secret_id" {
  description = "Secret Manager secret ID storing Atlassian OAuth & API credentials."
  value       = google_secret_manager_secret.atlassian_credentials.secret_id
}
