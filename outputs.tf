output "confidential_app_client_id" {
  description = "Client ID (SCIM name) of the confidential app — used by the workload during token exchange"
  value       = oci_identity_domains_app.confidential_app.name
}

output "confidential_app_id" {
  description = "SCIM ID of the confidential app"
  value       = oci_identity_domains_app.confidential_app.id
}

output "rpst_trust_id" {
  description = "SCIM ID of the RPST Identity Propagation Trust"
  value       = oci_identity_domains_identity_propagation_trust.rpst_trust.id
}

output "rpst_trust_name" {
  description = "Name of the RPST Identity Propagation Trust"
  value       = oci_identity_domains_identity_propagation_trust.rpst_trust.name
}
