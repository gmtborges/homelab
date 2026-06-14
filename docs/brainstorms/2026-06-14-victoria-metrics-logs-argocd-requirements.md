---
date: 2026-06-14
topic: victoria-metrics-logs-argocd
---

# VictoriaMetrics and VictoriaLogs on k3s via ArgoCD

## Summary

Add two ArgoCD `Application` manifests to `argocd/apps/` that deploy the single-node VictoriaMetrics and VictoriaLogs datastores from the `vm` Helm repo, pinned to the latest charts (`victoria-metrics-single` 0.40.1, `victoria-logs-single` 0.13.7). Each deploys into its own namespace with persistence backed by Longhorn, following the existing one-app-per-file pattern. The stores are deployed as bare backends; ingestion (scraping, log shipping) is a separate later change.

---

## Problem Frame

The cluster has no metrics or log retention layer of its own. The repo already carries Helm repos for adjacent observability tooling (`grafana`, `prometheus-community`, `vector`), so a metrics TSDB and a logs store are the missing durable backends those tools eventually feed. VictoriaMetrics and VictoriaLogs are chosen as resource-light, single-binary stores that suit a homelab. This round stands up the two stores only — deliberately not the full `victoria-metrics-k8s-stack` (operator, vmagent, vmalert, Alertmanager, Grafana, exporters), which is a heavier monitoring suite rather than "the datastores." Collection is wired separately once the stores exist.

---

## Key Decisions

- **Single-node charts, not cluster or k8s-stack.** `victoria-metrics-single` and `victoria-logs-single` match the homelab scale and the literal scope ("victoria-metrics and victoria-logs", not a monitoring stack). Cluster variants and the bundled k8s-stack are explicitly out.
- **Two independent Applications, one per file.** One manifest per component (`argocd/apps/victoria-metrics.yaml`, `argocd/apps/victoria-logs.yaml`), mirroring the existing per-app layout (`longhorn.yaml`, `cert-manager.yaml`), rather than a single combined or app-of-apps manifest.
- **Separate namespace per app.** `victoria-metrics` and `victoria-logs` get their own namespaces with `CreateNamespace=true`, consistent with the per-app namespace convention already in use (`longhorn-system`, `cert-manager`, `metallb-system`).
- **Pin to the latest charts at authoring time.** `targetRevision` is pinned to the exact chart versions reported by `helm search repo vm` (0.40.1 / 0.13.7), matching how every existing app pins a concrete chart version rather than tracking a range.
- **Persistence on Longhorn.** Both stores enable a PVC bound to Longhorn (the cluster's default StorageClass), so retained data survives pod rescheduling.

---

## Requirements

**VictoriaMetrics**

- R1. A new ArgoCD `Application` (`argocd/apps/victoria-metrics.yaml`) deploys the `victoria-metrics-single` chart from `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.40.1`.
- R2. It deploys into the `victoria-metrics` namespace with `CreateNamespace=true`, `project: default`, `namespace: argocd` on the Application object.
- R3. Server persistence is enabled and backed by Longhorn so metrics data is durable across pod restarts.

**VictoriaLogs**

- R4. A new ArgoCD `Application` (`argocd/apps/victoria-logs.yaml`) deploys the `victoria-logs-single` chart from `repoURL: https://victoriametrics.github.io/helm-charts/`, `targetRevision: 0.13.7`.
- R5. It deploys into the `victoria-logs` namespace with `CreateNamespace=true`, `project: default`, `namespace: argocd` on the Application object.
- R6. Server persistence is enabled and backed by Longhorn so log data is durable across pod restarts.

**Common**

- R7. Both manifests follow the existing single-`source` Helm Application shape (as in `cert-manager.yaml` / `metrics-server.yaml`); chart-specific overrides use `helm.values` / `helm.valuesObject` only where needed to enable persistence or set storage size.

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

Deferred for later:

- Metrics collection (vmagent or other scrapers) — VictoriaMetrics starts empty until something writes to it.
- Log shipping (a collector such as Vector or `victoria-logs-collector`) — VictoriaLogs starts empty until something ships logs to it.
- Dashboards, alerting, and Grafana wiring.
- Ingress / external exposure of either UI.
- Retention, downsampling, and resource-limit tuning beyond chart defaults.

Outside this round's shape:

- `victoria-metrics-k8s-stack` and the cluster chart variants — a different product than the two single-node stores requested.

---

## Dependencies / Assumptions

- The `vm` Helm repo (`https://victoriametrics.github.io/helm-charts/`) is reachable; chart versions 0.40.1 / 0.13.7 were confirmed via `helm search repo vm`.
- Longhorn is installed and is the cluster's default StorageClass, so chart-default PVCs bind without an explicit `storageClassName`.
- ArgoCD is running and watches `argocd/apps/`; the cluster destination is `https://kubernetes.default.svc`.

---

## Outstanding Questions (Deferred to Planning)

- PVC sizes for each store, or accept chart defaults.
- Whether to set `storageClassName: longhorn` explicitly versus relying on Longhorn being the default class.
- Whether either Application is registered in an app-of-apps/root Application or applied directly like the existing apps.

---

## Sources / Research

- `helm search repo vm` (after `helm repo update vm`) → latest single-node charts `victoria-metrics-single` 0.40.1 (app v1.145.0) and `victoria-logs-single` 0.13.7 (app v1.50.0); `victoria-metrics-k8s-stack` 0.83.0 considered and rejected as out of scope.
- `argocd/apps/cert-manager.yaml`, `argocd/apps/metrics-server.yaml` — single-`source` Helm Application pattern with `helm.values` / `helm.valuesObject`.
- `argocd/apps/longhorn.yaml` — per-app namespace + `CreateNamespace=true` convention and Longhorn as the storage layer.
