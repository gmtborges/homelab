remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket       = "gbsoft-homelab-tfstate"
    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOT
    provider "proxmox" {
      endpoint = "https://192.168.1.10:8006/"
      insecure = true
    }
  EOT
}
