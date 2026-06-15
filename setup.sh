#!/usr/bin/env bash
# =============================================================================
#  setup.sh  —  Bootstrap the Backstage × ServiceNow POC on kind
#
#  Usage:
#    ./setup.sh                              # use existing image from DockerHub
#    ./setup.sh --build yourname/snow-poc    # build & push your own image
#    ./setup.sh --image yourname/snow-poc:v2 # use a specific image tag
#    ./setup.sh --teardown                   # destroy the cluster
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
CLUSTER_NAME="backstage-snow-poc"
NAMESPACE="backstage-snow"
DEFAULT_IMAGE="your-dockerhub-user/backstage-snow-poc:latest"  # ← change this
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}/k8s"

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ══${NC}"; }

# ── Arg parsing ───────────────────────────────────────────────────────────────
BUILD=false
IMAGE="${DEFAULT_IMAGE}"
TEARDOWN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --build)   BUILD=true; IMAGE="${2:-$DEFAULT_IMAGE}"; shift 2 ;;
    --image)   IMAGE="$2"; shift 2 ;;
    --teardown) TEARDOWN=true; shift ;;
    *) error "Unknown flag: $1" ;;
  esac
done

# ── Teardown ──────────────────────────────────────────────────────────────────
if $TEARDOWN; then
  header "Tearing down cluster"
  kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null && \
    success "Cluster deleted" || warn "Cluster not found"
  exit 0
fi

# ── Preflight checks ──────────────────────────────────────────────────────────
header "Preflight checks"

check() {
  if command -v "$1" &>/dev/null; then
    success "$1 found ($(command -v "$1"))"
  else
    error "$1 not found — please install it first"
  fi
}

check kind
check kubectl
check docker

# ── Optionally build & push the image ─────────────────────────────────────────
if $BUILD; then
  header "Building Docker image: ${IMAGE}"
  # Delegates to build.sh which handles scaffold + yarn build + docker build + push
  "${SCRIPT_DIR}/build.sh" --push "${IMAGE}"
fi

# ── Create kind cluster ───────────────────────────────────────────────────────
header "Kind cluster"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation"
else
  info "Creating cluster..."
  kind create cluster \
    --name "${CLUSTER_NAME}" \
    --config "${K8S_DIR}/kind-cluster.yaml"
  success "Cluster created"
fi

kubectl cluster-info --context "kind-${CLUSTER_NAME}" >/dev/null
success "kubectl context set to kind-${CLUSTER_NAME}"

# ── Load image into kind (skips DockerHub pull if built locally) ──────────────
if $BUILD; then
  header "Loading image into kind (no pull needed)"
  kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
  success "Image loaded into kind nodes"
fi

# ── Apply manifests ───────────────────────────────────────────────────────────
header "Applying Kubernetes manifests"

# Patch the deployment image reference
TMP_DEPLOY=$(mktemp)
sed "s|\${DOCKERHUB_USERNAME}/backstage-snow-poc:latest|${IMAGE}|g" \
    "${K8S_DIR}/03-deployment.yaml" > "${TMP_DEPLOY}"

kubectl apply -f "${K8S_DIR}/00-namespace.yaml"
kubectl apply -f "${K8S_DIR}/01-configmap.yaml"
kubectl apply -f "${K8S_DIR}/02-secret.yaml"
kubectl apply -f "${TMP_DEPLOY}"
rm -f "${TMP_DEPLOY}"

success "Manifests applied"

# ── Wait for pod to be ready ──────────────────────────────────────────────────
header "Waiting for pod to be Ready (may take 2-3 min on first pull)"

echo -n "  "
kubectl rollout status deployment/backstage-snow-poc \
    -n "${NAMESPACE}" \
    --timeout=300s && echo ""

success "Deployment ready"

# ── Print access info ─────────────────────────────────────────────────────────
POD=$(kubectl get pod -n "${NAMESPACE}" -l app=backstage-snow-poc \
      -o jsonpath='{.items[0].metadata.name}')

echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  🚀  POC is running!${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Backstage UI      →  ${CYAN}http://localhost:7007${NC}"
echo -e "  ServiceNow mock   →  ${CYAN}http://localhost:8181${NC}"
echo ""
echo -e "  Pod: ${POD}"
echo ""
echo -e "  ${BOLD}Quick smoke test:${NC}"
echo -e "  curl -u admin:admin http://localhost:8181/health"
echo ""
echo -e "  ${BOLD}Logs:${NC}"
echo -e "  kubectl logs -f ${POD} -n ${NAMESPACE}"
echo ""
echo -e "  ${BOLD}Teardown:${NC}"
echo -e "  ./setup.sh --teardown"
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════${NC}"

# ── Switch to real ServiceNow hint ───────────────────────────────────────────
echo ""
echo -e "${YELLOW}💡 To connect a real ServiceNow instance:${NC}"
echo "   1. Edit k8s/01-configmap.yaml → set SERVICENOW_BASE_URL"
echo "   2. Edit k8s/02-secret.yaml    → set SERVICENOW_PASSWORD + SERVICENOW_AUTH_B64"
echo "   3. kubectl apply -f k8s/01-configmap.yaml -f k8s/02-secret.yaml"
echo "   4. kubectl rollout restart deployment/backstage-snow-poc -n ${NAMESPACE}"
echo ""
