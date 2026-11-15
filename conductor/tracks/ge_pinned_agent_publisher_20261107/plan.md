# Implementation Plan: Gemini Enterprise Pinned Assistant Publisher (`agents-cli publish` & `registry`)

## Phase 1: `agents-cli publish gemini-enterprise` Wrapper & Discovery Engine `v1alpha` Enricher
- [x] Task 1.1: Implement `GeAgentPublisherService` (`backend/app/services/ge_agent_publisher.py`) wrapping `agents-cli publish gemini-enterprise`, `deployment_metadata.json` resolution, and Discovery Engine `v1alpha` `PATCH` (`defaultPinned: true` and `starterPrompts`).
- [x] Task 1.2: Expose Admin endpoints under `/api/v1/admin/provisioning/ge-agents` (`GET /ge-agents`, `POST /ge-agents/publish`, `POST /ge-agents/{engine_id}/sync-starter-prompts`).
- [x] Task 1.3: Hook Stage 6 (`approve_workflow` in `backend/skill_workflow_service/engine.py`) to automatically trigger `sync_starter_prompts_for_engine` for all `selected_targets`.

## Phase 2: Admin UI for Pinned GE Agent Registration & Fleet Registry
- [x] Task 2.1: Add the **"Pin Orchestrator (`agents-cli publish`)"** tab in `frontend/src/components/ProvisioningStudio.tsx` allowing Admins to select target GE App(s), attach `--authorization-id`, view the `agents-cli publish gemini-enterprise` command, and inspect synced `starterPrompts`.
- [x] Task 2.2: Add backend and frontend unit tests (`pytest` and `vitest`) for GE Agent publishing and starter prompt synchronization.
