# OCI IAM Workload Identity Federation — RPST Token Exchange (Terraform)

Automates the setup of OCI **Resource Principal Session Token (RPST)** exchange using Terraform, deployable via OCI Resource Manager or the Terraform CLI.

> **Companion blog:** [Automating OCI Workload Identity Federation for RPST with Terraform and Resource Manager](https://www.ateam-oracle.com) *(coming soon)*  
> **Related blog (UPST):** [Automating OCI Workload Identity Federation with Terraform and Resource Manager](https://www.ateam-oracle.com/automating-oci-workload-identity-federation-with-terraform-and-resource-manager)

---

## Overview

OCI Workload Identity Federation (WIF) allows external workloads — such as GitHub Actions pipelines — to exchange third-party OIDC/JWT tokens for short-lived OCI session tokens, eliminating the need for long-lived API keys.

This repo automates the **RPST variant** of that flow. Unlike UPST (which issues a token that acts as an OCI *user*), RPST issues a token that acts as an OCI *resource principal* — appropriate for non-human workloads that should not be tied to a service user identity.

| Aspect | UPST (User Principal Session Token) | RPST (Resource Principal Session Token) |
|---|---|---|
| **What it represents** | A specific OCI service user — a non-interactive IAM identity you create and manage | An ephemeral workload identity — no OCI user required |
| **Requires OCI user?** | Yes — you must create a service user in OCI IAM and assign it to groups for policy authorization | No — identity is created dynamically at token exchange time |
| **Max token lifetime** | 1 hour (minimum of: IDP token remaining duration, API-supplied value, 60 minutes) | Up to 12 hours (configurable using `rpst_exp` parameter) |
| **Claim propagation** | Not supported — policies evaluate against the service user's group memberships | Supported — up to 3 claims from the incoming JWT can be embedded into the RPST and used in policy conditions |
| **IAM policy authorization** | Policies grant permissions to the service user's group memberships | Policies can evaluate specific claim values embedded in the token — such as a GitHub repository, an AWS role ARN, or any custom claim from the incoming JWT |
| **Best for** | Workloads that need to impersonate a known OCI service user; scenarios where group-based access control is preferred | Automated pipelines, CI/CD, and cross-cloud workloads where no static OCI identity should exist |

---

## Architecture

```
External Workload (e.g. GitHub Actions)
        │
        │  1. Obtain OIDC JWT from IdP
        ▼
OCI Token Exchange API  ◄──────────────────────────────────────┐
        │                                                       │
        │  2. Submit JWT + client_id/client_secret              │
        │     + impersonating_resource string                   │
        │                                                       │
        ▼                                                    Identity
Identity Propagation Trust (trust.tf)          ◄──────── Propagation
  - Validates JWT signature via JWKS endpoint               Trust
  - Matches issuer                                       (this repo)
  - Verifies impersonating_resource claim
  - Propagates up to 3 claims into RPST
        │
        │  3. Issues short-lived RPST
        ▼
Confidential App (app.tf)
  - Authenticates the calling workload
  - client_id / client_secret bound to the trust
        │
        │  4. Workload uses RPST to call OCI APIs
        ▼
OCI APIs (with Resource Principal authorization)
```

---

## Prerequisites

- OCI Identity Domain administrator privileges
- Terraform ≥ 1.3 **or** OCI Resource Manager access

---

## Files

| File | Purpose |
|---|---|
| `provider.tf` | OCI Terraform provider configuration |
| `variables.tf` | All input variable declarations with descriptions |
| `terraform.tfvars` | Your environment-specific values (copy from example) |
| `terraform_tfvars.example` | Example values — safe to commit |
| `app.tf` | Creates the Confidential Application in the Identity Domain |
| `trust.tf` | Creates the Identity Propagation Trust with RPST settings |
| `outputs.tf` | Exposes client ID, trust ID, and trust name after apply |

---

## Configuration

Copy the example file and fill in your values:

```bash
cp terraform_tfvars.example terraform.tfvars
```

### Key Variables

| Variable | Description | Example |
|---|---|---|
| `idcs_endpoint` | Identity Domain URL | `https://idcs-xxxx.identity.oraclecloud.com:443` |
| `region` | OCI region | `us-ashburn-1` |
| `confidential_app_name` | Display name for the OAuth app | `rpst-confidential-app` |
| `trust_name` | Unique name for the propagation trust | `rpst-trust` |
| `issuer` | External IdP issuer URI | `https://token.actions.githubusercontent.com` |
| `public_key_endpoint` | JWKS URL of the external IdP | `https://token.actions.githubusercontent.com/.well-known/jwks` |
| `impersonating_resource` | Logical workload identifier (not an OCID) | `ref_github` |
| `claim_propagations` | Claims to forward into the RPST (max 3) | `["ext_repository", "ext_actor", "ext_repository_id"]` |

> **`impersonating_resource`** is a customer-defined string label — not an OCI OCID. The calling workload must pass this exact same string in the token exchange request. Think of it as a handshake value that identifies which workload is performing the exchange.

> **`claim_propagations`** accepts a maximum of 3 claim names. These claims are read from the incoming JWT and forwarded into the issued RPST, making them available for policy decisions or auditing downstream.

---

## Terraform Execution Flow

This Terraform project automates Steps 1 and 2 below. Steps 3–6 are performed by the workload at runtime and are documented here for completeness.

### Step 1 — Create the Confidential Application (`app.tf`)

A confidential OAuth application is created in the Identity Domain. This app authenticates the workload during token exchange using `client_credentials`. The Terraform output `confidential_app_client_id` gives you the client ID.

After `apply`, retrieve the **client secret** from the OCI Console: **Identity & Security → Identity → Domains → your domain → Integrated applications → your app → OAuth configuration**.

### Step 2 — Create the Identity Propagation Trust (`trust.tf`)

The trust is created with:
- `subject_type = "Resource"` — issues RPST (not UPST)
- `type = "JWT"` — accepts JWT tokens from the external IdP
- `allow_impersonation = true` — required for RPST exchange
- `issuer` — the external IdP's issuer URI (e.g. `https://token.actions.githubusercontent.com`)
- `public_key_endpoint` — the IdP's JWKS URL used to validate the incoming JWT signature
- `impersonating_resource` — a customer-defined label the workload must pass at exchange time to match this trust
- `claim_propagations` — up to 3 claim names from the incoming JWT to copy into the RPST (prefixed with `ext_` in the issued token)
- Binding to the confidential app created in Step 1 via `oauth_clients`

> **Note on claim names:** Claims listed in `claim_propagations` must be specified **with** the `ext_` prefix (e.g. `ext_repository`, `ext_workflow_ref`, `ext_actor`). These same `ext_`-prefixed names are what OCI embeds into the RPST and what IAM policies evaluate against.

### Step 3 — Workload Obtains a JWT from Its IdP

The external workload authenticates with its local identity provider and receives a JWT. For GitHub Actions this happens automatically on each workflow run. The available claims depend on the IdP — for GitHub Actions, common claims include `repository`, `workflow_ref`, `actor`, and `environment`.

The claim names configured in `claim_propagations` must match what the incoming JWT actually contains.

### Step 4 — Workload Calls the OCI Token Exchange Endpoint

The workload generates an ephemeral public/private key pair, then submits the JWT to the OCI token endpoint. The public key is embedded into the issued RPST as a proof-of-possession claim.

```bash
curl --location 'https://idcs-<domain>.identity.oraclecloud.com/oauth2/v1/token' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --header 'Authorization: Basic <BASE64_CLIENTID_SECRET>' \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:token-exchange' \
  --data-urlencode 'requested_token_type=urn:oci:token-type:oci-rpst' \
  --data-urlencode 'public_key=<EPHEMERAL_PUBLIC_KEY>' \
  --data-urlencode 'subject_token_type=jwt' \
  --data-urlencode 'subject_token=<IDP_JWT>' \
  --data-urlencode 'res_type=ref_github' \
  --data-urlencode 'rpst_exp=9000'
```

| Parameter | Description |
|---|---|
| `requested_token_type` | `urn:oci:token-type:oci-rpst` for RPST; use `urn:oci:token-type:oci-upst` for UPST |
| `res_type` | Must exactly match the `impersonating_resource` string set in the Propagation Trust |
| `public_key` | The workload's ephemeral public key — embedded in the RPST for proof-of-possession |
| `rpst_exp` | Optional. Desired RPST lifetime in seconds. Maximum is `43200` (12 hours) |
| `Authorization` | Base64-encoded `client_id:client_secret` from the confidential app |

### Step 5 — OCI Validates and Issues the RPST

OCI validates the JWT signature against the configured JWKS endpoint, confirms the caller is an authorized OAuth client, and copies the configured claims into the RPST with the `ext_` prefix. The RPST represents an ephemeral identity OCI calls `identityfederateddomainapp` — created on the fly, not stored in IAM.

### Step 6 — Workload Signs API Requests and OCI Evaluates Policies

The workload uses the RPST and its private key to sign OCI API requests using OCI's standard HTTP Signature authentication. OCI verifies the signature using the public key embedded in the RPST (proof-of-possession), then evaluates the configured IAM policies against the `identityfederateddomainapp` principal.

#### Writing IAM Policies for RPST Workloads

RPST policies use the `identityfederateddomainapp` principal type. The `ext_` claims embedded in the RPST are available as policy conditions:

```
allow any-user to <verb> <resource-type> in <scope>
where all {
  request.principal.type = 'identityfederateddomainapp',
  request.principal.<ext_claim> = '<value>'
}
```

**Example 1 — Allow a specific GitHub repository:**

```
allow any-user to manage object-family in compartment my-compartment
where all {
  request.principal.type = 'identityfederateddomainapp',
  request.principal.ext_repository = 'octo-org/infra-deploy'
}
```

**Example 2 — Restrict to a specific workflow file and branch:**

```
allow any-user to read secret-bundles in compartment prod-secrets
where all {
  request.principal.type = 'identityfederateddomainapp',
  request.principal.ext_repository = 'octo-org/app-repo',
  request.principal.ext_workflow_ref = 'octo-org/app-repo/.github/workflows/deploy.yml@refs/heads/main'
}
```

**Example 3 — Custom claim from any IdP:**

```
allow any-user to use vaults in compartment shared-infra
where all {
  request.principal.type = 'identityfederateddomainapp',
  request.principal.ext_tenant_id = 'acme-corp-prod'
}
```

> **Claim propagation from GitHub Actions (example):**
>
> | Incoming JWT claim | Propagated into RPST as |
> |---|---|
> | `repository` | `ext_repository` |
> | `workflow_ref` | `ext_workflow_ref` |
> | `actor` | `ext_actor` |
> | `environment` | `ext_environment` |
>
> The same pattern applies to any IdP. Propagate whatever claims your IdP includes — role ARN, project ID, tenant identifier, or any custom claim.

All token exchanges and API calls are captured in OCI Audit, linked to the ephemeral `identityfederateddomainapp` identity.

---

## Deploying with OCI Resource Manager

1. In the OCI Console, navigate to **Developer Services → Resource Manager → Stacks**.
2. Click **Create Stack** and upload the folder containing these Terraform files.
3. Click **Next** and fill in the required variables.
4. Click **Apply**.

---

## Outputs

After a successful `apply`:

| Output | Description |
|---|---|
| `confidential_app_client_id` | Client ID of the confidential app (used in token exchange) |
| `confidential_app_id` | SCIM ID of the confidential app |
| `rpst_trust_id` | SCIM ID of the Identity Propagation Trust |
| `rpst_trust_name` | Name of the Identity Propagation Trust |

---

## References

- [OCI IAM Workload Identity Federation (Product Blog)](https://blogs.oracle.com/cloud-infrastructure/oci-iam-workload-identity-federation)
- [Workload Identity Federation — A-Team Chronicles](https://www.ateam-oracle.com/workload-identity-federation)
- [Automating OCI WIF with Terraform (UPST version)](https://www.ateam-oracle.com/automating-oci-workload-identity-federation-with-terraform-and-resource-manager)
- [GitHub Actions & OCI: Secure OIDC Token Exchange](https://www.ateam-oracle.com/github-actions-oci-a-guide-to-secure-oidc-token-exchange)

---

## Author

**Ramesh Balajepalli**  
Master Principal Cloud Architect, Oracle Cloud Infrastructure  
[A-Team Chronicles](https://www.ateam-oracle.com/authors/ramesh-balajepalli)
