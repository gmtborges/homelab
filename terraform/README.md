# Proxmox VMs (Terragrunt)

Provisions four Debian 13 VMs on the Proxmox host at `192.168.1.10:8006` — one
k3s server (`192.168.1.20`) and three agents (`.21`/`.22`/`.23`) — and exposes
their IPs for the later Ansible/k3s phase. State lives in AWS S3.

Layout:

- `root.hcl` — Terragrunt root: S3 remote state + generated `bpg/proxmox` provider.
- `proxmox-vms/terragrunt.hcl` — the unit; defines the VM map and host inputs.
- `modules/proxmox-vms/` — reusable module: image download, template VM, `for_each` clone, outputs.

## Prerequisites

- Proxmox VE 9.x reachable at `192.168.1.10:8006`.
- Terraform >= 1.11 (or OpenTofu >= 1.10) and Terragrunt.
- direnv.
- AWS S3 bucket `gbsoft-homelab-tfstate` (region `us-east-2`) and a profile with access to it. The bucket must exist before the first apply (one-time bootstrap).
- On the `local` datastore, enable the `Import` content type: Datacenter -> Storage -> `local` -> Content -> enable **Import**. Required for the image `disk.import_from` step.

## Proxmox API token and role

Run on the Proxmox node as `root@pam`.

1. Create a dedicated user:

   ```sh
   pveum user add terraform@pve
   ```

2. Create the role with the exact privileges the provider needs:

   ```sh
   pveum role add Terraform -privs "Datastore.Allocate Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit Sys.Audit Sys.AccessNetwork SDN.Use VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Migrate VM.PowerMgmt"
   ```

   Why these privileges:

   - `Datastore.Allocate*` / `Datastore.AllocateTemplate` — download the cloud image and create the template + clone disks.
   - `Sys.AccessNetwork` — gates the `query-url-metadata` API call the image download makes. On PVE < 8.2 (no `Sys.AccessNetwork`), use `Sys.Audit` + `Sys.Modify` on `/` instead.
   - `SDN.Use` — attach VM NICs to the `vmbr0` bridge (governed by the `localnetwork` SDN zone).
   - `VM.*` — create, clone, configure (including cloud-init), migrate, and power the VMs. Note: `VM.Monitor` is not a valid privilege on PVE 9.x — omit it.

3. Create an API token without privilege separation so it inherits the user's role:

   ```sh
   pveum user token add terraform@pve provider --privsep 0
   ```

   Copy the secret shown once. The full token string is `terraform@pve!provider=<uuid>`.

4. Assign the role on `/` — this propagates to nodes, storage, and SDN zones:

   ```sh
   pveum aclmod / -user terraform@pve -role Terraform
   ```

   If the token uses privilege separation (`--privsep 1`, the web UI default), grant the token its own ACL as well:

   ```sh
   pveum acl modify / -token 'terraform@pve!provider' -role Terraform
   ```

To add a privilege later, the API names the exact one in `Permission check failed (<path>, <Privilege>)`. Append it without retyping the list:

```sh
pveum role modify Terraform -privs "<Privilege>" -append 1
```

## Environment

Secrets and host-specific values are exported via direnv. From the repo root:

```sh
cp .envrc.example .envrc      # .envrc is gitignored
# edit .envrc: PROXMOX_VE_API_TOKEN, PROXMOX_VM_SSH_PUBLIC_KEY, AWS_PROFILE
direnv allow
```

Confirm the host inputs in `proxmox-vms/terragrunt.hcl` match your environment before applying: `node_name`, `image_datastore`, `disk_datastore`, `network_bridge`, `gateway`, and the `vms` map (VM IDs 9001-9004, IPs `.20`-`.23`).

## Apply

```sh
cd terraform/proxmox-vms
terragrunt apply
```

Outputs:

- `server` / `agents` — node name to IP, grouped by role.
- `hosts_ini` — ready-to-paste Ansible inventory:

  ```sh
  terragrunt output -raw hosts_ini > ../../playbooks/hosts.ini
  ```

The k3s install runs from `playbooks/` via Ansible as a separate, later phase; this layer's job ends at reachable VMs plus the IP outputs.
