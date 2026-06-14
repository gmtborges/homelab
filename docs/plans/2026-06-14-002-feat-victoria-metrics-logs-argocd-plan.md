---
title: "feat: VictoriaMetrics and VictoriaLogs ArgoCD apps"
type: feat
date: 2026-06-14
origin: docs/brainstorms/2026-06-14-victoria-metrics-logs-argocd-requirements.md
---

# feat: VictoriaMetrics and VictoriaLogs ArgoCD apps

## Summary

Add two ArgoCD `Application` manifests to `argocd/apps/` that deploy the single-node VictoriaMetrics and VictoriaLogs datastores from the `vm` Helm repo, pinned to charts `victoria-metrics-single` 0.40.1 and `victoria-logs-single` 0.13.7. Each deploys into its own namespace with persistence pinned to the Longhorn StorageClass. The stores are bare backends; ingestion (scraping, log shipping) is out of scope (see origin: `docs/brainstorms/2026-06-14-victoria-metrics-logs-argocd-requirements.md`).

---

## Problem Frame

The cluster has no metrics or log retention layer of its own. The repo already deploys adjacent ArgoCD apps the same way (`argocd/apps/metrics-server.yaml`, `cert-manager.yaml`, `longhorn.yaml`), so two new single-source Helm Applications are the natural shape. VictoriaMetrics and VictoriaLogs are picked as resource-light, single-binary stores suited to a homelab. This plan stands up the two stores only — deliberately not the heavier `victoria-metrics-k8s-stack` — and leaves collection to a later change.

---

## Requirements

**VictoriaMetrics**

- R1. A new ArgoCD `Application` at `argocd/apps/victoria-metrics.yaml` deploys the `victoria-metrics-single` chart from `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.40.1`. (origin R1)
- R2. It deploys into the `victoria-metrics` namespace with `CreateNamespace=true`; the Application object itself carries `project: default`, `namespace: argocd`. (origin R2)
- R3. Server persistence is enabled and bound to the `longhorn` StorageClass so metrics data survives pod restarts. (origin R3)

**VictoriaLogs**

- R4. A new ArgoCD `Application` at `argocd/apps/victoria-logs.yaml` deploys the `victoria-logs-single` chart from `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.13.7`. (origin R4)
- R5. It deploys into the `victoria-logs` namespace with `CreateNamespace=true`; the Application object itself carries `project: default`, `namespace: argocd`. (origin R5)
- R6. Server persistence is enabled and bound to the `longhorn` StorageClass so log data survives pod restarts. (origin R6)

**Common**

- R7. Both manifests use the existing single-`source` Helm Application shape (as in `argocd/apps/cert-manager.yaml` / `metrics-server.yaml`); `helm.values` overrides only what persistence requires. (origin R7)
- R8. Both deploy as bare datastores: metrics scrape/relabel and the logs chart's embedded Vector subchart, dashboards, and ingress are left at their chart-default `enabled: false`. (origin scope boundaries)

---

## Key Technical Decisions

- **Pin `server.persistentVolume.storageClassName: longhorn` explicitly rather than relying on the cluster default.** Both charts default `storageClassName: ""`, which binds to the default StorageClass (Longhorn today). Setting it explicitly makes the persistence backing unambiguous and survives a future change to the cluster default. Resolves the origin's deferred storage-class question.
- **Accept chart-default volume sizes and retention.** `victoria-metrics-single` 16Gi, `victoria-logs-single` 10Gi, both `retentionPeriod: 1` (month). Reasonable homelab starting point; bump via values later. Resolves the origin's deferred volume-size question.
- **Two independent Applications applied directly — no app-of-apps wrapper.** Matches the existing `argocd/apps/*.yaml` convention where each Application is applied on its own. Resolves the origin's deferred registration question.
- **Per-app namespaces (`victoria-metrics`, `victoria-logs`).** Consistent with the per-app namespace convention already in use (`longhorn-system`, `cert-manager`, `metallb-system`), rather than a shared `observability` namespace.

---

## Implementation Units

### U1. VictoriaMetrics ArgoCD Application

- **Goal:** A new ArgoCD Application deploys `victoria-metrics-single` 0.40.1 into the `victoria-metrics` namespace with Longhorn-backed persistence.
- **Requirements:** R1, R2, R3, R7, R8
- **Dependencies:** none
- **Files:**
  - `argocd/apps/victoria-metrics.yaml` (create) — `Application` in `namespace: argocd`, `project: default`, single `source` (chart `victoria-metrics-single`, `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.40.1`), `destination` namespace `victoria-metrics`, `syncOptions: [CreateNamespace=true]`.
- **Approach:** Mirror `argocd/apps/metrics-server.yaml` (single source + `helm.values`). Directional values shape:

  ```yaml
  helm:
    values: |
      server:
        persistentVolume:
          enabled: true
          storageClassName: longhorn
  ```
  Leave size at the chart default (16Gi) and scrape/relabel at their default `false`.
- **Patterns to follow:** `argocd/apps/metrics-server.yaml` (single-source `helm.values`); `argocd/apps/longhorn.yaml` for the `CreateNamespace=true` + per-app namespace shape.
- **Test scenarios:**
  - `kubectl apply --dry-run=client -f argocd/apps/victoria-metrics.yaml` parses without error.
  - `targetRevision` equals `0.40.1` and `chart` equals `victoria-metrics-single`.
  - `helm template` of the configured chart+values renders a StatefulSet whose `volumeClaimTemplate` carries `storageClassName: longhorn`.
  - `Covers AE1.` After apply, ArgoCD reports the app Synced/Healthy with the VictoriaMetrics pod Running and its PVC bound to a Longhorn volume.
- **Verification:** ArgoCD app diff/sync applies cleanly; the VictoriaMetrics StatefulSet is Running with a bound Longhorn PVC.

### U2. VictoriaLogs ArgoCD Application

- **Goal:** A new ArgoCD Application deploys `victoria-logs-single` 0.13.7 into the `victoria-logs` namespace with Longhorn-backed persistence.
- **Requirements:** R4, R5, R6, R7, R8
- **Dependencies:** none
- **Files:**
  - `argocd/apps/victoria-logs.yaml` (create) — `Application` in `namespace: argocd`, `project: default`, single `source` (chart `victoria-logs-single`, `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.13.7`), `destination` namespace `victoria-logs`, `syncOptions: [CreateNamespace=true]`.
- **Approach:** Same single-source + `helm.values` shape as U1:

  ```yaml
  helm:
    values: |
      server:
        persistentVolume:
          enabled: true
          storageClassName: longhorn
  ```
  Leave size at the chart default (10Gi); keep the embedded `vector`, `dashboards`, and `ingress` at their default `false`.
- **Patterns to follow:** U1; `argocd/apps/metrics-server.yaml`.
- **Test scenarios:**
  - `kubectl apply --dry-run=client -f argocd/apps/victoria-logs.yaml` parses without error.
  - `targetRevision` equals `0.13.7` and `chart` equals `victoria-logs-single`.
  - `helm template` of the configured chart+values renders a StatefulSet whose `volumeClaimTemplate` carries `storageClassName: longhorn`, with no Vector DaemonSet.
  - `Covers AE2.` After apply, ArgoCD reports the app Synced/Healthy with the VictoriaLogs pod Running and its PVC bound to a Longhorn volume.
- **Verification:** ArgoCD app diff/sync applies cleanly; the VictoriaLogs StatefulSet is Running with a bound Longhorn PVC.

---

## Acceptance Examples

- AE1. VictoriaMetrics syncs healthy
  - **Covers R1, R2, R3.**
  - **Given** the Application is applied to ArgoCD,
  - **When** ArgoCD syncs it,
  - **Then** it reports Synced/Healthy and the VictoriaMetrics pod is Running with a bound Longhorn PVC.
- AE2. VictoriaLogs syncs healthy
  - **Covers R4, R5, R6.**
  - **Given** the Application is applied to ArgoCD,
  - **When** ArgoCD syncs it,
  - **Then** it reports Synced/Healthy and the VictoriaLogs pod is Running with a bound Longhorn PVC.

---

## Scope Boundaries

### Deferred to Follow-Up Work

- Metrics collection (vmagent or other scrapers) — VictoriaMetrics starts empty until something writes to it.
- Log shipping (Vector or `victoria-logs-collector`) — VictoriaLogs starts empty until something ships logs to it.
- Dashboards, alerting, and Grafana wiring.
- Ingress / external exposure of either UI.
- Retention, downsampling, and resource-limit tuning beyond chart defaults.

### Outside this plan's shape

- `victoria-metrics-k8s-stack` and the cluster chart variants — a heavier monitoring suite, not the two single-node stores this plan delivers.

---

## Dependencies / Assumptions

- The `vm` Helm repo (`https://victoriametrics.github.io/helm-charts/`) is reachable; versions 0.40.1 / 0.13.7 were confirmed via `helm search repo vm`.
- Longhorn is installed and exposes a `longhorn` StorageClass; pinning `storageClassName: longhorn` removes any dependency on Longhorn being the cluster default.
- ArgoCD is running and watches `argocd/apps/`; the cluster destination is `https://kubernetes.default.svc`.

---

## Sources & Research

- `helm search repo vm` (after `helm repo update vm`) → `victoria-metrics-single` 0.40.1 (app v1.145.0), `victoria-logs-single` 0.13.7 (app v1.50.0); `victoria-metrics-k8s-stack` 0.83.0 considered and rejected as out of scope.
- `helm show values vm/victoria-metrics-single --version 0.40.1` → `server.persistentVolume.{enabled: true, storageClassName: "", size: 16Gi}`, `server.retentionPeriod: 1`, scrape/relabel default `false`.
- `helm show values vm/victoria-logs-single --version 0.13.7` → `server.persistentVolume.{enabled: true, storageClassName: "", size: 10Gi}`, `server.retentionPeriod: 1`, embedded `vector`/`dashboards`/`ingress` default `false`.
- `argocd/apps/metrics-server.yaml`, `argocd/apps/cert-manager.yaml` — single-source Helm Application + `helm.values` pattern.
- `argocd/apps/longhorn.yaml` — per-app namespace + `CreateNamespace=true` convention; Longhorn as the cluster storage layer.
- Origin requirements: `docs/brainstorms/2026-06-14-victoria-metrics-logs-argocd-requirements.md`.
