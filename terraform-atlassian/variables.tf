variable "project_id" {
  description = "Google Cloud Project ID hosting Gemini Enterprise."
  type        = string
}

variable "region" {
  description = "Google Cloud region for regional resources."
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Discovery Engine multi-region location (global, us, or eu)."
  type        = string
  default     = "global"
}

variable "atlassian_secret_id" {
  description = "Secret Manager secret ID storing Atlassian OAuth 2.0 & API credentials JSON."
  type        = string
  default     = "cymbal-atlassian-connector-credentials"
}

variable "atlassian_instance_uri" {
  description = "Atlassian Cloud site URL (e.g., https://mohanrajs-team.atlassian.net)."
  type        = string
  default     = "https://mohanrajs-team.atlassian.net"
}

variable "atlassian_instance_id" {
  description = "Atlassian Cloud ID (UUID from /_edge/tenant_info)."
  type        = string
  default     = "6ef6b83c-0038-4b28-941f-074fb11ea8c6"
}

variable "atlassian_admin_email" {
  description = "Atlassian Cloud administrator email address."
  type        = string
  default     = "mohanraj@mohanrajs.demo.altostrat.com"
}

variable "atlassian_client_id" {
  description = "Atlassian OAuth 2.0 (3LO) Client ID."
  type        = string
  default     = ""
  sensitive   = true
}

variable "atlassian_client_secret" {
  description = "Atlassian OAuth 2.0 (3LO) Client Secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "atlassian_refresh_token" {
  description = "Atlassian OAuth 2.0 (3LO) Refresh Token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "atlassian_api_token" {
  description = "Optional Atlassian API Token."
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_jira_connector" {
  description = "Whether to provision the Jira Cloud Data Connector."
  type        = string
  default     = "true"
}

variable "jira_collection_id" {
  description = "Collection ID for the Jira Cloud Data Connector."
  type        = string
  default     = "cymbal-jira-fed"
}

variable "jira_collection_display_name" {
  description = "Display name for the Jira Cloud Data Connector."
  type        = string
  default     = "Jira Cloud (cymbal)"
}

variable "jira_connector_mode" {
  description = "Primary connector mode for Jira Cloud (FEDERATED or DATA_INGESTION)."
  type        = string
  default     = "FEDERATED"
}

variable "jira_refresh_interval" {
  description = "Full sync refresh interval for Jira Cloud."
  type        = string
  default     = "86400s"
}

variable "jira_entities" {
  description = "Comma-separated Jira entities to search/sync."
  type        = string
  default     = "project,issue,comment,attachment,worklog"
}

variable "enable_jira_actions" {
  description = "Whether to enable BAP Write Actions on Jira Cloud."
  type        = string
  default     = "true"
}

variable "jira_enabled_actions" {
  description = "Comma-separated BAP write actions enabled for Jira Cloud."
  type        = string
  default     = "create_issue,update_issue,change_issue_status,create_comment,update_comment,upload_attachment,download_attachment,create_issue_link,create_project,update_project,create_worklog,update_worklog,search_issues,get_issue,list_issues,get_comment,list_comments,get_attachment,list_attachments,get_project,list_projects,get_worklog,list_worklogs,get_user,list_users,search_users,get_board,list_boards,get_sprint,list_sprints,get_priority,list_priorities,get_issue_type,list_issue_types,get_issue_transitions,list_issue_transitions"
}

variable "enable_confluence_connector" {
  description = "Whether to provision the Confluence Cloud Data Connector."
  type        = string
  default     = "true"
}

variable "confluence_collection_id" {
  description = "Collection ID for the Confluence Cloud Data Connector."
  type        = string
  default     = "cymbal-confluence-fed"
}

variable "confluence_collection_display_name" {
  description = "Display name for the Confluence Cloud Data Connector."
  type        = string
  default     = "Confluence Cloud (cymbal)"
}

variable "confluence_connector_mode" {
  description = "Primary connector mode for Confluence Cloud (FEDERATED or DATA_INGESTION)."
  type        = string
  default     = "FEDERATED"
}

variable "confluence_refresh_interval" {
  description = "Full sync refresh interval for Confluence Cloud."
  type        = string
  default     = "86400s"
}

variable "confluence_entities" {
  description = "Comma-separated Confluence entities to search/sync."
  type        = string
  default     = "space,page,blog,attachment,comment"
}

variable "enable_confluence_actions" {
  description = "Whether to enable BAP Write Actions on Confluence Cloud."
  type        = string
  default     = "true"
}

variable "confluence_enabled_actions" {
  description = "Comma-separated BAP write actions enabled for Confluence Cloud."
  type        = string
  default     = "create_page,update_page,create_blog_post,create_space,download_attachment,get_system_info,list_attachments,list_blog_posts,list_comments,list_pages,list_tasks,list_whiteboards,upload_attachment,get_attachment,get_blog_post,get_comment,get_page,get_space,get_task,get_user,get_whiteboard,list_spaces,list_users"
}
