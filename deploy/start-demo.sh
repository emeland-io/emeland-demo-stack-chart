#!/usr/bin/env bash
#
# start-demo.sh - recreate the KinD cluster and deploy the full EmELand demo
# stack with Gateway API (Envoy Gateway) hostname routing for every service.
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
#   deploy/start-demo.sh            # recreate cluster and deploy everything
#   KEEP_CLUSTER=1 deploy/start-demo.sh   # reuse an existing cluster
set -euo pipefail

# --- config ---------------------------------------------------------------
CLUSTER_NAME="emeland-demo"
NAMESPACE="emeland-demo"
ENVOY_GATEWAY_VERSION="v1.9.1"
ENVOY_GATEWAY_NS="envoy-gateway-system"

# Resolve paths relative to this script so it works from any CWD.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
CRD_CHART="$REPO_DIR/emeland-demo-crd"
DEMO_CHART="$REPO_DIR/emeland-demo"

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

# --- 3. namespace ---------------------------------------------------------
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- 4. CRD chart (must precede the main chart) ---------------------------
log "Installing CRD chart (emeland-demo-crd)"
helm dependency update "$CRD_CHART" >/dev/null
helm upgrade --install emeland-demo-crd "$CRD_CHART" \
  --namespace "$NAMESPACE" --wait --timeout 3m

# --- 5. main demo stack (creates the Gateway and all routes) -------------
log "Installing demo stack (emeland-demo) with Gateway routing"
helm dependency update "$DEMO_CHART" >/dev/null
helm upgrade --install emeland-demo "$DEMO_CHART" \
  --namespace "$NAMESPACE" \
  -f "$SCRIPT_DIR/gateway-values.yaml" \
  --wait --timeout 6m

# --- 6. wait for the Gateway to be programmed ----------------------------
# The chart creates the Gateway + EnvoyProxy in step 5; the NodePort patch can
# take a reconcile cycle or two before the Gateway is assigned an address.
log "Waiting for the Gateway to be programmed (data-plane NodePort service)"
kubectl wait --namespace "$NAMESPACE" \
  --for=condition=Programmed gateway/gateway --timeout=5m

# --- 7. smoke test --------------------------------------------------------
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
[[ "$smoke_ok" == "1" ]] || warn "one or more routes did not return a healthy status; check 'kubectl get httproute -n $NAMESPACE'"

# --- 8. summary -----------------------------------------------------------
log "Done. Services are reachable on the host at:"
cat <<'EOF'

  http://localtest.me               Overview (auto-detected services)
  http://emeland.localtest.me       EmELand web UI / server
  http://grafana.localtest.me       Grafana
  http://prometheus.localtest.me    Prometheus
  http://alertmanager.localtest.me  Alertmanager

(*.localtest.me and localtest.me both resolve to 127.0.0.1; no /etc/hosts edits needed.)
EOF
