---
title: "feat: Envoy Gateway TLS ingress for internal apps"
type: feat
date: 2026-06-15
origin: docs/brainstorms/2026-06-15-internal-apps-gateway-tls-requirements.md
deepened: 2026-06-15
---

# feat: Envoy Gateway TLS ingress for internal apps

## Summary

Stand up Gateway API ingress on the k3s cluster by adding Envoy Gateway
(`gateway-helm` 1.8.1) as a directly-applied ArgoCD `Application`, and front the
existing VictoriaMetrics and VictoriaLogs UIs at `vm-metrics.homelab.gbsoft.net`
and `vm-logs.homelab.gbsoft.net` behind a Let's Encrypt wildcard certificate
(`*.homelab.gbsoft.net`). cert-manager issues the wildcard over the ACME DNS-01
challenge via Cloudflare using its Gateway API shim; cert-manager and MetalLB
already run and are reused (see origin: `docs/brainstorms/2026-06-15-internal-apps-gateway-tls-requirements.md`).

---

## Problem Frame

The cluster has no ingress — Traefik was disabled at k3s install
(`docs/plans/2026-06-12-002-feat-k3s-ansible-install-plan.md`), so internal UIs
are reachable today only via `kubectl port-forward` or a raw Service IP, neither
of which carries a browser-trusted certificate. Two of the three pieces are
already in place: cert-manager (v1.17.2, `argocd/apps/cert-manager.yaml`) runs
with `--enable-gateway-api`, and MetalLB (v0.15.2, `argocd/apps/metallb.yaml`)
owns the `192.168.1.80-.85` L2 pool. What is missing is the gateway plus the
glue — an ACME issuer, a wildcard certificate, and host-based routes — that turns
those add-ons into named, HTTPS-trusted hostnames.

---

## Requirements

**Ingress gateway**

- R1. Envoy Gateway deploys as a directly-applied ArgoCD `Application` from the OCI chart `oci://docker.io/envoyproxy/gateway-helm`, pinned to `1.8.1`, following the per-app convention in `argocd/apps/`. (origin R1)
- R2. A `GatewayClass` and `Gateway` serve an HTTPS listener for `*.homelab.gbsoft.net`, with plain HTTP redirected to HTTPS. (origin R2)
- R3. The gateway's LoadBalancer Service binds the fixed address `192.168.1.80` from the MetalLB pool so the wildcard DNS record targets a stable IP. (origin R3)

**Certificate issuance**

- R4. A cert-manager ACME `ClusterIssuer` named `letsencrypt` uses Let's Encrypt's production endpoint with the DNS-01 solver backed by Cloudflare. (origin R4)
- R5. cert-manager issues one wildcard certificate for `*.homelab.gbsoft.net` via the Gateway API shim, consumed by the gateway's HTTPS listener. (origin R5)
- R6. The Cloudflare API token is supplied via a Secret provisioned out-of-band; no token value is committed to the repo. (origin R6)

**App exposure and routing**

- R7. An HTTPRoute exposes the VictoriaMetrics UI at `vm-metrics.homelab.gbsoft.net`. (origin R7)
- R8. An HTTPRoute exposes the VictoriaLogs UI at `vm-logs.homelab.gbsoft.net`. (origin R8)
- R9. Routes attach to the shared gateway across namespaces — they live in `victoria-metrics` / `victoria-logs` while the gateway lives in `envoy-gateway-system`. (origin R9)

**DNS**

- R10. A public Cloudflare wildcard A record (`*.homelab.gbsoft.net`) resolves to `192.168.1.80`. (origin R10)

---

## Key Technical Decisions

- **Issue the cert via the cert-manager Gateway API shim, not a standalone `Certificate`.** Annotating the `Gateway` with `cert-manager.io/cluster-issuer: letsencrypt` plus a listener `tls.certificateRefs` makes cert-manager derive the cert from the listener `hostname` and write it into the referenced Secret. One annotation drives issuance and renewal; nothing else to maintain. Requires `--enable-gateway-api`, already set on the cert-manager app. The shim only creates the Secret in the `Gateway`'s own namespace, which is why the wildcard Secret and the routes' parent `Gateway` both live in `envoy-gateway-system`.
- **A single `letsencrypt` ClusterIssuer on the production ACME endpoint — no staging.** The homelab is one environment, so a staging issuer adds no value (user decision). Resolves the origin's deferred LE-environment question.
- **Pin the gateway to `192.168.1.80` via an `EnvoyProxy` resource.** The `GatewayClass` `parametersRef` points at an `EnvoyProxy` whose `envoyService.annotations` carry `metallb.io/loadBalancerIPs: "192.168.1.80"`. The wildcard A record is a single fixed address, so the LB IP must be stable; `.80` is the first address in the MetalLB pool. Resolves the origin's deferred IP-pinning question.
- **Add public recursive resolvers to cert-manager for the DNS-01 self-check.** Adding `--dns01-recursive-nameservers-only` and `--dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53` to the cert-manager args makes its pre-issuance TXT self-check resolve the public `_acme-challenge` record instead of relying on cluster DNS, which would not see the Cloudflare record.
- **Follow the "chart + git manifests" multi-source pattern.** The envoy-gateway app uses a `sources:` array (the `gateway-helm` chart plus a git source for `argocd/manifests/envoy-gateway/`), mirroring `argocd/apps/metallb.yaml`. The existing cert-manager app is likewise extended with a git source for the ClusterIssuer manifest. Resolves the origin's deferred "where the glue manifests live" question.
- **Co-locate HTTPRoutes in their backend namespaces; no `ReferenceGrant`.** Each route sits in the same namespace as the Service it targets (`victoria-metrics` / `victoria-logs`), so backend references need no `ReferenceGrant`. Cross-namespace *parent* attachment to the gateway is governed by the listener's `allowedRoutes.namespaces`, opened to those namespaces. Resolves the origin's deferred cross-namespace-routing question.

---

## High-Level Technical Design

One `Gateway` in `envoy-gateway-system` is the single ingress entrypoint at
`192.168.1.80`. cert-manager watches the gateway annotation and issues the
wildcard cert into a Secret the HTTPS listener reads. HTTPRoutes in the app
namespaces attach to the gateway and forward to the VM backends.

```mermaid
flowchart TB
  subgraph cloudflare[Cloudflare zone gbsoft.net]
    AREC["*.homelab.gbsoft.net A -> 192.168.1.80 (DNS-only)"]
    TXT["_acme-challenge TXT (DNS-01)"]
  end

  Browser["LAN browser"] -->|resolves wildcard| AREC
  Browser -->|HTTPS 443| GW

  subgraph egns[namespace: envoy-gateway-system]
    GC["GatewayClass eg + EnvoyProxy (metallb.io/loadBalancerIPs 192.168.1.80)"]
    GW["Gateway eg<br/>HTTP :80 redirect, HTTPS :443 *.homelab.gbsoft.net"]
    SEC[("Secret homelab-wildcard-tls")]
    RED["HTTPRoute http-redirect (301 to https)"]
    GC --> GW
    SEC --> GW
    GW --> RED
  end

  subgraph cmns[namespace: cert-manager]
    CI["ClusterIssuer letsencrypt (ACME prod)"]
  end

  GW -. cert-manager.io/cluster-issuer .-> CI
  CI -->|DNS-01 via Cloudflare API token| TXT
  CI -->|signed wildcard| SEC

  subgraph vmns[namespace: victoria-metrics]
    RM["HTTPRoute vm-metrics"] --> SVM["VictoriaMetrics server :8428"]
  end
  subgraph vlns[namespace: victoria-logs]
    RL["HTTPRoute vm-logs"] --> SVL["VictoriaLogs server :9428"]
  end

  GW --> RM
  GW --> RL
```

---

## Output Structure

```text
argocd/
  apps/
    envoy-gateway.yaml                          (new)    Application: gateway-helm 1.8.1 + git manifests
    cert-manager.yaml                           (modify) sources[]: chart + git manifests; dns01 resolver args
  manifests/
    cert-manager/
      clusterissuer-letsencrypt.yaml            (new)    ACME DNS-01 Cloudflare ClusterIssuer
    envoy-gateway/
      gatewayclass.yaml                         (new)    GatewayClass eg + EnvoyProxy (pinned LB IP)
      gateway.yaml                              (new)    Gateway eg: HTTP + HTTPS listeners, cert shim
      httproute-redirect.yaml                   (new)    HTTP -> HTTPS 301 redirect
      httproute-vm-metrics.yaml                 (new)    route in victoria-metrics ns
      httproute-vm-logs.yaml                    (new)    route in victoria-logs ns
```

The per-unit `**Files:**` sections are authoritative; the implementer may adjust
layout if it reveals a cleaner shape.

---

## Implementation Units

### U1. Out-of-band prerequisites: Cloudflare token Secret and wildcard DNS record

- **Goal:** The cluster holds the Cloudflare API token Secret cert-manager needs, and the public wildcard A record resolves to the gateway IP.
- **Requirements:** R6, R10
- **Dependencies:** none — `192.168.1.80` is fixed by KTD, so the A record can be created up front.
- **Files:** none — provisioned out-of-band, never committed (security guardrail).
- **Approach:**
  - Create Secret `cloudflare-api-token` (key `api-token`) in the `cert-manager` namespace from a Cloudflare token scoped `Zone:Read` + `DNS:Write` on `gbsoft.net`.
  - Add a public DNS A record `*.homelab.gbsoft.net -> 192.168.1.80` in Cloudflare. It MUST be **DNS-only (grey cloud)**, never proxied — a proxied record would route through Cloudflare to a private IP and break.
- **Execution note:** Manual / operational; the token value never enters version control. Mirrors the `longhorn-backup-secret` out-of-band pattern.
- **Test scenarios:** `Test expectation: none -- out-of-band credential and DNS provisioning; validated by the verification commands below, not unit tests.`
- **Verification:** `kubectl -n cert-manager get secret cloudflare-api-token` exists with key `api-token`; `dig +short vm-metrics.homelab.gbsoft.net` returns `192.168.1.80`.

### U2. Let's Encrypt DNS-01 ClusterIssuer and cert-manager app extension

- **Goal:** A `letsencrypt` ClusterIssuer issues certs over ACME DNS-01 via Cloudflare, and cert-manager runs its DNS-01 self-check against public resolvers.
- **Requirements:** R4 (consumes R6)
- **Dependencies:** U1 (token Secret)
- **Files:**
  - `argocd/manifests/cert-manager/clusterissuer-letsencrypt.yaml` (create) — `ClusterIssuer` `letsencrypt`, ACME server `https://acme-v02.api.letsencrypt.org/directory`, an account email, a `privateKeySecretRef`, and a `dns01` Cloudflare solver referencing the token Secret.
  - `argocd/apps/cert-manager.yaml` (modify) — convert the single `source` to a `sources:` array: the jetstack chart (keeping `installCRDs: true`, `--enable-gateway-api`, adding the two `--dns01-recursive-nameservers*` args) plus a git source for `argocd/manifests/cert-manager`.
- **Approach:** Directional issuer solver shape:

  ```yaml
  solvers:
    - dns01:
        cloudflare:
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
  ```
  Directional cert-manager arg additions (preserve existing `--enable-gateway-api`):

  ```yaml
  extraArgs:
    - --enable-gateway-api
    - --dns01-recursive-nameservers-only
    - --dns01-recursive-nameservers=1.1.1.1:53,9.9.9.9:53
  ```
- **Patterns to follow:** `argocd/apps/metallb.yaml` for the `sources:` chart + git-manifests shape; the existing `helm.valuesObject` block in `argocd/apps/cert-manager.yaml`.
- **Test scenarios:**
  - `kubectl apply --dry-run=client -f argocd/manifests/cert-manager/clusterissuer-letsencrypt.yaml` parses without error.
  - `argocd/apps/cert-manager.yaml` renders a `sources:` array containing both the jetstack chart and the `argocd/manifests/cert-manager` git path; `extraArgs` still includes `--enable-gateway-api` and now also the two `--dns01-recursive-nameservers*` args.
  - `Covers AE2.` After sync with the token Secret present, `kubectl get clusterissuer letsencrypt` reports `Ready=True` (ACME account registered).
- **Verification:** ClusterIssuer `Ready=True`; cert-manager pods healthy after the args-driven rollout.

### U3. Envoy Gateway controller, GatewayClass, and pinned LoadBalancer IP

- **Goal:** Envoy Gateway 1.8.1 runs in `envoy-gateway-system`; a `GatewayClass` `eg` is backed by an `EnvoyProxy` that pins the envoy LoadBalancer Service to `192.168.1.80`.
- **Requirements:** R1, R3
- **Dependencies:** none (precedes U4)
- **Files:**
  - `argocd/apps/envoy-gateway.yaml` (create) — `Application` in `namespace: argocd`, `project: default`, `sources:` array of the OCI `gateway-helm` chart (`targetRevision: 1.8.1`) and a git source for `argocd/manifests/envoy-gateway`; `destination` namespace `envoy-gateway-system`; `syncOptions: [CreateNamespace=true]`.
  - `argocd/manifests/envoy-gateway/gatewayclass.yaml` (create) — `GatewayClass` `eg` (controllerName `gateway.envoyproxy.io/gatewayclass-controller`, `parametersRef` -> the `EnvoyProxy`) and an `EnvoyProxy` in `envoy-gateway-system`.
- **Approach:** The `gateway-helm` chart installs the Gateway API CRDs and the Envoy Gateway CRDs (`EnvoyProxy`, etc.). Directional EnvoyProxy shape for the static IP:

  ```yaml
  spec:
    provider:
      type: Kubernetes
      kubernetes:
        envoyService:
          type: LoadBalancer
          annotations:
            metallb.io/loadBalancerIPs: "192.168.1.80"
  ```
  The exact ArgoCD OCI-Helm source fields (registry `repoURL`, `chart`) are settled at implementation against the running ArgoCD version (see Open Questions).
- **Patterns to follow:** `argocd/apps/metallb.yaml` (chart + git-manifests `sources:`); `argocd/manifests/metallb/metallb-config.yaml` (config CRs deployed by the app).
- **Test scenarios:**
  - `argocd/apps/envoy-gateway.yaml` pins the `gateway-helm` chart to `targetRevision: 1.8.1` and carries the git manifests source.
  - `gatewayclass.yaml` `EnvoyProxy` carries `metallb.io/loadBalancerIPs: "192.168.1.80"`, and the `GatewayClass` `parametersRef` points at it.
  - `Covers AE1 (gateway readiness).` After sync, the envoy-gateway controller pod is Running, `kubectl get gatewayclass eg` reports `Accepted=True`.
- **Verification:** GatewayClass `Accepted=True`; controller Deployment healthy. (CR manifests validate server-side post-sync since their CRDs ship with the chart.)

### U4. Gateway listeners and HTTP-to-HTTPS redirect

- **Goal:** A `Gateway` serves an HTTPS listener for `*.homelab.gbsoft.net` (TLS terminated with the shim-issued wildcard) and an HTTP listener that 301-redirects to HTTPS; cross-namespace routes are allowed.
- **Requirements:** R2, R5
- **Dependencies:** U2 (issuer), U3 (GatewayClass + CRDs)
- **Files:**
  - `argocd/manifests/envoy-gateway/gateway.yaml` (create) — `Gateway` `eg` (`gatewayClassName: eg`) in `envoy-gateway-system`, annotated `cert-manager.io/cluster-issuer: letsencrypt`; an HTTP listener (`:80`) and an HTTPS listener (`:443`, `hostname: "*.homelab.gbsoft.net"`, `tls.mode: Terminate`, `certificateRefs` -> Secret `homelab-wildcard-tls`); both listeners `allowedRoutes.namespaces.from: All`.
  - `argocd/manifests/envoy-gateway/httproute-redirect.yaml` (create) — HTTPRoute in `envoy-gateway-system` attached to the HTTP listener via `sectionName`, hostnames `*.homelab.gbsoft.net`, a `RequestRedirect` filter (`scheme: https`, `statusCode: 301`).
- **Approach:** The shim issues the wildcard into Secret `homelab-wildcard-tls` in the gateway's own namespace, so the listener reference needs no `ReferenceGrant`. Directional redirect filter:

  ```yaml
  filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
  ```
  `allowedRoutes.from: All` keeps attachment simple for the homelab; tightening to a namespace selector is deferred follow-up.
- **Test scenarios:**
  - `kubectl apply --dry-run=client -f argocd/manifests/envoy-gateway/gateway.yaml` and `-f .../httproute-redirect.yaml` parse without error.
  - `gateway.yaml` HTTPS listener has `hostname: "*.homelab.gbsoft.net"`, `certificateRefs` name `homelab-wildcard-tls`, and the `cert-manager.io/cluster-issuer: letsencrypt` annotation.
  - The redirect route carries a `RequestRedirect` filter with `scheme: https`, `statusCode: 301`.
  - `Covers AE2, AE3.` After sync, `kubectl get certificate -n envoy-gateway-system` is `Ready=True` and Secret `homelab-wildcard-tls` is populated; `curl -sI http://vm-metrics.homelab.gbsoft.net` returns `301` to the `https://` URL.
- **Verification:** Gateway `Programmed=True`; wildcard Certificate `Ready=True`; HTTP requests return 301.

### U5. HTTPRoutes for VictoriaMetrics and VictoriaLogs

- **Goal:** HTTPRoutes expose the two UIs at their hostnames through the gateway over the wildcard cert.
- **Requirements:** R7, R8, R9
- **Dependencies:** U4 (Gateway serving); VictoriaMetrics/VictoriaLogs already deployed (`argocd/apps/victoria-metrics.yaml`, `argocd/apps/victoria-logs.yaml`)
- **Files:**
  - `argocd/manifests/envoy-gateway/httproute-vm-metrics.yaml` (create) — HTTPRoute in `victoria-metrics`, `parentRefs` -> Gateway `eg` in `envoy-gateway-system`, `hostnames: [vm-metrics.homelab.gbsoft.net]`, `backendRefs` -> the VictoriaMetrics server Service on `:8428`.
  - `argocd/manifests/envoy-gateway/httproute-vm-logs.yaml` (create) — HTTPRoute in `victoria-logs`, `parentRefs` -> the same Gateway, `hostnames: [vm-logs.homelab.gbsoft.net]`, `backendRefs` -> the VictoriaLogs server Service on `:9428`.
- **Approach:** Each route lives in its backend's namespace, so the `backendRefs` need no `ReferenceGrant`; the `parentRefs` entry carries `namespace: envoy-gateway-system` for cross-namespace attachment. Exact backend Service names follow the Helm release fullname and are confirmed at implementation (`kubectl -n victoria-metrics get svc`); expected `*-victoria-metrics-single-server:8428` and `*-victoria-logs-single-server:9428`. VictoriaLogs serves its UI under `/select/vmui` — whether to add a path/redirect is deferred (Open Questions).
- **Test scenarios:**
  - `kubectl apply --dry-run=client -f` both route files parse without error.
  - Each route has the correct `hostname`, a `parentRefs` entry with `namespace: envoy-gateway-system` / `name: eg`, and the expected backend port (`8428` / `9428`).
  - `Covers AE1, AE4.` After sync, both routes report `Accepted=True` / `ResolvedRefs=True`; a browser loads `https://vm-metrics.homelab.gbsoft.net` and `https://vm-logs.homelab.gbsoft.net` with a publicly-trusted certificate and no warning, the second served by the same wildcard with no new cert issued.
- **Verification:** Both HTTPRoutes `Accepted`/`ResolvedRefs` true; each UI loads over trusted TLS.

---

## Acceptance Examples

- AE1. Trusted TLS in the browser
  - **Covers R2, R5, R7.**
  - **Given** the gateway, cert, and the vm-metrics route are synced,
  - **When** the operator opens `https://vm-metrics.homelab.gbsoft.net`,
  - **Then** the VictoriaMetrics UI loads with a publicly-trusted certificate and no browser warning.
- AE2. Wildcard certificate issued
  - **Covers R4, R5, R6.**
  - **Given** the ClusterIssuer and Cloudflare token Secret exist and the gateway is annotated,
  - **When** cert-manager processes the request,
  - **Then** the `Certificate` reports `Ready=True` and Secret `homelab-wildcard-tls` holds a Let's Encrypt-signed `*.homelab.gbsoft.net` cert.
- AE3. HTTP redirects to HTTPS
  - **Covers R2.**
  - **Given** the gateway is serving,
  - **When** a client requests `http://vm-logs.homelab.gbsoft.net`,
  - **Then** it is redirected (301) to the `https://` URL.
- AE4. Second app reuses the same wildcard
  - **Covers R8.**
  - **Given** the wildcard cert is already issued,
  - **When** the VictoriaLogs route is added,
  - **Then** `vm-logs.homelab.gbsoft.net` serves over the existing cert with no new certificate issued.

---

## Scope Boundaries

### Deferred to Follow-Up Work

- Exposing the ArgoCD and Longhorn UIs — only the two VictoriaMetrics/Logs UIs in this plan.
- Any authentication or authorization in front of the exposed UIs — they are reachable by anyone who can hit the gateway on the LAN.
- A local DNS resolver for `*.homelab.gbsoft.net` — the public Cloudflare record is used instead.
- Tightening `allowedRoutes.from: All` to a namespace selector.
- Automating the Cloudflare A record (e.g., external-dns) — created manually here.

### Outside this plan's shape

- An internal CA or the HTTP-01 challenge — the trust model is public Let's Encrypt via DNS-01.
- Redeploying or reconfiguring cert-manager and MetalLB beyond the cert-manager args/source change above.
- Non-HTTP (TCP/UDP) routing through the gateway.

---

## Dependencies / Prerequisites

- cert-manager v1.17.2 is running with `--enable-gateway-api` (`argocd/apps/cert-manager.yaml`).
- MetalLB v0.15.2 is running with the `192.168.1.80-.85` L2 pool (`argocd/manifests/metallb/metallb-config.yaml`), and `192.168.1.80` is free (no other LoadBalancer Service holds it).
- Cloudflare hosts the `gbsoft.net` zone, and an API token scoped `Zone:Read` + `DNS:Write` is available for U1.
- VictoriaMetrics and VictoriaLogs are deployed and serving their UIs (`argocd/apps/victoria-metrics.yaml`, `argocd/apps/victoria-logs.yaml`).
- ArgoCD watches `argocd/apps/` and syncs to `https://kubernetes.default.svc`.
- LAN clients can route to `192.168.1.80` and their resolver does not block the public hostname answering with an RFC1918 address.

---

## Risks & Mitigations

- **ArgoCD sync ordering.** The `Gateway`, `EnvoyProxy`, and HTTPRoute CRs depend on CRDs the chart installs in the same Application; the first sync may show transient errors until the CRDs and controller are up. The `argocd/apps/metallb.yaml` precedent (chart + config CRs in one app) converges via ArgoCD retry/self-heal. Mitigation: rely on retry; if it persists, split CRDs with sync waves or a pre-sync CRD apply.
- **Envoy Gateway + MetalLB static-IP quirks.** Upstream issues report external-IP assignment problems in on-prem LB mode (envoyproxy/gateway #5012, #7395). Mitigation: verify the envoy Service receives `192.168.1.80`; if the annotation is not honored, fall back to a MetalLB pool reservation or `spec.loadBalancerIP`.
- **DNS-01 self-check failure.** Without public recursive resolvers, cert-manager's pre-issuance TXT check can fail behind cluster DNS. Mitigated by the `--dns01-recursive-nameservers` args in U2.
- **Production ACME rate limits (no staging).** A misconfigured issuance loop could hit Let's Encrypt's duplicate-certificate limit. Mitigation: confirm `ClusterIssuer Ready=True` and the DNS-01 challenge is presented before depending on issuance; a single wildcard keeps cert count low.
- **Proxied Cloudflare record.** An orange-cloud (proxied) wildcard record would break private-IP resolution. Mitigated by the DNS-only requirement in U1.

---

## Open Questions (Deferred to Implementation)

- Exact backend Service names for the VM UIs (Helm release fullname) — confirm via `kubectl get svc`; and whether the VictoriaLogs route needs a path/redirect for its `/select/vmui` UI base.
- The ACME account email for the `letsencrypt` ClusterIssuer.
- The precise ArgoCD OCI-Helm source fields for `gateway-helm` (registry `repoURL` vs `chart`) against the running ArgoCD version.
- Whether `allowedRoutes.from: All` is acceptable or should be narrowed to a namespace selector now.
- Whether the cert-manager args change rolls out via ArgoCD alone or needs a manual controller restart.

---

## Sources & Research

- `helm show chart oci://docker.io/envoyproxy/gateway-helm` -> latest stable `gateway-helm` 1.8.1 (appVersion v1.8.1); `1.9.0-rc.0` exists but is a release candidate. Envoy Gateway ships as an OCI chart, so `helm search repo` does not index it.
- Envoy Gateway "Using cert-manager For TLS Termination" task and "HTTP Redirects" task (`gateway.envoyproxy.io/docs/tasks/`).
- cert-manager Gateway API shim (`cert-manager.io/docs/usage/gateway`) — annotate the `Gateway` with `cert-manager.io/cluster-issuer`; the `Certificate` is named after the `certificateRefs` Secret with `dnsNames` from the listener `hostname`; requires `--enable-gateway-api` (already set in `argocd/apps/cert-manager.yaml`). The shim creates the Secret only in the `Gateway`'s namespace — verified, drives the `envoy-gateway-system` Secret placement.
- MetalLB static IP for Envoy Gateway via the `EnvoyProxy` `provider.kubernetes.envoyService.annotations` field (confirmed against Envoy Gateway v1.8 `customize-envoyproxy` + `GatewayClass.parametersRef` docs). The current MetalLB annotation key is `metallb.io/loadBalancerIPs` (verified against MetalLB upstream usage docs; `metallb.universe.tf/loadBalancerIPs` is deprecated). On-prem IP-assignment caveats: envoyproxy/gateway issues #5012, #7395.
- Cloudflare DNS-01 token scope `Zone:Read` + `DNS:Write`; `--dns01-recursive-nameservers` for self-check reliability (web research, 2025-2026 guides).
- Repo precedents: `argocd/apps/metallb.yaml` (`sources:` chart + git), `argocd/manifests/metallb/metallb-config.yaml`, `argocd/apps/cert-manager.yaml` (`--enable-gateway-api`), `argocd/apps/victoria-metrics.yaml`, `argocd/apps/victoria-logs.yaml`.
- Origin requirements: `docs/brainstorms/2026-06-15-internal-apps-gateway-tls-requirements.md`.
