include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  region = "us-east-2"
}

terraform {
  source = "../modules/longhorn-backup"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "aws" {
      region = "${local.region}"
    }
  EOT
}

inputs = {
  bucket_name   = "gbsoft-homelab-longhorn-backup"
  iam_user_name = "gbsoft-homelab-longhorn-backup"
  region        = local.region
}
