"""Unified CLI entrypoint (`gedeploy`) for Customer Onboarding & Direct Terraform/Cloud API Deployment.

Executes Terraform stacks (`infra/stacks/*`, `infra/terraform-*`) and Google Cloud,
Discovery Engine, Cloud Identity, Microsoft Entra ID, ServiceNow, and Atlassian APIs
directly from the CLI — with zero web server or middleware API layer required.

1. List All Core Onboarding Steps (Steps 1-7) & Optional Add-On Modules:
   gedeploy --list

2. Step-by-Step Core Onboarding Guide (7 Core Steps):
   Step 1: gedeploy --gcp-foundation --config infra/configs/cymbal-onboard.env
   Step 2: gedeploy --google-admin --config infra/configs/cymbal-onboard.env
   Step 3: gedeploy --entra-bootstrap --config infra/configs/cymbal-onboard.env
   Step 4: gedeploy --directory-sync --config infra/configs/cymbal-onboard.env
   Step 5: gedeploy --identity-terraform --config infra/configs/cymbal-onboard.env
   Step 6: gedeploy --m365-connectors --config infra/configs/cymbal-onboard.env
   Step 7: gedeploy --ge-apps --config infra/configs/cymbal-onboard.env

3. 1-Command Full Core Onboarding (Runs Core Steps 1-7 by Default):
   gedeploy --onboard --config infra/configs/cymbal-onboard.env --dry-run
   gedeploy --onboard --config infra/configs/cymbal-onboard.env

4. Optional Add-On Parameters (Universal Agent, Skill Sharing, ServiceNow, Atlassian & Sandbox CSV):
   # Include optional add-ons during full onboarding:
   gedeploy --onboard --with-universal-agent --with-skill-sharing --config infra/configs/cymbal-onboard.env
   gedeploy --onboard --with-servicenow --with-atlassian --config infra/configs/cymbal-onboard.env

   # Or run any optional module individually at any time:
   gedeploy --universal-agent --config infra/configs/cymbal-onboard.env
   gedeploy --skill-sharing --config infra/configs/cymbal-onboard.env
   gedeploy --servicenow-bootstrap --config infra/configs/cymbal-onboard.env
   gedeploy --servicenow-connector --config infra/configs/cymbal-onboard.env
   gedeploy --atlassian-bootstrap --config infra/configs/cymbal-onboard.env
   gedeploy --atlassian-connectors --config infra/configs/cymbal-onboard.env
   gedeploy --seed-demo-csv --config infra/configs/cymbal-onboard.env --members-csv infra/configs/cymbal_users_groups.csv
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
import importlib.metadata
import json
import os
import pathlib
from pathlib import Path
import shutil
import subprocess
import sys
from typing import Any, Sequence


@dataclass(frozen=True)
class OnboardingModuleSpec:
    """Metadata for each named infrastructure & API deployment module in `gedeploy`."""

    name: str
    cli_flag: str
    legacy_alias: str
    title: str
    cloud_apis_and_terraform: str
    underlying_script: str
    default_enabled: bool = True


ONBOARDING_MODULES: tuple[OnboardingModuleSpec, ...] = (
    OnboardingModuleSpec(
        name="gcp-foundation",
        cli_flag="--gcp-foundation",
        legacy_alias="--step-0c",
        title="GCP APIs & Versioned Terraform State Bucket",
        cloud_apis_and_terraform=(
            "gcloud services enable (14 APIs: Discovery Engine, Cloud Identity, "
            "Admin SDK, Secret Manager, Vertex AI, Agent Registry, Cloud DNS) + "
            "gs://<customer>-ge-tfstate"
        ),
        underlying_script="infra/onboard_customer.sh --gcp-foundation",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="google-admin",
        cli_flag="--google-admin",
        legacy_alias="--step-0b",
        title="Google Admin Console, Domain DNS TXT Verification & SAML SSO Profile",
        cloud_apis_and_terraform=(
            "Admin SDK Directory API + Google Site Verification API + Cloud DNS TXT + "
            "Cloud Identity Inbound SAML SSO Profile API"
        ),
        underlying_script="infra/deploy_google_admin_bootstrap.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="entra-bootstrap",
        cli_flag="--entra-bootstrap",
        legacy_alias="--step-0a",
        title="Microsoft Entra ID OAuth App (49 Scopes) + SAML 2.0 Gallery App",
        cloud_apis_and_terraform=(
            "Terraform Stack 00 (infra/stacks/00-entra-bootstrap: hashicorp/azuread + "
            "hashicorp/google) + Microsoft Graph API + GCP Secret Manager"
        ),
        underlying_script="infra/deploy_entra_bootstrap.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="servicenow-bootstrap",
        cli_flag="--servicenow-bootstrap",
        legacy_alias="--step-0d",
        title="Optional: ServiceNow Instance Bootstrap (Integration User, Roles, OAuth 2.0 & Secret Sync)",
        cloud_apis_and_terraform=(
            "ServiceNow Table REST API (sys_user, sys_user_has_role, oauth_entity) + "
            "GCP Secret Manager"
        ),
        underlying_script="infra/deploy_servicenow_bootstrap.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="atlassian-bootstrap",
        cli_flag="--atlassian-bootstrap",
        legacy_alias="--step-0e",
        title="Optional: Atlassian Cloud Bootstrap (Tenant Cloud ID, OAuth 2.0 3LO & Secret Sync)",
        cloud_apis_and_terraform=(
            "Atlassian Cloud Tenant Info API + Jira/Confluence REST API v3 + "
            "GCP Secret Manager"
        ),
        underlying_script="infra/deploy_atlassian_bootstrap.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="directory-sync",
        cli_flag="--directory-sync",
        legacy_alias="--step-1a",
        title="GCP Directory Sync Configuration & GE UserStore License Sync",
        cloud_apis_and_terraform=(
            "Cloud Identity Directory Sync API + Discovery Engine v1alpha userStores "
            "License Config API"
        ),
        underlying_script="infra/deploy_gcp_directory_sync.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="identity-terraform",
        cli_flag="--identity-terraform",
        legacy_alias="--step-1b",
        title="Stack 01: Cloud Identity Per-App Group Nesting & SAML Handshake",
        cloud_apis_and_terraform=(
            "Terraform Stack 01 (infra/stacks/01-identity-foundation) + "
            "Cloud Identity Groups & Inbound SAML Credentials API"
        ),
        underlying_script="infra/deploy_identity.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="seed-demo-csv",
        cli_flag="--seed-demo-csv",
        legacy_alias="--step-1c",
        title="Optional: Sandbox CSV Group Membership Seeding",
        cloud_apis_and_terraform=(
            "Cloud Identity Groups Memberships REST API (v1/groups/*/memberships)"
        ),
        underlying_script="infra/sync_group_members_from_csv.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="m365-connectors",
        cli_flag="--m365-connectors",
        legacy_alias="--step-2",
        title="Stack 03: Shared M365 Connectors (SharePoint, OneDrive, Outlook, Teams)",
        cloud_apis_and_terraform=(
            "Terraform Stack 03 (infra/stacks/03-m365-connectors) + Discovery Engine "
            "v1alpha DataConnector API (FEDERATED + ACTIONS)"
        ),
        underlying_script="infra/deploy_m365.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="servicenow-connector",
        cli_flag="--servicenow-connector",
        legacy_alias="--step-2b",
        title="Optional Stack 03B: Shared ServiceNow Connector (KB, Incidents, Catalog & Actions)",
        cloud_apis_and_terraform=(
            "Terraform Stack 03B (infra/terraform-servicenow) + Discovery Engine "
            "v1alpha ServiceNow DataConnector API"
        ),
        underlying_script="infra/deploy_servicenow.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="atlassian-connectors",
        cli_flag="--atlassian-connectors",
        legacy_alias="--step-2c",
        title="Optional Stack 03C: Shared Atlassian Connectors (Jira Cloud, Confluence Cloud & Actions)",
        cloud_apis_and_terraform=(
            "Terraform Stack 03C (infra/terraform-atlassian) + Discovery Engine "
            "v1alpha Jira & Confluence DataConnector API"
        ),
        underlying_script="infra/deploy_atlassian.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="ge-apps",
        cli_flag="--ge-apps",
        legacy_alias="--step-3",
        title="Stack 02: Departmental Gemini Enterprise Apps (16-Point Master Template)",
        cloud_apis_and_terraform=(
            "Terraform Stack 02 (infra/stacks/02-ge-app-instance) + Discovery Engine "
            "v1alpha Engine, WidgetConfig, ACL, Model Armor & Observability APIs"
        ),
        underlying_script="infra/create_app_from_template.sh + infra/scripts/configure_ge_app.sh",
        default_enabled=True,
    ),
    OnboardingModuleSpec(
        name="universal-agent",
        cli_flag="--agent-publish",
        legacy_alias="--step-4",
        title="Optional: Agent Publishing — Deploy & Pin ADK Agents across Customer GE Apps",
        cloud_apis_and_terraform=(
            "Vertex AI ReasoningEngine API (agents-cli deploy) + Discovery Engine "
            "v1alpha Authorizations & Assistant Agents API (defaultPinned: true)"
        ),
        underlying_script="infra/publish_universal_agent.sh",
        default_enabled=False,
    ),
    OnboardingModuleSpec(
        name="skill-sharing",
        cli_flag="--skill-publish",
        legacy_alias="--step-5",
        title="Optional: Skill Publishing — 6-Rubric Benchmark Gate, GCS Upload & Multi-App Skill Sharing",
        cloud_apis_and_terraform=(
            "Discovery Engine :streamAssist Evaluation API + GCS Skill Registry + "
            "GCP Agent Registry API (skillgp)"
        ),
        underlying_script="infra/publish_m365_skills.sh",
        default_enabled=False,
    ),
)

_ALIAS_MAP: dict[str, str] = {}
for _mod in ONBOARDING_MODULES:
    _ALIAS_MAP[_mod.name.upper()] = _mod.name
    _ALIAS_MAP[_mod.cli_flag.lstrip("-").upper()] = _mod.name
    _ALIAS_MAP[_mod.legacy_alias.lstrip("-").upper()] = _mod.name
    _ALIAS_MAP[_mod.legacy_alias.replace("--step-", "").upper()] = _mod.name
_ALIAS_MAP["CLOUD-IDENTITY-GROUPS"] = "identity-terraform"
_ALIAS_MAP["AGENT-PUBLISHING"] = "universal-agent"
_ALIAS_MAP["UNIVERSAL-AGENT"] = "universal-agent"
_ALIAS_MAP["SKILL-PUBLISHING"] = "skill-sharing"
_ALIAS_MAP["SKILL-SHARING"] = "skill-sharing"
_ALIAS_MAP["1"] = "directory-sync,identity-terraform"


def normalize_module_names(raw_items: Sequence[str]) -> list[str]:
    """Resolves a list/CSV of module names or legacy codes to canonical module names."""
    resolved: list[str] = []
    valid_names = [m.name for m in ONBOARDING_MODULES]
    for raw in raw_items:
        for token in str(raw).split(","):
            cleaned = token.strip().lstrip("-").replace("_", "-").upper()
            if not cleaned:
                continue
            mapped = _ALIAS_MAP.get(cleaned)
            if not mapped:
                raise ValueError(
                    f"Unknown onboarding module '{token.strip()}'. "
                    f"Valid module names: {', '.join(valid_names)}"
                )
            for part in mapped.split(","):
                if part not in resolved:
                    resolved.append(part)
    return resolved


def _repo_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def _infra_root() -> pathlib.Path:
    repo = _repo_root()
    if (repo / "onboard_customer.sh").is_file():
        return repo
    return repo / "infra"


def _resolve_config_path(config_arg: str, customer_name: str) -> str:
    """Resolves `--config` relative to cwd, repo root, or `infra/`."""
    repo = _repo_root()
    infra = _infra_root()
    if config_arg:
        candidates = [
            pathlib.Path(config_arg).expanduser(),
            repo / config_arg,
            infra / config_arg,
        ]
        for c in candidates:
            if c.is_file():
                return str(c.resolve())
        return config_arg
    for base in (infra, repo):
        default_cfg = base / "configs" / f"{customer_name}-onboard.env"
        if default_cfg.is_file():
            return str(default_cfg.resolve())
    return ""


def _print_modules_table(as_json: bool = False) -> None:
    core_modules = [m for m in ONBOARDING_MODULES if m.default_enabled]
    optional_modules = [m for m in ONBOARDING_MODULES if not m.default_enabled]
    if as_json:
        payload = {
            "total": len(ONBOARDING_MODULES),
            "core_steps_count": len(core_modules),
            "optional_addons_count": len(optional_modules),
            "modules": [asdict(m) for m in ONBOARDING_MODULES],
        }
        print(json.dumps(payload, indent=2))
        return

    print("=" * 122)
    print(
        f" gedeploy — Step-by-Step Core Onboarding (Steps 1-{len(core_modules)}) & Optional Add-On Modules (Total: {len(ONBOARDING_MODULES)})"
    )
    print("=" * 122)
    print(
        " A. CORE STEP-BY-STEP ONBOARDING MODULES (Enabled by default in `gedeploy --onboard`):"
    )
    print("-" * 122)
    print(
        f" {'Step':<8} {'CLI Option':<24} {'Module Name':<22} {'Direct Terraform Stack / Cloud APIs':<40} {'Title'}"
    )
    print("-" * 122)
    for idx, m in enumerate(core_modules, start=1):
        stack_short = (
            m.cloud_apis_and_terraform[:37] + "..."
            if len(m.cloud_apis_and_terraform) > 40
            else m.cloud_apis_and_terraform
        )
        print(
            f" {f'Step {idx}':<8} {m.cli_flag:<24} {m.name:<22} {stack_short:<40} {m.title}"
        )

    print("-" * 122)
    print(
        " B. OPTIONAL ADD-ON MODULES (Opt-in via `--with-universal-agent`, `--with-skill-sharing`, `--with-servicenow`, `--with-atlassian`, or individual flag):"
    )
    print("-" * 122)
    print(
        f" {'Add-On':<8} {'CLI Option':<24} {'Module Name':<22} {'Direct Terraform Stack / Cloud APIs':<40} {'Title'}"
    )
    print("-" * 122)
    for idx, m in enumerate(optional_modules, start=1):
        stack_short = (
            m.cloud_apis_and_terraform[:37] + "..."
            if len(m.cloud_apis_and_terraform) > 40
            else m.cloud_apis_and_terraform
        )
        print(
            f" {f'Opt {idx}':<8} {m.cli_flag:<24} {m.name:<22} {stack_short:<40} {m.title}"
        )
    print("=" * 122)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gedeploy",
        description=(
            "gedeploy — Direct Terraform & Cloud API Deployment CLI for Enterprise "
            "Customer Onboarding (Zero Web Server / API Middleware Required)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""Examples:
  # 1. List all 7 Core Onboarding Steps & 7 Optional Add-On Modules
  gedeploy --list

  # 2. Step-by-Step Core Onboarding Guide (Steps 1 to 7)
  gedeploy --gcp-foundation     --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --google-admin       --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --entra-bootstrap    --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --directory-sync     --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --identity-terraform --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --m365-connectors    --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --ge-apps            --config infra/configs/cymbal-onboard.env --dry-run

  # 3. 1-Command Full Core Onboarding (Runs Core Steps 1 to 7 by Default)
  gedeploy --onboard --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --onboard --config infra/configs/cymbal-onboard.env

  # 4. Optional Add-On Parameters (Universal Agent, Skill Sharing, ServiceNow, Atlassian & Sandbox CSV)
  gedeploy --onboard --with-universal-agent --with-skill-sharing --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --onboard --with-servicenow --with-atlassian --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --universal-agent      --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --skill-sharing        --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --servicenow-bootstrap --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --servicenow-connector --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --atlassian-bootstrap  --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --atlassian-connectors --config infra/configs/cymbal-onboard.env --dry-run
  gedeploy --seed-demo-csv        --config infra/configs/cymbal-onboard.env --members-csv infra/configs/cymbal_users_groups.csv --dry-run
""",
    )

    # ------------------------------------------------------------------
    # Group 1: Discovery Options
    # ------------------------------------------------------------------
    disc_group = parser.add_argument_group("Module Discovery Options")
    disc_group.add_argument(
        "-l",
        "--list",
        "--steps",
        "--list-steps",
        dest="list_modules",
        action="store_true",
        help="List the 7 Core Onboarding Steps and 7 Optional Add-On Modules with their Terraform stacks & Cloud APIs",
    )

    # ------------------------------------------------------------------
    # Group 2: Core Onboarding Step Flags (Steps 1 to 7)
    # ------------------------------------------------------------------
    mod_group = parser.add_argument_group(
        "Core Step-by-Step Onboarding Options (Steps 1-7, enabled by default in --onboard)"
    )
    mod_group.add_argument(
        "--onboard",
        "--all",
        dest="onboard_all",
        action="store_true",
        help="Run all 7 Core Onboarding Steps end-to-end (combine with --with-universal-agent, --with-skill-sharing, --with-servicenow, --with-atlassian for optional add-ons)",
    )
    for mod in ONBOARDING_MODULES:
        if not mod.default_enabled:
            continue
        dest_name = f"mod_{mod.name.replace('-', '_')}"
        extra_flags = [mod.cli_flag, mod.legacy_alias]
        if mod.name == "identity-terraform":
            extra_flags.insert(1, "--cloud-identity-groups")
        mod_group.add_argument(
            *extra_flags,
            dest=dest_name,
            action="store_true",
            help=f"{mod.title} [{mod.cloud_apis_and_terraform}]",
        )
    mod_group.add_argument(
        "--module",
        "--step",
        dest="explicit_module",
        metavar="MODULE_NAME",
        type=str,
        help="Run a single onboarding module by name (e.g. gcp-foundation, entra-bootstrap, m365-connectors, ge-apps)",
    )
    mod_group.add_argument(
        "--only",
        "--only-modules",
        "--only-steps",
        "--only-phases",
        dest="only_modules",
        metavar="CSV",
        type=str,
        help="Comma-separated list of named modules to execute (e.g. gcp-foundation,entra-bootstrap,m365-connectors,ge-apps)",
    )
    mod_group.add_argument(
        "--skip",
        "--skip-modules",
        "--skip-steps",
        "--skip-phases",
        dest="skip_modules",
        metavar="CSV",
        type=str,
        help="Comma-separated list of named modules to skip",
    )

    # ------------------------------------------------------------------
    # Group 3: Optional Add-On Modules (Agent Publishing, Skill Publishing, ServiceNow, Atlassian & Sandbox CSV)
    # ------------------------------------------------------------------
    opt_group = parser.add_argument_group(
        "Optional Add-On Parameters (Agent Publishing, Skill Publishing, ServiceNow, Atlassian & Sandbox CSV — Disabled by Default)"
    )
    opt_group.add_argument(
        "--with-agent-publish",
        "--with-universal-agent",
        "--enable-agent-publish",
        "--enable-universal-agent",
        dest="with_universal_agent",
        action="store_true",
        help="Enable optional Agent Publishing (--agent-publish / --universal-agent)",
    )
    opt_group.add_argument(
        "--with-skill-publish",
        "--with-skill-sharing",
        "--enable-skill-publish",
        "--enable-skill-sharing",
        dest="with_skill_sharing",
        action="store_true",
        help="Enable optional Skill Publishing (--skill-publish / --skill-sharing)",
    )
    opt_group.add_argument(
        "--with-servicenow",
        "--enable-servicenow",
        dest="with_servicenow",
        action="store_true",
        help="Enable optional ServiceNow bootstrap (--servicenow-bootstrap) + ServiceNow connector (--servicenow-connector)",
    )
    opt_group.add_argument(
        "--with-atlassian",
        "--enable-atlassian",
        dest="with_atlassian",
        action="store_true",
        help="Enable optional Atlassian Cloud bootstrap (--atlassian-bootstrap) + Jira/Confluence connectors (--atlassian-connectors)",
    )
    for mod in ONBOARDING_MODULES:
        if mod.default_enabled:
            continue
        dest_name = f"mod_{mod.name.replace('-', '_')}"
        extra_flags = [mod.cli_flag, mod.legacy_alias]
        if mod.name == "universal-agent":
            extra_flags.insert(1, "--universal-agent")
        elif mod.name == "skill-sharing":
            extra_flags.insert(1, "--skill-sharing")
        opt_group.add_argument(
            *extra_flags,
            dest=dest_name,
            action="store_true",
            help=f"{mod.title} [{mod.cloud_apis_and_terraform}]",
        )

    # ------------------------------------------------------------------
    # Group 4: Customer, Identity, Connector & App Parameters
    # ------------------------------------------------------------------
    cfg_group = parser.add_argument_group(
        "Customer, Cloud Identity, Connector & App Configuration Options"
    )
    cfg_group.add_argument(
        "--config",
        type=str,
        default="",
        help="Path to onboarding `.env` file (default: infra/configs/<customer>-onboard.env)",
    )
    cfg_group.add_argument(
        "--customer-name",
        type=str,
        default="cymbal",
        help="Customer short name / prefix (default: cymbal)",
    )
    cfg_group.add_argument(
        "--customer-domain",
        type=str,
        default="",
        help="Verified corporate identity domain (e.g. cymbal.com)",
    )
    cfg_group.add_argument(
        "--gcp-project-id",
        type=str,
        default="",
        help="Target Google Cloud Project ID (e.g. cymbal-ge-prod)",
    )
    cfg_group.add_argument(
        "--gcp-region",
        type=str,
        default="",
        help="Target GCP Region for Vertex AI Reasoning Engine & GCS State (default: us-central1)",
    )
    cfg_group.add_argument(
        "--entra-tenant-id",
        "--tenant-id",
        dest="entra_tenant_id",
        type=str,
        default="",
        help="Microsoft Entra ID Tenant UUID",
    )
    cfg_group.add_argument(
        "--dns-project-id",
        type=str,
        default="",
        help="Cloud DNS GCP Project ID (defaults to --gcp-project-id)",
    )
    cfg_group.add_argument(
        "--dns-zone-name",
        type=str,
        default="",
        help="Cloud DNS Managed Zone name for automated domain TXT verification",
    )
    cfg_group.add_argument(
        "--entra-mode",
        choices=["terraform", "az-graph"],
        default="",
        help="Entra bootstrap mode: terraform (Stack 00) or az-graph (default: terraform)",
    )
    cfg_group.add_argument(
        "--servicenow-instance-uri",
        type=str,
        default="",
        help="[Optional ServiceNow] Instance URL for --servicenow-bootstrap / --servicenow-connector",
    )
    cfg_group.add_argument(
        "--servicenow-admin-user",
        type=str,
        default="",
        help="[Optional ServiceNow] Admin username for --servicenow-bootstrap",
    )
    cfg_group.add_argument(
        "--servicenow-admin-password",
        type=str,
        default="",
        help="[Optional ServiceNow] Admin password for --servicenow-bootstrap (or export SN_ADMIN_PASSWORD)",
    )
    cfg_group.add_argument(
        "--atlassian-instance-uri",
        type=str,
        default="",
        help="[Optional Atlassian] Cloud Site URL for --atlassian-bootstrap / --atlassian-connectors",
    )
    cfg_group.add_argument(
        "--atlassian-instance-id",
        type=str,
        default="",
        help="[Optional Atlassian] Tenant Cloud ID (auto-discovered if omitted)",
    )
    cfg_group.add_argument(
        "--atlassian-admin-email",
        type=str,
        default="",
        help="[Optional Atlassian] Admin Email for --atlassian-bootstrap / --atlassian-connectors",
    )
    cfg_group.add_argument(
        "--atlassian-client-id",
        type=str,
        default="",
        help="[Optional Atlassian] OAuth 2.0 (3LO) Client ID",
    )
    cfg_group.add_argument(
        "--atlassian-client-secret",
        type=str,
        default="",
        help="[Optional Atlassian] OAuth 2.0 (3LO) Client Secret",
    )
    cfg_group.add_argument(
        "--atlassian-api-token",
        type=str,
        default="",
        help="[Optional Atlassian] API Token for --atlassian-bootstrap verification",
    )
    cfg_group.add_argument(
        "--members-csv",
        type=str,
        default="",
        help="[Optional CSV] CSV path for --seed-demo-csv sandbox group membership seeding",
    )
    cfg_group.add_argument(
        "--target-apps",
        type=str,
        default="",
        help="Comma-separated list of GE App IDs for --ge-apps (default: all 4 departmental apps)",
    )
    cfg_group.add_argument(
        "--skip-reasoning-engine-deploy",
        action="store_true",
        help="In --universal-agent, only register/pin existing ReasoningEngine without redeploying",
    )
    cfg_group.add_argument(
        "--tf-state-bucket",
        type=str,
        default="",
        help="Remote GCS Terraform state bucket name (default: <customer>-ge-tfstate)",
    )

    # ------------------------------------------------------------------
    # Group 5: Execution Mode Options
    # ------------------------------------------------------------------
    exec_group = parser.add_argument_group("Execution Mode & Output Options")
    exec_group.add_argument(
        "--dry-run",
        "--plan",
        dest="dry_run",
        action="store_true",
        help="Preview Terraform plans & Cloud API calls without mutating remote state",
    )
    exec_group.add_argument(
        "--apply",
        action="store_true",
        help="Execute Terraform apply & Cloud API mutations (default when --dry-run is not passed)",
    )
    exec_group.add_argument(
        "--json",
        action="store_true",
        help="Emit structured JSON summary of the execution",
    )
    exec_group.add_argument(
        "--check-workstation",
        "--doctor",
        dest="check_workstation",
        action="store_true",
        help="Verify workstation CLI binaries, Terraform, and Python modules required for Core Steps and Optional Add-Ons",
    )

    return parser


def _run_workstation_check(as_json: bool = False) -> int:
    cli_checks = [
        ("python3", [sys.executable, "--version"], True, "Core Steps 1-7 & Optional Modules (>= 3.11)"),
        ("gcloud", ["gcloud", "--version"], True, "Core Steps 1-7 (Google Cloud SDK >= 470.0.0)"),
        ("az", ["az", "--version"], True, "Core Steps 3, 4, 6 (Microsoft Azure CLI >= 2.55.0)"),
        ("terraform", ["terraform", "--version"], True, "Core Steps 3, 5, 6, 7 & Optional Connectors (>= 1.5.0)"),
        ("jq", ["jq", "--version"], True, "Core Steps 1-7 & Optional Modules (>= 1.6)"),
        ("curl", ["curl", "--version"], True, "Core Steps 1-7 & Optional Modules (>= 7.70)"),
        ("zip", ["zip", "-v"], True, "Optional --skill-sharing bundle packaging"),
        ("uv", ["uv", "--version"], False, "Optional --universal-agent (Python package manager)"),
        ("agents-cli", ["agents-cli", "--version"], False, "Optional --universal-agent (Vertex AI ReasoningEngine deploy)"),
    ]

    cli_results: list[dict[str, Any]] = []
    for name, ver_cmd, required_core, used_for in cli_checks:
        bin_path = shutil.which(name) if name != "python3" else sys.executable
        version_str = ""
        if bin_path:
            try:
                proc = subprocess.run(ver_cmd, capture_output=True, text=True, timeout=5, check=False)
                raw = (proc.stdout or proc.stderr or "").strip().splitlines()
                version_str = raw[0].strip() if raw else "installed"
            except Exception:
                version_str = "installed"
        cli_results.append(
            {
                "name": name,
                "installed": bool(bin_path),
                "path": bin_path or "",
                "version": version_str,
                "required_for_core": required_core,
                "purpose": used_for,
            }
        )

    venv_py = _repo_root() / ".venv" / "bin" / "python"
    py_packages = [
        ("google-auth", "Optional --skill-sharing & --universal-agent (Google ADC & OAuth)"),
        ("requests", "Optional --skill-sharing (Discovery Engine v1alpha REST client)"),
        ("urllib3", "Optional --skill-sharing (HTTP retry & connection pooling)"),
        ("google-adk", "Optional --universal-agent (Google Agent Development Kit runtime)"),
        ("google-cloud-aiplatform", "Optional --universal-agent (Vertex AI ReasoningEngine SDK)"),
        ("a2a-sdk", "Optional --universal-agent (Agent-to-Agent protocol server)"),
        ("gcsfs", "Optional --universal-agent (GCS SKILL.md bundle loader)"),
        ("httpx", "Optional --universal-agent & Web Portal (:streamAssist async client)"),
        ("pydantic", "Optional --universal-agent & Web Portal (Schema validation)"),
        ("fastapi", "Optional Governance Web Portal Backend"),
    ]

    pkg_results: list[dict[str, Any]] = []
    for pkg_name, purpose in pkg_packages_iter(py_packages, venv_py):
        pkg_results.append(pkg_name_entry(pkg_name, purpose))

    if as_json:
        print(
            json.dumps(
                {
                    "python_executable": sys.executable,
                    "venv_python": str(venv_py) if venv_py.exists() else "",
                    "cli_binaries": cli_results,
                    "python_packages": pkg_results,
                },
                indent=2,
            )
        )
        return 0

    print("=" * 112)
    print(" gedeploy Workstation Readiness Check (CLIs, Terraform & Python Modules)")
    print("=" * 112)
    print("\n1. CLI BINARIES & SYSTEM TOOLS:")
    print(f"  {'STATUS':<10} {'BINARY':<14} {'VERSION / PATH':<42} {'USED FOR'}")
    print("  " + "-" * 108)
    for item in cli_results:
        status = "[OK]" if item["installed"] else ("[MISSING]" if item["required_for_core"] else "[OPTIONAL]")
        ver_display = (item["version"] or item["path"] or "not found")[:40]
        print(f"  {status:<10} {item['name']:<14} {ver_display:<42} {item['purpose']}")

    print("\n2. PYTHON RUNTIME & MODULES:")
    print(f"  - Core Steps 1-7 (`gedeploy`): Python stdlib only ({sys.version.split()[0]}) -> [OK] Zero pip packages required")
    print(f"  - Project Virtualenv (`.venv`): {venv_py if venv_py.exists() else 'Not created yet (run: python3 -m venv .venv)'}")
    print(f"\n  {'STATUS':<10} {'PYTHON PACKAGE':<26} {'VERSION':<16} {'USED FOR'}")
    print("  " + "-" * 108)
    for pkg in pkg_results:
        status = "[OK]" if pkg["installed"] else "[OPTIONAL]"
        ver = pkg["version"] or "not installed"
        print(f"  {status:<10} {pkg['package']:<26} {ver:<16} {pkg['purpose']}")
    print("=" * 112)
    return 0


def pkg_packages_iter(
    py_packages: list[tuple[str, str]], venv_py: Path
) -> list[tuple[dict[str, Any], str]]:
    venv_versions: dict[str, str] = {}
    agent_venv_py = (
        _repo_root() / "agents" / "universal_skill_orchestrator" / ".venv" / "bin" / "python"
    )
    for py_bin in (venv_py, agent_venv_py):
        if py_bin.exists():
            try:
                proc = subprocess.run(
                    [
                        str(py_bin),
                        "-c",
                        "import importlib.metadata as m, json; print(json.dumps({d.metadata['Name'].lower(): d.version for d in m.distributions() if d.metadata.get('Name')}))",
                    ],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=False,
                )
                if proc.returncode == 0 and proc.stdout.strip():
                    for k, v in json.loads(proc.stdout.strip()).items():
                        venv_versions.setdefault(k, v)
            except Exception:
                pass

    out: list[tuple[dict[str, Any], str]] = []
    for pkg_name, purpose in py_packages:
        ver = venv_versions.get(pkg_name.lower(), "")
        if not ver:
            try:
                ver = importlib.metadata.version(pkg_name)
            except Exception:
                ver = ""
        out.append(({"package": pkg_name, "installed": bool(ver), "version": ver}, purpose))
    return out


def pkg_name_entry(entry: dict[str, Any], purpose: str) -> dict[str, Any]:
    return {
        "package": entry["package"],
        "installed": entry["installed"],
        "version": entry["version"],
        "purpose": purpose,
    }


def _collect_selected_modules(args: argparse.Namespace) -> list[str]:
    selected: list[str] = []
    if args.explicit_module:
        selected.extend(normalize_module_names([args.explicit_module]))
    for mod in ONBOARDING_MODULES:
        attr = f"mod_{mod.name.replace('-', '_')}"
        if getattr(args, attr, False) and mod.name not in selected:
            selected.append(mod.name)
    if args.only_modules:
        for m in normalize_module_names([args.only_modules]):
            if m not in selected:
                selected.append(m)
    if not args.onboard_all:
        if getattr(args, "with_servicenow", False):
            for m in ("servicenow-bootstrap", "servicenow-connector"):
                if m not in selected:
                    selected.append(m)
        if getattr(args, "with_atlassian", False):
            for m in ("atlassian-bootstrap", "atlassian-connectors"):
                if m not in selected:
                    selected.append(m)
        if getattr(args, "with_universal_agent", False):
            if "universal-agent" not in selected:
                selected.append("universal-agent")
        if getattr(args, "with_skill_sharing", False):
            if "skill-sharing" not in selected:
                selected.append("skill-sharing")
    return selected


def _build_onboard_command(
    args: argparse.Namespace,
    selected_modules: list[str],
    skip_modules: list[str],
) -> list[str]:
    script_path = _infra_root() / "onboard_customer.sh"
    cmd: list[str] = [str(script_path)]

    resolved_cfg = _resolve_config_path(args.config, args.customer_name)
    if resolved_cfg:
        cmd.extend(["--config", resolved_cfg])

    if getattr(args, "with_servicenow", False):
        cmd.append("--with-servicenow")
    if getattr(args, "with_atlassian", False):
        cmd.append("--with-atlassian")
    if getattr(args, "with_universal_agent", False):
        cmd.append("--with-universal-agent")
    if getattr(args, "with_skill_sharing", False):
        cmd.append("--with-skill-sharing")

    if selected_modules:
        cmd.extend(["--only", ",".join(selected_modules)])
        if "seed-demo-csv" in selected_modules:
            cmd.append("--seed-demo-csv")

    if skip_modules:
        cmd.extend(["--skip", ",".join(skip_modules)])

    if args.customer_name:
        cmd.extend(["--customer-name", args.customer_name])
    if args.customer_domain:
        cmd.extend(["--customer-domain", args.customer_domain])
    if args.gcp_project_id:
        cmd.extend(["--gcp-project-id", args.gcp_project_id])
    if args.gcp_region:
        cmd.extend(["--gcp-region", args.gcp_region])
    if args.entra_tenant_id:
        cmd.extend(["--entra-tenant-id", args.entra_tenant_id])
    if args.dns_project_id:
        cmd.extend(["--dns-project-id", args.dns_project_id])
    if args.dns_zone_name:
        cmd.extend(["--dns-zone-name", args.dns_zone_name])
    if args.entra_mode:
        cmd.extend(["--entra-mode", args.entra_mode])
    if args.servicenow_instance_uri:
        cmd.extend(["--servicenow-instance-uri", args.servicenow_instance_uri])
    if args.servicenow_admin_user:
        cmd.extend(["--servicenow-admin-user", args.servicenow_admin_user])
    if args.servicenow_admin_password:
        cmd.extend(["--servicenow-admin-password", args.servicenow_admin_password])
    if args.atlassian_instance_uri:
        cmd.extend(["--atlassian-instance-uri", args.atlassian_instance_uri])
    if args.atlassian_instance_id:
        cmd.extend(["--atlassian-instance-id", args.atlassian_instance_id])
    if args.atlassian_admin_email:
        cmd.extend(["--atlassian-admin-email", args.atlassian_admin_email])
    if args.atlassian_client_id:
        cmd.extend(["--atlassian-client-id", args.atlassian_client_id])
    if args.atlassian_client_secret:
        cmd.extend(["--atlassian-client-secret", args.atlassian_client_secret])
    if args.atlassian_api_token:
        cmd.extend(["--atlassian-api-token", args.atlassian_api_token])
    if args.members_csv:
        cmd.extend(["--members-csv", args.members_csv])
    if args.target_apps:
        cmd.extend(["--target-apps", args.target_apps])
    if args.skip_reasoning_engine_deploy:
        cmd.append("--skip-reasoning-engine-deploy")
    if args.tf_state_bucket:
        cmd.extend(["--tf-state-bucket", args.tf_state_bucket])
    if args.dry_run:
        cmd.append("--dry-run")

    return cmd


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.list_modules:
        _print_modules_table(as_json=args.json)
        return 0

    if getattr(args, "check_workstation", False):
        return _run_workstation_check(as_json=args.json)

    try:
        selected_modules = _collect_selected_modules(args)
        skip_modules = (
            normalize_module_names([args.skip_modules])
            if args.skip_modules
            else []
        )
    except ValueError as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    if not args.onboard_all and not selected_modules:
        parser.print_help()
        return 0

    cmd = _build_onboard_command(
        args=args,
        selected_modules=selected_modules,
        skip_modules=skip_modules,
    )

    env = os.environ.copy()
    env["CLOUDSDK_METRICS_ENVIRONMENT"] = "geapphub"

    if args.json:
        proc = subprocess.run(
            cmd,
            cwd=str(_infra_root()),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        if selected_modules:
            executed = selected_modules
        else:
            opt_enabled: set[str] = set()
            if getattr(args, "with_servicenow", False):
                opt_enabled.update({"servicenow-bootstrap", "servicenow-connector"})
            if getattr(args, "with_atlassian", False):
                opt_enabled.update({"atlassian-bootstrap", "atlassian-connectors"})
            if getattr(args, "with_universal_agent", False):
                opt_enabled.add("universal-agent")
            if getattr(args, "with_skill_sharing", False):
                opt_enabled.add("skill-sharing")
            executed = [
                m.name
                for m in ONBOARDING_MODULES
                if (m.default_enabled or m.name in opt_enabled)
                and m.name not in skip_modules
            ]
        summary: dict[str, Any] = {
            "status": "SUCCEEDED" if proc.returncode == 0 else "FAILED",
            "return_code": proc.returncode,
            "customer_name": args.customer_name,
            "dry_run": bool(args.dry_run),
            "executed_modules": executed,
            "skipped_modules": skip_modules,
            "command": cmd,
            "output": proc.stdout,
        }
        if proc.stderr:
            summary["stderr"] = proc.stderr
        print(json.dumps(summary, indent=2))
        return proc.returncode

    proc = subprocess.run(
        cmd,
        cwd=str(_repo_root() / "infra"),
        env=env,
        check=False,
    )
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
