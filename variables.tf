variable "idcs_endpoint" {
  description = "Identity Domain URL (e.g. https://idcs-xxxx.identity.oraclecloud.com)"
  type        = string
}

variable "region" {
  description = "OCI region (e.g. us-ashburn-1)"
  type        = string
  default     = "us-ashburn-1"
}

# ── Confidential App ────────────────────────────────────────────────────────

variable "confidential_app_name" {
  description = "Display name for the confidential application in the Identity Domain"
  type        = string
  default     = "rpst-confidential-app"
}

# ── Trust Configuration ─────────────────────────────────────────────────────

variable "trust_name" {
  description = "Unique name for the Identity Propagation Trust"
  type        = string
  default     = "rpst-trust"
}

variable "trust_description" {
  description = "Description for the Identity Propagation Trust"
  type        = string
  default     = "RPST-based Identity Propagation Trust"
}

variable "issuer" {
  description = <<-EOT
    The issuer claim of the external Identity Provider whose JWT tokens will be
    exchanged for OCI RPST tokens.
    Example: "https://token.actions.githubusercontent.com" for GitHub Actions.
  EOT
  type        = string
}

variable "public_key_endpoint" {
  description = <<-EOT
    The JWKS (JSON Web Key Set) URL of the external Identity Provider.
    Used to validate the signature of the incoming JWT token.
    Example: "https://token.actions.githubusercontent.com/.well-known/jwks" for GitHub Actions.
  EOT
  type        = string
}

variable "impersonating_resource" {
  description = <<-EOT
    A customer-defined string identifier for the workload performing token exchange.
    This is NOT an OCID — it is a logical label you choose (e.g. "ref_github", "my-pipeline").
    The calling workload MUST pass this exact same string value when requesting a token exchange.
  EOT
  type        = string
}

variable "claim_propagations" {
  description = <<-EOT
    List of claim names from the incoming JWT to forward into the resulting RPST.
    Maximum 3 claims allowed.
    NOTE: The defaults below are examples for GitHub Actions — set to the claims your workload needs.
  EOT
  type    = list(string)
  default = ["ext_workflow_ref", "ext_repository", "ext_actor"]

  validation {
    condition     = length(var.claim_propagations) <= 3
    error_message = "claim_propagations supports a maximum of 3 entries."
  }
}
