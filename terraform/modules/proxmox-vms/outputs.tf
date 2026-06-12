output "server" {
  description = "k3s server node name to IP."
  value = {
    for name, vm in var.vms : name => split("/", vm.ip)[0] if vm.role == "server"
  }
}

output "agents" {
  description = "k3s agent node names to IPs."
  value = {
    for name, vm in var.vms : name => split("/", vm.ip)[0] if vm.role == "agent"
  }
}

output "hosts_ini" {
  description = "Ansible inventory snippet for playbooks/hosts.ini."
  value = format(
    "[server]\n%s\n\n[agents]\n%s\n",
    join("\n", [for name, vm in var.vms : "${name} ansible_host=${split("/", vm.ip)[0]}" if vm.role == "server"]),
    join("\n", [for name, vm in var.vms : "${name} ansible_host=${split("/", vm.ip)[0]}" if vm.role == "agent"]),
  )
}
