# Specification: Gemini Enterprise Pinned Assistant Publisher (`agents-cli publish` & `registry`)

## 1. Overview
Provide a 1-click Admin capability and CLI workflow wrapping **`agents-cli publish gemini-enterprise`** and **`agents-cli registry`** (plus Discovery Engine `v1alpha` UI metadata enrichment) to register the **Universal Enterprise Skill Orchestrator** as a **first-class Pinned Assistant** (`defaultPinned: true`, right alongside Google's built-in **Deep Research** agent) on any Gemini Enterprise App (`engines/{engine_id}/assistants/default_assistant/agents`), bind OAuth 2.0 user token passthrough (`--authorization-id`), and automatically sync newly published Skills from Stage 6 as clickable `starterPrompts` cards.

## 2. Key Capabilities
- **Discovery Engine `Authorization` Resource Provisioning:**
  - `POST /v1alpha/projects/{project}/locations/global/authorizations?authorizationId={auth_id}` configuring `serverSideOauth2` for Google OAuth user token passthrough.
- **Native Registration via `agents-cli publish gemini-enterprise`:**
  - Executes `agents-cli publish gemini-enterprise --app-id <ENGINE_ID> --display-name "Enterprise Skill Orchestrator" --description "..." --authorization-id <AUTH_RESOURCE> --mode adk` (automatically reading `remote_agent_engine_id` from `deployment_metadata.json`).
  - Inspects fleet state via `agents-cli registry agents list --location global`.
- **UI Pinning & Automatic `starterPrompts` Sync (`v1alpha` `PATCH`):**
  - Enriches the registered GE Agent with `defaultPinned: true`, `customPlaceholderText`, and `starterPrompts` generated from all approved Skills distributed to that `engine_id` in Stage 6.
