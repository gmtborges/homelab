include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../modules/proxmox-vms"
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

inputs = {
  node_name       = "pve"
  image_datastore = "local"
  disk_datastore  = "local-lvm"
  network_bridge  = "vmbr0"
  gateway         = "192.168.1.1"
  dns_servers     = ["192.168.1.1"]
  vm_user         = "debian"
  ssh_public_key  = get_env("PROXMOX_VM_SSH_PUBLIC_KEY")

  vms = {
    "k3s-server"  = { vm_id = 9001, role = "server", ip = "192.168.1.20/24" }
    "k3s-agent-1" = { vm_id = 9002, role = "agent", ip = "192.168.1.21/24" }
    "k3s-agent-2" = { vm_id = 9003, role = "agent", ip = "192.168.1.22/24" }
    "k3s-agent-3" = { vm_id = 9004, role = "agent", ip = "192.168.1.23/24" }
  }
}
