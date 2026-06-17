# Exchanges an external IdP JWT for an OCI RPST token.
# The external IdP (e.g. GitHub Actions) issues a JWT; this trust
# validates it via the JWKS endpoint and issues an RPST with
# subject_type = Resource.

resource "oci_identity_domains_identity_propagation_trust" "rpst_trust" {

  idcs_endpoint = var.idcs_endpoint
  name          = var.trust_name
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]

  # External IdP issuer (e.g. GitHub Actions OIDC provider)
  issuer = var.issuer

  # Incoming token type
  type = "JWT"

  # Resource principal — the resulting RPST represents a resource, not a user
  subject_type = "Resource"

  # JWKS endpoint of the external IdP for signature validation
  public_key_endpoint = var.public_key_endpoint

  # A customer-defined string identifying the calling workload.
  # The workload passes this same value when requesting token exchange.
  impersonating_resource = var.impersonating_resource

  # Claims from the incoming JWT to forward into the resulting RPST.
  # Maximum 3 claims allowed.
  claim_propagations = var.claim_propagations

  active              = true
  allow_impersonation = true
  description         = var.trust_description

  # Bind this trust to the confidential app created in app.tf.
  # oauthClients expects the app's SCIM "name" attribute.
  oauth_clients = [oci_identity_domains_app.confidential_app.name]
}
