# EmELand Demo Stack

This is a helm chart that should roll out a complete EmELand stack for demonstration purposes. You will need to provide a Kubernetes cluster to run the individual components.

The following example uses a KinD cluster to provide the environment:
```bash
kind create cluster --name emeland-demo
helm dependency build ./emeland-demo
helm install emeland-demo ./emeland-demo --namespace emeland-demo --create-namespace
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
│  ┌────────────────────────────────────────────────────────────┐      │
│  │  Prometheus Stack                                          │      │
│  │                                                            │      │
│  │  ┌────────────┐   scrapes /metrics   ┌────────────────┐    │      │
│  │  │ Prometheus │─────────────────────▶│ modelsrv       │    │      │
│  │  │            │                      │ kube-state-m.  │    │      │
│  │  │            │                      │ node-exporter  │    │      │
│  │  └───┬────┬───┘                      └────────────────┘    │      │
│  │      │    │                                                │      │
│  │      │    └─────────────────────┐                          │      │
│  │      │ alerts                   │ queries                  │      │
│  │      ▼                          ▼                          │      │
│  │  ┌──────────────┐         ┌─────────┐                      │      │
│  │  │ Alertmanager │         │ Grafana │                      │      │
│  │  └──────────────┘         └─────────┘                      │      │
│  └────────────────────────────────────────────────────────────┘      │
└──────────────────────────────────────────────────────────────────────┘
```

## Connections

| From | To | Protocol | Purpose |
|------|----|----------|---------|
| gitsensor | gitserver | SSH (port 22) | Clone repo, poll for changes |
| gitsensor | modelsrv | HTTP POST `/api/events/push` | Push resource events |
| k8s-sensor | K8s API | HTTPS (in-cluster) | Watch workloads |
| k8s-sensor | modelsrv | HTTP POST `/api/events/push` | Push resource events |
| Prometheus | modelsrv | HTTP GET `/metrics` | Scrape metrics |
| tools pod | modelsrv | HTTP GET `/api/...` | CLI queries |
| Grafana | Prometheus | HTTP | Query metrics for dashboards |

## Components

The helm chart will roll out a number of components, either directly or from sub-charts:

- CRDs required for the K8s sensor (via `modelsrv-k8s-crd` sub-chart)
- This chart will set up the `Deployment` for the following components from prepared OCI images:
    1. **A modelsrv as the central server.** This will be replaced with the [web-server for the Web UI variant](https://github.com/emeland-io/modelsrv-web-ui-server), once it becomes available. It is configured to listen to events from the following two components.
    2. **A container running the EmELand CLI tool.** The container is running a shell and a user can attach to that shell via `kubectl exec`.
    3. **A container containing the git sensor demo data**: Image `ghcr.io/emeland-io/emeland-demo-git` (built from [`emeland-demo-git/`](emeland-demo-git/)) runs an SSH git server with a bare clone of [`test-gitsensor-target`](https://github.com/emeland-io/test-gitsensor-target).
    4. **The Git sensor** (`modelsrv-git-sensor`): Clones from the in-cluster git service over SSH and watches `watchedDir/` manifests.
- The modelsrv Kubernetes sensor (via `modelsrv-k8s-sensor` sub-chart). The sensor will scan the K8s cluster it is deployed in.
- The kube-prometheus-stack (sub-chart): Prometheus, Alertmanager, Grafana, kube-state-metrics, and node-exporter.

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

