# Product Definition: Gemini Enterprise App Deployment Automation

## 1. Product Vision & Summary
**Gemini Enterprise App Deployment Automation** is an automated provisioning and deployment toolkit designed for repeatable, turnkey execution in customer Google Cloud environments. The solution uses a hybrid Infrastructure-as-Code (IaC) approach—leveraging modular **Terraform** resources where supported by the Google Cloud provider (`google` / `google-beta`) and seamlessly bridging provider gaps with authenticated **`curl` REST API** commands against Google Cloud Discovery Engine / Gemini Enterprise endpoints. It delivers a unified, master executable deployment script powered by a single configuration file that customers can run directly in their environment to create and configure the full Gemini Enterprise application suite end-to-end.

## 2. Target Audience & Execution Environment
- **Primary Users:** Customer Cloud Administrators, DevOps / Platform Engineers, and Solutions Engineers executing deployments during customer onboarding or production rollouts.
- **Target Execution Environments:**
  - Google Cloud Shell (`gcloud`, `terraform`, `curl`, and `jq` pre-installed).
  - Standard Linux or macOS admin workstations with Google Cloud SDK and Terraform installed.

## 3. Core Capabilities & Scope
1. **Single-Point Customer Configuration:**
   - A centralized configuration file (e.g., `config.env` / `terraform.tfvars`) where customers define all environment-specific parameters (Project ID, Location/Region, App Display Name, Data Store configs, IAM principals, and Agent endpoints) in one place without modifying logic scripts.
2. **Master Executable Orchestration Script (`deploy.sh`):**
   - Acts as the single runnable entrypoint for the customer.
   - Runs pre-flight checks (validating `gcloud` authentication, active project, required CLI tools, and API enablement).
   - Executes Terraform workflows (`init`, `plan`, `apply`) for supported resources and passes outputs seamlessly into subsequent REST API steps.
   - Executes parameterized, idempotent `curl` commands using `gcloud auth print-access-token` to configure Gemini Enterprise capabilities not yet exposed in Terraform.
3. **Full Gemini Enterprise App Suite Provisioning:**
   - **Foundation & Prerequisites:** Enabling required Google Cloud APIs (`discoveryengine.googleapis.com`, `aiplatform.googleapis.com`, etc.), service accounts, and IAM bindings.
   - **Data Stores & Centralized Common Connectors:** Provisioning and linking app-specific Data Stores alongside a centralized Common Connectors registry (`configs/common_connectors.env`, including Microsoft 365 SharePoint Online, OneDrive, Outlook, and Teams) that is automatically attached (1-to-Many) to every Gemini Enterprise App created or updated.
   - **Gemini Enterprise App / Engine Creation:** Provisioning the Gemini Enterprise (`SOLUTION_TYPE_SEARCH` / `SOLUTION_TYPE_CHAT` / Gemini Enterprise assistant) engine and configuring app-level settings.
   - **IAM, ACLs, Per-App Cloud Identity Groups, Entra ID Entity Sync & Agent Registration:** Provisioning a dedicated Google Cloud Identity group per Gemini Enterprise App (`<GE_APP_ID>-users@<GE_CUSTOMER_DOMAIN>`), synchronizing Microsoft Entra ID users, security groups, and memberships into Google Cloud Identity (`terraform-identity/` and `deploy_identity.sh`) using shared Secret Manager credentials (`m365-connector-credentials`) and a shared custom domain (`mohanrajs.demo.altostrat.com`), revoking broad project-level Discovery Engine user/viewer bindings, enforcing exclusive Engine-level IAM policies (`:setIamPolicy`) so only members of each app's group have access, and registering custom/ADK agents or tools into the Gemini Enterprise app via REST APIs.
4. **Verification & Output Summary:**
   - Post-deployment validation and a clear summary of created resource IDs, endpoints, and console links.

## 4. Key Design Principles
- **Terraform Where Available, `curl` Where Necessary:** Prefer declarative state management via Terraform (`google`/`google-beta`) first; fall back cleanly to well-structured REST API calls via `curl` when API features outpace Terraform provider coverage.
- **Zero-Friction Customer Handoff:** Produce a self-contained, portable script and configuration bundle that requires minimal dependencies (`bash`, `gcloud`, `terraform`, `curl`, `jq`) and no complex runtime installation.
- **Idempotency & Safety:** Ensure both Terraform modules and `curl` API calls handle existing resources gracefully and fail fast with clear error messages on misconfiguration.
