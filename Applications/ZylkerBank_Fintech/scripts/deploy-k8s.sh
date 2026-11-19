#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerBank — Deploy to Kubernetes
# Usage:
#   ./deploy-k8s.sh                  # Full cluster deployment
#   ./deploy-k8s.sh <service-name>   # Redeploy a single microservice
#   ./deploy-k8s.sh status           # Show cluster pod and service status
#   ./deploy-k8s.sh delete           # Teardown the zylkerbank namespace
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
K8S_DIR="${ROOT_DIR}/k8s"
TARGET="${1:-}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        ZylkerBank — Kubernetes Deployment                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Teardown shortcut ──
if [ "$TARGET" = "delete" ] || [ "$TARGET" = "down" ]; then
    echo "▶ Deleting ZylkerBank namespace and resources..."
    kubectl delete namespace zylkerbank --ignore-not-found=true
    echo "✅ ZylkerBank resources deleted."
    exit 0
fi

# ── Status shortcut ──
if [ "$TARGET" = "status" ]; then
    echo "Pods in namespace 'zylkerbank':"
    kubectl -n zylkerbank get pods -o wide
    echo ""
    echo "Services in namespace 'zylkerbank':"
    kubectl -n zylkerbank get svc
    echo ""
    echo "Ingress in namespace 'zylkerbank':"
    kubectl -n zylkerbank get ingress
    exit 0
fi

# ── Single-service redeploy shortcut ──
SERVICES=("api-gateway" "banking-portal" "ledger-service" "financial-gateway" "ai-risk-service")
if [ -n "$TARGET" ]; then
    MATCH=false
    for svc in "${SERVICES[@]}"; do
        if [ "$svc" = "$TARGET" ]; then
            MATCH=true
            break
        fi
    done

    if [ "$MATCH" = true ]; then
        echo "▶ Redeploying single service: ${TARGET}"
        kubectl -n zylkerbank rollout restart deployment "${TARGET}"
        echo "⏳ Waiting for rollout to complete..."
        kubectl -n zylkerbank rollout status deployment "${TARGET}" --timeout=120s
        echo "✅ ${TARGET} redeployed successfully."
        echo ""
        kubectl -n zylkerbank get pods -l app="${TARGET}" -o wide
        exit 0
    else
        echo "❌ Unknown command or service: ${TARGET}"
        echo "   Usage: $0 {all|<service-name>|status|delete}"
        echo "   Available services: ${SERVICES[*]}"
        exit 1
    fi
fi

# ── Check kubectl connectivity ──
echo "▶ Checking Kubernetes cluster connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    echo "❌ Cannot connect to Kubernetes cluster via kubectl. Please check your kubeconfig."
    exit 1
fi
echo "  ✅ Cluster reachable"
echo ""

# ── Optional Site24x7 APM Key Prompt ──
S247_KEY="${S247_LICENSE_KEY:-}"
if [ -z "$S247_KEY" ]; then
    read -rp "🔑 Enter Site24x7 APM License Key (leave empty to run without APM): " S247_KEY
    echo ""
fi

# ── Step 1: Namespace ──
echo "▶ Step 1: Applying Namespace..."
kubectl apply -f "${K8S_DIR}/00-namespace.yaml"
echo "  ✅ Namespace 'zylkerbank' ready"
echo ""

# ── Step 2: ConfigMap & Secrets ──
echo "▶ Step 2: Applying ConfigMap and Secrets..."
if [ -n "$S247_KEY" ]; then
    echo "  🔑 Injecting Site24x7 license key & enabling APM..."
    sed -e "s|S247_APM_ENABLED: \"false\"|S247_APM_ENABLED: \"true\"|g" \
        -e "s|S247_LICENSE_KEY: \"\"|S247_LICENSE_KEY: \"${S247_KEY}\"|g" \
        "${K8S_DIR}/01-configmap-secrets.yaml" | kubectl apply -f -
else
    kubectl apply -f "${K8S_DIR}/01-configmap-secrets.yaml"
fi
echo "  ✅ ConfigMap and Secrets ready"
echo ""

# ── Step 3: Database Init ConfigMaps ──
echo "▶ Step 3: Applying Database Initialization ConfigMaps..."
kubectl apply -f "${K8S_DIR}/02-db-init-configmaps.yaml"
echo "  ✅ Database SQL schemas configured"
echo ""

# ── Step 4: Datastores (Oracle, Postgres, Kafka) ──
echo "▶ Step 4: Deploying Datastores (Oracle 23c Free, PostgreSQL 16, Kafka KRaft)..."
kubectl apply -f "${K8S_DIR}/03-datastores.yaml"
echo "  ⏳ Waiting for PostgreSQL to become ready..."
kubectl -n zylkerbank rollout status deployment postgres --timeout=120s || true
echo "  ⏳ Waiting for Kafka to become ready..."
kubectl -n zylkerbank rollout status deployment kafka --timeout=120s || true
echo "  ⏳ Waiting for Oracle 23c Free to become ready..."
kubectl -n zylkerbank rollout status deployment oracle-db --timeout=180s || true
echo "  ✅ Datastores running"
echo ""

# ── Step 5: Application Microservices ──
echo "▶ Step 5: Deploying Application Microservices..."
kubectl apply -f "${K8S_DIR}/04-services.yaml"
echo "  ⏳ Waiting for API Gateway and microservices rollout..."
for svc in "${SERVICES[@]}"; do
    echo "     - Rolling out ${svc}..."
    kubectl -n zylkerbank rollout status deployment "${svc}" --timeout=180s || true
done
echo "  ✅ All microservices deployed"
echo ""

# ── Step 6: Ingress ──
echo "▶ Step 6: Applying Ingress..."
kubectl apply -f "${K8S_DIR}/05-ingress.yaml"
echo "  ✅ Ingress rules ready"
echo ""

# ── Step 7: Optional Site24x7 Go eBPF DaemonSet ──
if [ -n "$S247_KEY" ]; then
    echo "▶ Step 7: Deploying Site24x7 Go eBPF APM DaemonSet..."
    kubectl apply -f "${K8S_DIR}/06-go-apm-daemonset.yaml"
    echo "  ✅ Go eBPF APM agent deployed"
    echo ""
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  🏦 ZylkerBank Fintech Platform is deployed on Kubernetes!  ║"
echo "║                                                              ║"
echo "║  🌐 Ingress Entrypoint:  http://localhost/ (or cluster IP)   ║"
echo "║  📖 API Documentation:   http://localhost/docs               ║"
echo "║                                                              ║"
echo "║  Port-forwarding shortcuts for testing without Ingress:      ║"
echo "║    kubectl -n zylkerbank port-forward svc/api-gateway 8000:8000║"
echo "║    kubectl -n zylkerbank port-forward svc/banking-portal 8080:8080║"
echo "║                                                              ║"
echo "║  Demo Login: desphixs@gmail.com / Password@123 (PIN 1234)    ║"
echo "║              alice@zylkerbank.com / Password@123 (PIN 1234)  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
kubectl -n zylkerbank get pods -o wide
