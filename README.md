# EmELand Demo Stack

This is a helm chart that should roll out a complete EmELand stack for demonstration purposes. You will need to provide a Kubernetes cluster to run the individual components.

## Charts

| Chart              | Purpose                                                      |
| ------------------ | ------------------------------------------------------------ |
| `emeland-demo-crd` | CRDs required by the Kubernetes sensor (install first)       |
| `emeland-demo`     | Demo stack: web UI server, filter, CLI, git sensor, optional OCI registry sensor, k8s sensor, Prometheus |

## Quick start

The fastest path is the [`deploy/start-demo.sh`](deploy/start-demo.sh) script. It
recreates a KinD cluster, installs Envoy Gateway, deploys both charts, and prints
the service URLs. It requires `docker`, `kind`, `kubectl`, and `helm`.

```bash
deploy/start-demo.sh
# reuse an existing cluster instead of recreating it:
KEEP_CLUSTER=1 deploy/start-demo.sh
```

When it finishes, every UI is reachable on the host (no port-forwarding); the
overview page auto-detects the others:

| URL | Service |
| --- | --- |
| http://localtest.me | Overview landing page (auto-detected services) |
| http://emeland.localtest.me | EmELand web UI / server |
| http://grafana.localtest.me | Grafana |
| http://prometheus.localtest.me | Prometheus |
| http://alertmanager.localtest.me | Alertmanager |

`*.localtest.me` and the bare `localtest.me` both resolve to `127.0.0.1`, so no
`/etc/hosts` edits are needed. Access works because the KinD node maps host port
80 to the Envoy Gateway (see [`deploy/kind-cluster.yaml`](deploy/kind-cluster.yaml)
and [`deploy/gateway-values.yaml`](deploy/gateway-values.yaml)).

### Manual install

You can also install the charts by hand. Install CRDs **before** the main stack:
the k8s-sensor requires CRDs such as `FindingRule` (`structure.emeland.io/v1alpha1`)
at startup; without them the sensor pod crash-loops.

```bash
kind create cluster --name emeland-demo

# 1. CRDs first (cluster-scoped; includes FindingRule)
helm dependency build ./emeland-demo-crd
helm upgrade --install emeland-demo-crd ./emeland-demo-crd \
  --namespace emeland-demo --create-namespace

# 2. Main demo stack
helm dependency update ./emeland-demo
helm upgrade --install emeland-demo ./emeland-demo \
  --namespace emeland-demo --create-namespace
```

The chart creates a Gateway API `Gateway` and `HTTPRoute`s for every UI, but you
must provide the Gateway controller (e.g. Envoy Gateway) and the Gateway API CRDs
yourself, and set hostnames suitable for your environment. On a non-KinD cluster
the Envoy Service defaults to `LoadBalancer`; on KinD use the NodePort overlay
(`-f deploy/gateway-values.yaml`) as the script does. Without a Gateway, disable
routing with `--set gateway.create=false --set httpRoute.enabled=false --set
monitoringRoutes.enabled=false --set overview.enabled=false` and reach the server
directly:

```bash
kubectl port-forward -n emeland-demo svc/emeland-demo-server 8080:80
# open http://127.0.0.1:8080
```

Verify CRDs and the k8s-sensor image after install:

```bash
kubectl get crd findingrules.structure.emeland.io
kubectl get deploy emeland-demo-modelsrv-k8s-sensor -n emeland-demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

# Stack Setup

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (KinD)                                           │
│                                                                      │
│  ┌─────────────────┐   git clone (SSH)    ┌────────────────────┐     │
│  │  gitsensor      │─────────────────────▶│  gitserver         │     │
│  │                 │   port 22            │                    │     │
│  │  watches repo   │                      │  sshd + git-shell  │     │
│  │  for changes    │                      │  serves:           │     │
│  │                 │                      │  test-gitsensor-   │     │
│  │                 │                      │  target.git        │     │
│  └────────┬────────┘                      └────────────────────┘     │
│           │                                                          │
│           │ pushes events                                            │
│           │ POST /api/events/push                                    │
│           ▼                                                          │
│  ┌─────────────────────────────────────┐                             │
│  │        modelsrv (server)            │                             │
│  │                                     │                             │
│  │  • Aggregates events into model     │◄──── kubectl exec           │
│  │  • Runs finding inference filters   │      emelandctl             │
│  │  • Exposes REST API (:8080/api)     │         │                   │
│  │  • Exposes /metrics                 │         │                   │
│  └──────────────────▲──────────────────┘         │                   │
│                     │                    ┌───────┴─────────┐         │
│                     │ pushes events      │  tools pod      │         │
│                     │                    │  (CLI shell)    │         │
│  ┌──────────────────┴──┐                 └─────────────────┘         │
│  │  k8s-sensor         │                                             │
│  │  (controller)       │  watches                                    │
│  │                     │────────────────▶ Deployments, Services,     │
│  │                     │                  Namespaces, Ingresses ...  │
│  └─────────────────────┘                                             │
│                                                                      │
│  ┌─────────────────────┐                                             │
│  │  ociregistrysensor  │  (optional; disabled by default)            │
│  │                     │────────────────▶ OCI registries             │
│  │  polls catalogs     │  Artefact / ArtefactInstance events         │
│  └──────────┬──────────┘                                             │
│             │ POST /api/events/push                                  │
│             └──────────────────────────────▶ modelsrv / filter       │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐      │
│  │  Prometheus Stack                                          │      │
│  │                                                            │      │
│  │  ┌────────────┐   scrapes /metrics   ┌────────────────┐    │      │
│  │  │ Prometheus │─────────────────────▶│ modelsrv       │    │      │
│  │  │            │                      │ kube-state-m.  │    │      │
│  │  │            │                      │ node-exporter  │    │      │
│  │  └───┬────┬───┘                      └────────────────┘    │      │
│  │      │    │                                                │      │
│  │      │    └─────────────────────────────┐                  │      │
│  │      │ alerts                           │ queries          │      │
│  │      ▼                                  ▼                  │      │
│  │  ┌──────────────┐                 ┌─────────┐              │      │
│  │  │ Alertmanager │                 │ Grafana │              │      │
│  │  └──────────────┘                 └─────────┘              │      │
│  └────────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────────┘
```

## Connections

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| gitsensor | gitserver | SSH (port 22) | Clone repo, poll for changes |
| gitsensor | modelsrv / filter | HTTP POST `/api/events/push` | Push resource events |
| ociregistrysensor | OCI registry | HTTPS | Catalog repos, list tags, resolve digests |
| ociregistrysensor | modelsrv / filter | HTTP POST `/api/events/push` | Push Artefact / ArtefactInstance events |
| k8s-sensor | K8s API | HTTPS (in-cluster) | Watch workloads |
| k8s-sensor | modelsrv / filter | HTTP POST `/api/events/push` | Push resource events |
| Prometheus | modelsrv | HTTP GET `/metrics` | Scrape metrics |
| tools pod | modelsrv | HTTP GET `/api/...` | CLI queries |
| Grafana | Prometheus | HTTP | Query metrics for dashboards |

## Components

The demo stack rolls out the following, either directly or from sub-charts:

- **CRDs** (`emeland-demo-crd` chart → `modelsrv-k8s-crd` sub-chart): `System`, `SystemInstance`, `API`, `Component`, and `FindingRule`. Install this chart before `emeland-demo`; Helm does not reliably apply CRDs from subcharts when only the parent chart is installed.
- This chart will set up the `Deployment` for the following components from prepared OCI images:
    1. **A modelsrv as the central server.** This will be replaced with the [web-server for the Web UI variant](https://github.com/emeland-io/modelsrv-web-ui-server), once it becomes available. It is configured to listen to events from the following two components.
    2. **A container running the EmELand CLI tool.** The container is running a shell and a user can attach to that shell via `kubectl exec`.
    3. **A container containing the git sensor demo data**: Image `ghcr.io/emeland-io/emeland-demo-git` (built from [`emeland-demo-git/`](emeland-demo-git/)) runs an SSH git server with a bare clone of [`test-gitsensor-target`](https://github.com/emeland-io/test-gitsensor-target).
    4. **The Git sensor** (`modelsrv-git-sensor`): Clones from the in-cluster git service over SSH and watches `watchedDir/` manifests.
    5. **The OCI registry sensor** (`modelsrv-oci-registry-sensor`, optional): Disabled by default. Enable with `ociregistrysensor.enabled=true` and set `ociregistrysensor.registries` to scan OCI registries and emit `Artefact` / `ArtefactInstance` events.
- The modelsrv Kubernetes sensor (via `modelsrv-k8s-sensor` sub-chart). The sensor will scan the K8s cluster it is deployed in.
- The kube-prometheus-stack (sub-chart): Prometheus, Alertmanager, Grafana, kube-state-metrics, and node-exporter.
- **metrics-server** (sub-chart, `metrics-server.enabled`): provides the Metrics API for `kubectl top`, HPA, and the overview cluster widget. On KinD it runs with `--kubelet-insecure-tls` (see `metrics-server.args`).
- **A `ServiceMonitor`** (`serviceMonitor.enabled`) telling the kube-prometheus-stack Prometheus to scrape the modelsrv server and filter `/metrics` endpoints.
- **A shared Gateway API `Gateway`** (`gateway.create`) named `gateway`, plus its `GatewayClass` and Envoy `EnvoyProxy`, and an `HTTPRoute` per UI. Requires a Gateway controller (e.g. Envoy Gateway) in the cluster. The Envoy Service defaults to `LoadBalancer`; the KinD overlay pins it to a NodePort.
- **An overview landing page** (`overview.enabled`, [gethomepage/homepage](https://github.com/gethomepage/homepage)) served at the bare host. It runs in Kubernetes "cluster" mode with Gateway API discovery, so it auto-detects every `HTTPRoute` annotated with `gethomepage.dev/enabled`.

## Git server image

The [`emeland-demo-git/`](emeland-demo-git/) Dockerfile clones `test-gitsensor-target` at build time and serves it as `/srv/git/test-gitsensor-target.git` over SSH (`git-shell`).

- **Build on PR**: workflow `git-server-build.yml` (no push)
- **Publish on tag**: push a `v*` tag (e.g. `v0.1.0`) to publish `ghcr.io/emeland-io/emeland-demo-git:<tag>`
- Set `image.gitserver.tag` in [`emeland-demo/values.yaml`](emeland-demo/values.yaml) to match the published tag

## Git Server SSH Host Key

The git server image generates an **ED25519 host key at image build time**. The fingerprint is stable for a given image digest/tag.

| Item | Value |
|------|--------|
| Documented fingerprint (`values.gitserver.sshHostKeyFingerprint`) | See `gitserver.sshHostKeyFingerprint` in chart values (update after first publish) |
| In-cluster SSH service | `<release-name>-git` (port 22), e.g. `emeland-demo-git` |
| Repository SSH URL | `git@<release-name>-git:/srv/git/test-gitsensor-target.git` |

After building or pulling the image, read the fingerprint from the image:

```bash
docker run --rm ghcr.io/emeland-io/emeland-demo-git:<tag> cat /etc/ssh/ssh_host_ed25519_key.fingerprint
```

Update `gitserver.sshHostKeyFingerprint` in `emeland-demo/values.yaml` with the `SHA256:...` line.

## Deploy key (demo)

The chart ships a **demo-only** Ed25519 deploy key pair in `deployKey` values. The private key is mounted into the git sensor; the public key is mounted as `authorized_keys` on the git server.

To rotate keys for a non-demo environment:

1. Generate a new pair: `ssh-keygen -t ed25519 -f deploy_key -N "" -C "emeland-demo-deploy"`
2. Set `deployKey.privateKey` and `deployKey.publicKey` in Helm values
3. Upgrade the release

The git sensor config expects the public key path `/keys/id_ed25519.pub` (private key at `/keys/id_ed25519`).

