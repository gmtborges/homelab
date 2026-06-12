resource "proxmox_virtual_environment_download_file" "debian" {
  content_type = "import"
  datastore_id = var.image_datastore
  node_name    = var.node_name
  url          = var.debian_image_url
  file_name    = "debian-13-genericcloud-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "template" {
  name      = "debian-13-template"
  node_name = var.node_name
  vm_id     = var.template_vm_id
  template  = true
  started   = false

  agent {
    enabled = false
  }

  cpu {
    cores = var.default_cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.default_memory
  }

  disk {
    datastore_id = var.disk_datastore
    interface    = "scsi0"
    import_from  = proxmox_virtual_environment_download_file.debian.id
    size         = var.default_disk_size
  }

  initialization {
    datastore_id = var.disk_datastore

    ip_config {
      ipv4 {
        address = "dhcp"
      }
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
