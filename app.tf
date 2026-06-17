# Creates a confidential application in the Identity Domain.
# The client_id and client_secret from this app are used by the
# workload when performing RPST token exchange.

resource "oci_identity_domains_app" "confidential_app" {
  idcs_endpoint = var.idcs_endpoint
  display_name  = var.confidential_app_name

  schemas = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  is_oauth_client = true
  client_type     = "confidential"
  active          = true

  # Token exchange is handled by the Identity Propagation Trust, not the app.
  # The app only needs client_credentials to authenticate the workload.
  allowed_grants = ["client_credentials"]
}
