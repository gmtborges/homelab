---
date: 2026-06-14
topic: longhorn-s3-backup
---

# Longhorn on k3s with S3 Backup

## Summary

Update the existing ArgoCD Longhorn application to the latest chart (`1.12.0`) and give it an S3 backup target. A new Terragrunt unit provisions an AWS S3 bucket plus a least-privilege IAM user and access key (same account and region as the Terraform state backend); Longhorn reads those credentials from a Kubernetes Secret applied out-of-band from Terraform's sensitive outputs.

---

## Problem Frame

Longhorn provides distributed block storage for the k3s cluster, but its volumes are only as durable as the nodes that hold them. Without an external backup target, a multi-node failure or a rebuild of the homelab loses persistent data. The repo already keeps Terraform state in AWS S3, so the same account is the natural, low-friction home for off-cluster volume backups. The Longhorn app exists today (`argocd/apps/longhorn.yaml`) pinned at `v1.8.1` with no backup target configured — this brief closes that gap and moves to the current chart in one pass.

---

## Key Decisions

- **Update the existing app in place, don't replace it.** `argocd/apps/longhorn.yaml` already deploys Longhorn at `v1.8.1`; bump its `targetRevision` to `1.12.0` and add backup values rather than introduce a parallel Application.
- **Manual Secret, no secrets operator.** The repo has no sealed-secrets / external-secrets / SOPS tooling. Deliver the backup credentials as an out-of-band `kubectl` Secret created from Terraform outputs — keeps credentials out of git without adding a new operator. Cost: one documented manual step on (re)bootstrap.
- **Isolated Terragrunt unit with its own AWS provider.** The `proxmox-vms` unit stays untouched. The backup infrastructure is a separate unit that shares only the existing S3 state backend (`terraform/root.hcl`), so an AWS resource provider is added without entangling the Proxmox provider.
- **Least-privilege IAM scoped to the one bucket.** A dedicated IAM user for Longhorn — not the state/operator credentials — with a policy limited to that single bucket.

---

## Requirements

**Longhorn deployment**

- R1. The existing Longhorn ArgoCD Application is updated in place to chart `1.12.0` (the latest reported by `helm search repo longhorn/longhorn`), retaining its single-source structure and the `preUpgradeChecker.jobEnabled: false` value.
- R2. Longhorn continues to deploy into the `longhorn-system` namespace with `CreateNamespace=true`.

**S3 backup infrastructure (Terraform)**

- R3. A new Terragrunt unit and module provision an AWS S3 bucket for Longhorn backups in the same account and region as the existing state backend (`us-east-2`), reusing the shared S3 backend defined in `terraform/root.hcl`.
- R4. The bucket blocks all public access and has server-side encryption enabled.
- R5. A dedicated IAM user is created with a least-privilege policy scoped to only that bucket (list the bucket; get/put/delete objects within it) and a programmatic access key.
- R6. The access key id and secret are exposed as sensitive Terraform outputs; no credentials are committed to git.

**Backup wiring and credentials**

- R7. Longhorn's `defaultSettings.backupTarget` is set to the bucket in `s3://<bucket>@<region>/` form, and `defaultSettings.backupTargetCredentialSecret` references a Secret in `longhorn-system`.
- R8. The credential Secret is created out-of-band from the Terraform outputs (holding the access key id and secret) and is never managed by ArgoCD or stored in git.
- R9. The Terraform README documents the sequence: `terragrunt apply` → read sensitive outputs → create the `longhorn-system` Secret → ArgoCD syncs the configured backup target.

---

## Key Flow

- F1. Backup infrastructure bootstrap
  - **Trigger:** Operator runs `terragrunt apply` on the new backup unit.
  - **Actors:** Operator, Terraform/AWS, ArgoCD, Longhorn.
  - **Steps:** Bucket + IAM user + access key are created → Terraform prints the sensitive credential outputs → operator creates the `longhorn-system` Secret from those outputs → ArgoCD syncs Longhorn with the configured `backupTarget` → Longhorn reports the backup target as healthy.
  - **Outcome:** Volumes can be backed up to the S3 bucket.

---

## Acceptance Examples

- AE1. Backup target connects
  - **Covers R7, R8.**
  - **Given** the credential Secret exists with valid keys and `backupTarget` is set,
  - **When** Longhorn evaluates the backup target,
  - **Then** it reports the target as connected/healthy with no authentication error.
- AE2. A volume backup lands in S3
  - **Covers R3, R5.**
  - **Given** a healthy backup target,
  - **When** a volume backup is triggered and completes,
  - **Then** a backup object appears under the bucket and the volume shows a backup in Longhorn.

---

## Scope Boundaries

Deferred for later:

- Recurring backup schedules (Longhorn RecurringJobs) and snapshot policies — this round wires the backup target only.
- Restore / disaster-recovery runbook.
- S3 lifecycle expiration and versioning/retention tuning.
- Adopting a secrets operator (sealed-secrets / external-secrets) to automate the credential Secret.

---

## Dependencies / Assumptions

- Longhorn is not yet deployed with live volumes — the cluster is newly provisioned, so a clean install at `1.12.0` is safe. A populated `1.8.x` install would need a staged minor-by-minor upgrade, which is out of scope here.
- An AWS account and profile with S3 and IAM permissions (the same one backing `gbsoft-homelab-tfstate`), exported via direnv (`AWS_PROFILE`).
- The k3s cluster is reachable with ArgoCD running; `helm` CLI is available (used to confirm the latest chart, `1.12.0`).
- `kubectl` access is available to create the credential Secret.

---

## Outstanding Questions (Deferred to Planning)

- Exact bucket, IAM user, policy, and Secret names — follow the existing `gbsoft-homelab-*` convention.
- Whether to enable bucket versioning and a lifecycle rule to expire old backups.
- Final IAM action list (e.g., whether `s3:GetBucketLocation` is needed alongside list/get/put/delete).
- Secret key names and whether `AWS_ENDPOINTS` is set (left empty for native AWS S3).

---

## Sources / Research

- `helm search repo longhorn/longhorn --versions` → latest chart `1.12.0` (app `v1.12.0`); existing app pins `v1.8.1`.
- `argocd/apps/longhorn.yaml` — current Longhorn Application (single source, `preUpgradeChecker.jobEnabled: false`).
- `argocd/apps/cert-manager.yaml`, `argocd/apps/metallb.yaml` — ArgoCD Application patterns (`helm.valuesObject` vs `helm.values`, multi-source layout).
- `terraform/root.hcl` — shared S3 state backend (`gbsoft-homelab-tfstate`, `us-east-2`) and generated provider block.
- `terraform/proxmox-vms/` and `terraform/modules/proxmox-vms/` — existing unit/module layout to mirror for the new backup unit.
