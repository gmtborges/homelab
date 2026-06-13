# k3s (Ansible)

Installs and configures a single-server k3s cluster on the Debian VMs provisioned
by `terraform/proxmox-vms/` — one server (`192.168.1.20`) and three agents
(`.21`/`.22`/`.23`) — pinned to `v1.36.1+k3s1`. The run ends at a workload-ready
cluster plus a kubeconfig fetched to this machine. ArgoCD bootstrap and Longhorn
are separate later phases.

Roles:

- `node_prep` — installs `qemu-guest-agent` and disables sshd password auth on all nodes.
- `k3s_server` — installs the control-plane server with servicelb, Traefik, and metrics-server disabled.
- `k3s_agent` — installs and joins the three agents using the server's runtime node token.

`site.yml` runs them in order, hands the node token from the server to the agents,
and fetches the kubeconfig.

## Prerequisites

- The `terraform/proxmox-vms/` layer is applied and the four VMs answer SSH as
  user `debian` with your injected key (`ssh-add` the matching private key, or
  configure it in `~/.ssh/config`).
- `ansible` available (`ansible --version`).
- Internet egress from the nodes to `https://get.k3s.io`.

## Inventory

`hosts.ini` carries the `[server]` / `[agents]` groups. Regenerate it from the
Terragrunt outputs whenever the fleet changes:

```sh
cd ../terraform/proxmox-vms
terragrunt output -raw hosts_ini > ../../playbooks/hosts.ini
```

The connection user (`debian`) and the pinned k3s version live in
`group_vars/all.yml`.

## Run

```sh
cd playbooks
ansible-playbook site.yml
```

A second run is a no-op (no reinstall, no re-join).

## Kubeconfig

On success the cluster kubeconfig is written to `playbooks/kubeconfig` (gitignored)
with the API address rewritten to `192.168.1.20`:

```sh
kubectl --kubeconfig playbooks/kubeconfig get nodes
```

Override the destination with `-e kubeconfig_local_path=/path/to/kubeconfig`.

## Follow-ups

- The guest agent installed by `node_prep` stays inert in Proxmox until the VM
  layer sets `agent.enabled = true` and re-applies.
- Longhorn (and its node prerequisites), MetalLB, cert-manager, metrics-server,
  and the ArgoCD bootstrap are deployed in later phases via `argocd/`.
