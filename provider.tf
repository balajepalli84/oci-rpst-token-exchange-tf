terraform {
  required_providers {
    oci = {
      source = "hashicorp/oci"
    }
  }
}

provider "oci" {
  auth   = "InstancePrincipal"
  region = var.region
}
