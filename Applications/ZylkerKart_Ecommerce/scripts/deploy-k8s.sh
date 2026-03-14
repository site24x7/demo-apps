#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Deploy to Kubernetes
# Usage:  ./deploy-k8s.sh                  # full cluster deploy
#         ./deploy-k8s.sh <service-name>   # redeploy a single service
# Example: ./deploy-k8s.sh order-service
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
K8S_DIR="${ROOT_DIR}/k8s"
SERVICES_DIR="${K8S_DIR}/services"
REGISTRY="${DOCKER_REGISTRY:-impazhani}"
TAG="${IMAGE_TAG:-latest}"
SINGLE_SERVICE="${1:-}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        ZylkerKart — Kubernetes Deployment                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Single-service redeploy shortcut ──
if [ -n "$SINGLE_SERVICE" ]; then
    SVC_FILE="${SERVICES_DIR}/${SINGLE_SERVICE}.yaml"
    if [ ! -f "$SVC_FILE" ]; then
        echo "❌ No manifest found at k8s/services/${SINGLE_SERVICE}.yaml"
        echo "   Available services:"
        ls "${SERVICES_DIR}"/*.yaml 2>/dev/null | xargs -n1 basename | sed 's/.yaml$//' | sed 's/^/     - /'
        exit 1
    fi
    echo "▶ Redeploying single service: ${SINGLE_SERVICE}"
    kubectl apply -f "$SVC_FILE"
    kubectl -n zylkerkart rollout restart deployment "${SINGLE_SERVICE}" 2>/dev/null || true
    echo "  ⏳ Waiting for rollout..."
    kubectl -n zylkerkart rollout status deployment "${SINGLE_SERVICE}" --timeout=120s 2>/dev/null || true
    echo "  ✅ ${SINGLE_SERVICE} redeployed"
    echo ""
    kubectl -n zylkerkart get pods -l app="${SINGLE_SERVICE}" -o wide
    exit 0
fi

# ── Prompt for Site24x7 license key ──
read -rp "🔑 Enter Site24x7 APM License Key (leave empty to skip APM): " S247_KEY
echo ""

if [ -n "$S247_KEY" ]; then
    echo "  ✅ APM will be enabled for all services"
else
    echo "  ⚠️  No license key — APM monitoring will be skipped"
fi
echo ""

# ── Step 1: Build images ──
echo "▶ Step 1: Building all Docker images..."
if ! bash "${ROOT_DIR}/scripts/build-all.sh"; then
    echo "❌ Build failed. Aborting deployment."
    exit 1
fi
echo ""

# ── Step 2: Namespace ──
echo "▶ Step 2: Creating namespace..."
kubectl apply -f "${K8S_DIR}/namespace.yaml"
echo "  ✅ Namespace ready"
echo ""

# ── Step 3: ConfigMap (inject Site24x7 key if provided) ──
echo "▶ Step 3: Applying ConfigMap..."
if [ -n "$S247_KEY" ]; then
    echo "  🔑 Injecting Site24x7 license key into ConfigMap"
    sed "s|<your-site24x7-license-key>|${S247_KEY}|g" "${K8S_DIR}/configmap.yaml" | kubectl apply -f -
else
    kubectl apply -f "${K8S_DIR}/configmap.yaml"
fi
echo "  ✅ ConfigMap ready"
echo ""

# ── Step 4: MySQL ──
echo "▶ Step 4: Deploying MySQL..."
kubectl apply -f "${K8S_DIR}/mysql.yaml"
echo "  ⏳ Waiting for MySQL to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod -l app=mysql --timeout=120s 2>/dev/null || true
echo "  ✅ MySQL ready"
echo ""

# ── Step 5: Redis ──
echo "▶ Step 5: Deploying Redis..."
kubectl apply -f "${K8S_DIR}/redis.yaml"
echo "  ⏳ Waiting for Redis to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod -l app=redis --timeout=60s 2>/dev/null || true
echo "  ✅ Redis ready"
echo ""

# ── Step 6: Application services (individual deployments) ──
echo "▶ Step 6: Deploying application services..."
for svc_file in "${SERVICES_DIR}"/*.yaml; do
    svc_name=$(basename "$svc_file" .yaml)
    echo "  ▶ Applying ${svc_name}..."
    kubectl apply -f "$svc_file"
done
echo "  ⏳ Waiting for all pods to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod --all --timeout=180s 2>/dev/null || true
echo "  ✅ Application services ready"
echo ""

# ── Step 7: Ingress ──
echo "▶ Step 7: Applying Ingress..."
kubectl apply -f "${K8S_DIR}/ingress.yaml"
echo "  ✅ Ingress ready"
echo ""

# ── Step 8: Site24x7 Go APM DaemonSet ──
if [ -n "$S247_KEY" ]; then
    echo "▶ Step 8: Deploying Site24x7 Go APM DaemonSet..."
    echo "  🔑 Injecting Site24x7 license key into Go APM ConfigMap"
    sed "s|<your-site24x7-license-key>|${S247_KEY}|g" "${K8S_DIR}/go-apm-daemonset.yaml" | kubectl apply -f -
    echo "  ⏳ Waiting for DaemonSet to roll out..."
    kubectl -n monitoring wait --for=condition=ready pod -l app=site24x7-go-apm --timeout=120s 2>/dev/null || true
    echo "  ✅ Go APM agent ready"
else
    echo "▶ Step 8: Skipping Go APM DaemonSet (no license key)"
fi
echo ""

# ── Step 9: Site24x7 Server Agent ──
if [ -n "$S247_KEY" ]; then
    echo "▶ Step 9: Deploying Site24x7 Server Agent..."
    kubectl create secret generic site24x7-agent --from-literal KEY="${S247_KEY}" --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${K8S_DIR}/site24x7-agent.yaml"
    echo "  ✅ Site24x7 Server Agent deployed"
    echo ""

    # ── Step 10: Add MySQL monitoring to Site24x7 agent ──
    echo "▶ Step 10: Configuring MySQL monitoring in Site24x7 agent..."
    echo "  ⏳ Waiting for Site24x7 agent pod to be ready..."
    kubectl -n default wait --for=condition=ready pod -l app=site24x7-agent --timeout=120s 2>/dev/null || true
    S247_POD=$(kubectl -n default get pod -l app=site24x7-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$S247_POD" ]; then
        echo "  ⏳ Waiting for agent to initialize (60s)..."
        sleep 60
        echo "  ▶ Running mysql --add_instance in pod ${S247_POD}..."
        kubectl -n default exec "${S247_POD}" -- /opt/site24x7/monagent/scripts/AgentManager.sh mysql --add_instance || true
        echo "  ✅ MySQL monitoring configured"
    else
        echo "  ⚠️  Could not find Site24x7 agent pod — MySQL monitoring skipped"
    fi
else
    echo "▶ Step 9: Skipping Site24x7 Server Agent (no license key)"
fi
echo ""

# ── Summary ──
echo "▶ Pod Status:"
kubectl -n zylkerkart get pods -o wide
echo ""
echo "▶ Services:"
kubectl -n zylkerkart get svc
echo ""

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ZylkerKart deployed to Kubernetes!                         ║"
echo "║                                                             ║"
echo "║  Add to /etc/hosts:                                         ║"
echo "║    127.0.0.1  zylkerkart.local                               ║"
echo "║                                                             ║"
echo "║  🛒  Storefront:      http://zylkerkart.local               ║"
echo "║                                                             ║"
echo "║  Or port-forward individual services:                       ║"
echo "║    kubectl -n zylkerkart port-forward svc/storefront 8080:80 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
