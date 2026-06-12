resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.vms

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id

  agent {
    enabled = false
  }

  stop_on_destroy = true

  clone {
    vm_id   = proxmox_virtual_environment_vm.template.vm_id
    full    = true
    retries = 8
  }

  cpu {
    cores = coalesce(each.value.cores, var.default_cores)
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = coalesce(each.value.memory, var.default_memory)
  }

  disk {
    datastore_id = var.disk_datastore
    interface    = "scsi0"
    size         = coalesce(each.value.disk_size, var.default_disk_size)
  }

  initialization {
    datastore_id = var.disk_datastore

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.vm_user
      keys     = [trimspace(var.ssh_public_key)]
    }

    upgrade = false
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}
