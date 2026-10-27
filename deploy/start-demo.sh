#!/usr/bin/env bash
#
# start-demo.sh - recreate the KinD cluster and deploy the full EmELand demo
# stack, split into two layers:
#
#   1. Platform layer  (emeland-platform, namespace "monitoring"):
#      Envoy Gateway + the shared Gateway, kube-prometheus-stack, metrics-server,
#      the monitoring UI routes and the homepage overview. Everything
#      cluster-related lives here.
#   2. EmELand system  (emeland-demo, namespace "emeland-demo"):
#      the EmELand modules only. Cluster-agnostic; attaches to the platform's
#      Gateway.
#
# After it finishes, all UIs are reachable on the host via localtest.me:
#
#   http://localtest.me               Overview (auto-detected services)
#   http://emeland.localtest.me       EmELand web UI / server
#   http://grafana.localtest.me       Grafana
#   http://prometheus.localtest.me    Prometheus
#   http://alertmanager.localtest.me  Alertmanager
#
# Requirements: docker, kind, kubectl, helm.
#
# Usage:
#   deploy/start-demo.sh                  # recreate cluster and deploy everything
#   KEEP_CLUSTER=1 deploy/start-demo.sh   # reuse an existing cluster
set -euo pipefail

# --- config ---------------------------------------------------------------
CLUSTER_NAME="emeland-demo"
APP_NAMESPACE="emeland-demo"
PLATFORM_NAMESPACE="monitoring"
ENVOY_GATEWAY_VERSION="v1.9.1"
ENVOY_GATEWAY_NS="envoy-gateway-system"

# Resolve paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CRD_CHART="$REPO_DIR/emeland-demo-crd"
DEMO_CHART="$REPO_DIR/emeland-demo"
PLATFORM_CHART="$REPO_DIR/emeland-platform"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m error:\033[0m %s\n' "$*" >&2; exit 1; }

# --- preflight ------------------------------------------------------------
for bin in docker kind kubectl helm; do
  command -v "$bin" >/dev/null 2>&1 || die "required tool not found: $bin"
done

# --- 1. cluster -----------------------------------------------------------
if [[ "${KEEP_CLUSTER:-0}" == "1" ]]; then
  log "KEEP_CLUSTER=1, reusing existing cluster '$CLUSTER_NAME'"
  kind get clusters | grep -qx "$CLUSTER_NAME" || die "cluster '$CLUSTER_NAME' does not exist"
else
  if kind get clusters | grep -qx "$CLUSTER_NAME"; then
    log "Deleting existing cluster '$CLUSTER_NAME'"
    kind delete cluster --name "$CLUSTER_NAME"
  fi
  log "Creating KinD cluster '$CLUSTER_NAME' (host port 80 -> gateway)"
  kind create cluster --name "$CLUSTER_NAME" --config "$SCRIPT_DIR/kind-cluster.yaml"
fi

kubectl config use-context "kind-$CLUSTER_NAME" >/dev/null

# --- 2. Envoy Gateway (installs Gateway API CRDs + controller) ------------
log "Installing Envoy Gateway $ENVOY_GATEWAY_VERSION"
helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace "$ENVOY_GATEWAY_NS" --create-namespace \
  --wait --timeout 5m

log "Waiting for Envoy Gateway to be available"
kubectl wait --namespace "$ENVOY_GATEWAY_NS" \
  --for=condition=Available deployment/envoy-gateway --timeout=5m

# --- 3. platform layer (Gateway + monitoring stack + overview) ------------
log "Installing platform chart (emeland-platform) in namespace '$PLATFORM_NAMESPACE'"
helm dependency update "$PLATFORM_CHART" >/dev/null
helm upgrade --install emeland-platform "$PLATFORM_CHART" \
  --namespace "$PLATFORM_NAMESPACE" --create-namespace \
  -f "$SCRIPT_DIR/platform-kind-values.yaml" \
  --wait --timeout 8m

log "Waiting for the Gateway to be programmed (data-plane NodePort service)"
kubectl wait --namespace "$PLATFORM_NAMESPACE" \
  --for=condition=Programmed gateway/gateway --timeout=5m

# --- 4. CRD chart (must precede the app chart) ----------------------------
log "Installing CRD chart (emeland-demo-crd) in namespace '$APP_NAMESPACE'"
kubectl create namespace "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
helm dependency update "$CRD_CHART" >/dev/null
helm upgrade --install emeland-demo-crd "$CRD_CHART" \
  --namespace "$APP_NAMESPACE" --wait --timeout 3m

# --- 5. EmELand system layer ----------------------------------------------
log "Installing EmELand system (emeland-demo) in namespace '$APP_NAMESPACE'"
helm dependency update "$DEMO_CHART" >/dev/null
helm upgrade --install emeland-demo "$DEMO_CHART" \
  --namespace "$APP_NAMESPACE" \
  --wait --timeout 6m

# --- 6. smoke test --------------------------------------------------------
log "Smoke-testing routes via host port 80"
smoke_ok=1
for host in localtest.me emeland.localtest.me grafana.localtest.me prometheus.localtest.me alertmanager.localtest.me; do
  code="000"
  # Envoy needs a moment to program freshly-applied routes; retry briefly.
  for _ in $(seq 1 15); do
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${host}" \
      --max-time 10 http://127.0.0.1/ || echo 000)"
    # 2xx/3xx means the route reached its backend (login redirects are fine).
    [[ "$code" =~ ^[23][0-9][0-9]$ ]] && break
    sleep 2
  done
  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
    printf '    ok   %-27s HTTP %s\n' "${host}" "$code"
  else
    printf '    FAIL %-27s HTTP %s\n' "${host}" "$code"
    smoke_ok=0
  fi
done
[[ "$smoke_ok" == "1" ]] || warn "one or more routes did not return a healthy status; check 'kubectl get httproute -A'"

# --- 7. summary -----------------------------------------------------------
log "Done. Services are reachable on the host at:"
cat <<'EOF'

  http://localtest.me               Overview (auto-detected services)
  http://emeland.localtest.me       EmELand web UI / server
  http://grafana.localtest.me       Grafana
  http://prometheus.localtest.me    Prometheus
  http://alertmanager.localtest.me  Alertmanager

(*.localtest.me and localtest.me both resolve to 127.0.0.1; no /etc/hosts edits needed.)

Layers:
  platform (namespace monitoring):     Gateway, kube-prometheus-stack, metrics-server, overview
  emeland  (namespace emeland-demo):   server, filter, sensors (git, k8s), gitserver
EOF
