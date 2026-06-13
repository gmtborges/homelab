variable "node_name" {
  description = "Proxmox node that hosts the VMs."
  type        = string
}

variable "image_datastore" {
  description = "Datastore holding the imported cloud image (must allow the 'import' content type)."
  type        = string
  default     = "local"
}

variable "disk_datastore" {
  description = "Datastore backing VM disks and cloud-init drives."
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Proxmox network bridge the VMs attach to."
  type        = string
  default     = "vmbr0"
}

variable "gateway" {
  description = "IPv4 default gateway for the VMs."
  type        = string
  default     = "192.168.1.1"
}

variable "dns_servers" {
  description = "DNS resolvers passed to cloud-init."
  type        = list(string)
  default     = ["192.168.1.1"]
}

variable "vm_user" {
  description = "Default cloud-init user created on each VM."
  type        = string
  default     = "debian"
}

variable "ssh_public_key" {
  description = "SSH public key injected into the cloud-init user."
  type        = string

  validation {
    condition     = trimspace(var.ssh_public_key) != ""
    error_message = "ssh_public_key must be non-empty; set PROXMOX_VM_SSH_PUBLIC_KEY before applying."
  }
}

variable "debian_image_file" {
  description = "File name of the manually imported Debian genericcloud image (content type 'import')."
  type        = string
  default     = "debian-13-genericcloud-amd64.qcow2"
}

variable "template_vm_id" {
  description = "VM ID for the cloud-init template built from the image."
  type        = number
  default     = 9000
}

variable "default_cores" {
  description = "Default vCPU count when a VM entry omits it."
  type        = number
  default     = 2
}

variable "default_memory" {
  description = "Default memory in MB when a VM entry omits it."
  type        = number
  default     = 4096
}

variable "default_disk_size" {
  description = "Default disk size in GB when a VM entry omits it."
  type        = number
  default     = 40
}

variable "vms" {
  description = "Map of VM name to its definition (vm_id, role, static CIDR IP, optional per-VM sizing)."
  type = map(object({
    vm_id     = number
    role      = string
    ip        = string
    cores     = optional(number)
    memory    = optional(number)
    disk_size = optional(number)
  }))
}
