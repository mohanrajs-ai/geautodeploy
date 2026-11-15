# Google ADK Agents, `agents-cli` & Skill Catalog Style Guide (`agents/` & `skills_catalog/`)

## 1. Mandatory `agents-cli` Lifecycle (`google-agents-cli ~= 1.4.1`)
All ADK agents under `agents/` (starting with `agents/universal_skill_orchestrator/`) MUST be scaffolded, smoke-tested, evaluated, deployed, and published using **`agents-cli`** (`uv tool install "google-agents-cli~=1.4.1"`):

1. **Scaffold & Enhance (`agents-cli scaffold`):**
   ```bash
   # Prototype-first creation (name <= 26 chars, lowercase/hyphens)
   agents-cli scaffold create universal-skill-agent \
     --agent adk \
     --deployment-target agent_runtime \
     --region us-central1 \
     --prototype \
     --agent-guidance-filename GEMINI.md

   # Add Agent Runtime deployment & CI/CD scaffolding when ready
   agents-cli scaffold enhance . --deployment-target agent_runtime
   ```
   - **Preserved Scaffold Files:** Never hand-edit `agents-cli-manifest.yaml`, `app/fast_api_app.py`, `app/app_utils/a2a.py`, `app/app_utils/services.py`, or `Dockerfile` (these wire up serving, sessions, and the built-in A2A protocol surface).
   - **Agent Runtime Sessions:** When targeting `agent_runtime`, do not hardcode a custom `session_type` in code—Agent Runtime manages `VertexAiSessionService` automatically.

2. **Local Smoke Testing & Playground (`agents-cli run` / `playground`):**
   ```bash
   agents-cli run "Run skill customer-escalation-resolver for Acme Corp" --start-server
   agents-cli playground
   ```

3. **Evaluation vs. Unit Tests (`agents-cli eval` vs. `uv run pytest`):**
   - **`uv run pytest`**: Use strictly for deterministic code contracts (schema validation, token extraction helpers, registry HTTP parsing). **Never** assert on non-deterministic LLM text output in `pytest`.
   - **`agents-cli eval run`**: Use for end-to-end agent behavior, tool trajectory (`load_skill_bundle` $\rightarrow$ `execute_subskill`), and LLM-as-judge quality gates.

4. **Deployment to Vertex AI Agent Runtime (`agents-cli deploy`):**
   ```bash
   # Requires explicit human approval before execution
   agents-cli deploy --project $PROJECT_ID --region us-central1 --no-wait --no-confirm-project
   agents-cli deploy --status
   ```
   - Writes `deployment_metadata.json` containing `remote_agent_engine_id` upon completion.

5. **Publishing to Gemini Enterprise & Fleet Management (`agents-cli publish` & `registry`):**
   ```bash
   # Auto-reads remote_agent_engine_id from deployment_metadata.json
   agents-cli publish gemini-enterprise \
     --app-id "$GE_ENGINE_ID" \
     --display-name "Enterprise Skill Orchestrator" \
     --description "Executes governed Parent Skills and Sub-Skills from the AI Skill Hub" \
     --authorization-id "projects/$PROJECT_NUMBER/locations/global/authorizations/ge-user-auth" \
     --mode adk

   # Inspect registered agents across the project
   agents-cli registry agents list --location global
   ```

## 2. Universal ADK Agent Code Standards
- Export `root_agent` in `agent.py` and `__init__.py`.
- Use dynamic `InstructionProvider` callables (`instruction=build_dynamic_skill_instruction(ctx: ReadonlyContext) -> str`) instead of deploying static per-use-case Reasoning Engines.
- Follow the repository Python style guide (`<= 80` characters per line, single-line sorted imports verified via `ruff check`).

## 3. Per-User Identity & `:streamAssist` Execution
- Always extract the calling Gemini Enterprise user's forwarded OAuth 2.0 token from `callback_context.state` / `tool_context.state` (injected via `authorizationConfig.toolAuthorizations` / `--authorization-id`) before falling back to Application Default Credentials.
- Propagate the user's OAuth token to Discovery Engine `:streamAssist` calls so executions consume the user's GE seat quota and respect their M365/enterprise ACLs.

## 4. Declarative Skills & Sub-Skills (`skills_catalog/`)
- Every `SKILL.md` must include YAML frontmatter (`name`, `description`) and use environment placeholders (`{{ENGINE_ID}}`, `{{DATA_STORE_IDS}}`) rather than hardcoded engine or data store IDs.
- Composite skills in `skills_catalog/composite_skills/` must include a `manifest.json` declaring `required_connectors` and `sub_skills`.
