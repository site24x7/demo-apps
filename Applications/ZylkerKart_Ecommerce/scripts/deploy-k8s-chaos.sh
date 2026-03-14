#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart + Site24x7 Chaos Engineering — Deploy to Kubernetes
#
# Deploys pre-built chaos-enabled images (impazhani/*:chaos) with:
#   - Site24x7 Chaos SDK on all 6 microservices
#   - Site24x7 APM agents (Java, Node.js, Python, .NET, Go eBPF)
#   - Site24x7 Server Monitoring agent (DaemonSet)
#   - kube-state-metrics for Kubernetes monitoring
#
# Usage:  ./deploy-k8s-chaos.sh                  # full cluster deploy
#         ./deploy-k8s-chaos.sh <service-name>   # redeploy a single service
# Example: ./deploy-k8s-chaos.sh order-service
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEPLOY_DIR="${ROOT_DIR}/k8s/deploy"
SINGLE_SERVICE="${1:-}"

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ZylkerKart + Site24x7 Chaos Engineering — K8s Deployment       ║"
echo "║  Images: impazhani/*:chaos (pre-built, no build step)           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

# ── Single-service redeploy shortcut ──
if [ -n "$SINGLE_SERVICE" ]; then
    echo "▶ Redeploying single service: ${SINGLE_SERVICE}"
    echo "  ▶ Re-applying 05-services.yaml..."
    kubectl apply -f "${DEPLOY_DIR}/05-services.yaml"
    kubectl -n zylkerkart rollout restart deployment "${SINGLE_SERVICE}" 2>/dev/null || true
    echo "  ⏳ Waiting for rollout..."
    kubectl -n zylkerkart rollout status deployment "${SINGLE_SERVICE}" --timeout=180s 2>/dev/null || true
    echo "  ✅ ${SINGLE_SERVICE} redeployed"
    echo ""
    kubectl -n zylkerkart get pods -l app="${SINGLE_SERVICE}" -o wide
    exit 0
fi

# ── Prompt for Site24x7 license key ──
read -rp "🔑 Enter Site24x7 License Key (leave empty to skip APM + monitoring): " S247_KEY
echo ""

if [ -n "$S247_KEY" ]; then
    echo "  ✅ APM + Server monitoring will be enabled"
else
    echo "  ⚠️  No license key — APM and server monitoring will be skipped"
fi
echo ""

# ── Step 1: Namespace ──
echo "▶ Step 1: Creating namespace..."
kubectl apply -f "${DEPLOY_DIR}/01-namespace.yaml"
echo "  ✅ Namespace 'zylkerkart' ready"
echo ""

# ── Step 2: ConfigMap (inject Site24x7 key if provided) ──
echo "▶ Step 2: Applying ConfigMap..."
if [ -n "$S247_KEY" ]; then
    echo "  🔑 Injecting Site24x7 license key into ConfigMap"
    sed "s|<your-site24x7-license-key>|${S247_KEY}|g" "${DEPLOY_DIR}/02-configmap.yaml" | kubectl apply -f -
else
    kubectl apply -f "${DEPLOY_DIR}/02-configmap.yaml"
fi
echo "  ✅ ConfigMap ready"
echo ""

# ── Step 3: MySQL ──
echo "▶ Step 3: Deploying MySQL..."
kubectl apply -f "${DEPLOY_DIR}/03-mysql.yaml"
echo "  ⏳ Waiting for MySQL to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod -l app=mysql --timeout=120s 2>/dev/null || true
echo "  ✅ MySQL ready"
echo ""

# ── Step 4: Redis ──
echo "▶ Step 4: Deploying Redis..."
kubectl apply -f "${DEPLOY_DIR}/04-redis.yaml"
echo "  ⏳ Waiting for Redis to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod -l app=redis --timeout=60s 2>/dev/null || true
echo "  ✅ Redis ready"
echo ""

# ── Step 5: Application services (chaos SDK + APM agents) ──
echo "▶ Step 5: Deploying application services (chaos SDK + APM)..."
kubectl apply -f "${DEPLOY_DIR}/05-services.yaml"
echo "  ⏳ Waiting for all pods to be ready..."
kubectl -n zylkerkart wait --for=condition=ready pod --all --timeout=300s 2>/dev/null || true
echo "  ✅ Application services ready"
echo ""

# ── Step 6: Site24x7 Server Monitoring Agent ──
if [ -n "$S247_KEY" ]; then
    echo "▶ Step 6: Deploying Site24x7 Server Monitoring Agent..."
    # Create/update the secret with the license key
    kubectl create secret generic site24x7-agent \
        --namespace=default \
        --from-literal KEY="${S247_KEY}" \
        --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${DEPLOY_DIR}/06-site24x7-agent.yaml"
    echo "  ⏳ Waiting for Site24x7 agent pods to be ready..."
    kubectl -n default wait --for=condition=ready pod -l app=site24x7-agent --timeout=120s 2>/dev/null || true
    echo "  ✅ Site24x7 Server Agent deployed"
    echo ""

    # ── MySQL monitoring auto-discovery ──
    echo "  ▶ Configuring MySQL monitoring in Site24x7 agent..."
    echo "  ⏳ Waiting for agent to initialize (60s)..."
    sleep 60
    S247_POD=$(kubectl -n default get pod -l app=site24x7-agent -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$S247_POD" ]; then
        echo "  ▶ Running mysql --add_instance in pod ${S247_POD}..."
        kubectl -n default exec "${S247_POD}" -- \
            /opt/site24x7/monagent/scripts/AgentManager.sh mysql --add_instance || true
        echo "  ✅ MySQL monitoring configured"
    else
        echo "  ⚠️  Could not find Site24x7 agent pod — MySQL monitoring skipped"
    fi
else
    echo "▶ Step 6: Skipping Site24x7 Server Agent (no license key)"
fi
echo ""

# ── Step 7: Site24x7 Go APM DaemonSet (eBPF) ──
if [ -n "$S247_KEY" ]; then
    echo "▶ Step 7: Deploying Site24x7 Go APM DaemonSet (eBPF)..."
    echo "  🔑 Injecting Site24x7 license key into Go APM ConfigMap"
    sed "s|<your-site24x7-license-key>|${S247_KEY}|g" "${DEPLOY_DIR}/07-go-apm-daemonset.yaml" | kubectl apply -f -
    echo "  ⏳ Waiting for Go APM agent to be ready..."
    kubectl -n monitoring wait --for=condition=ready pod -l app=site24x7-go-apm --timeout=120s 2>/dev/null || true
    echo "  ✅ Go APM agent ready"
else
    echo "▶ Step 7: Skipping Go APM DaemonSet (no license key)"
fi
echo ""

# ── Summary ──
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  Deployment Complete!                                           ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
echo "▶ ZylkerKart Pods (namespace: zylkerkart):"
kubectl -n zylkerkart get pods -o wide
echo ""
echo "▶ ZylkerKart Services:"
kubectl -n zylkerkart get svc
echo ""

if [ -n "$S247_KEY" ]; then
    echo "▶ Site24x7 Agent Pods (namespace: default):"
    kubectl -n default get pods -l app=site24x7-agent -o wide 2>/dev/null || true
    echo ""
    echo "▶ Go APM Agent Pods (namespace: monitoring):"
    kubectl -n monitoring get pods -l app=site24x7-go-apm -o wide 2>/dev/null || true
    echo ""
fi

echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║  ZylkerKart + Site24x7 Chaos Engineering deployed!              ║"
echo "║                                                                  ║"
echo "║  🛒 Storefront (LoadBalancer):                                   ║"
echo "║     kubectl -n zylkerkart get svc storefront-lb                  ║"
echo "║                                                                  ║"
echo "║  Or port-forward:                                                ║"
echo "║     kubectl -n zylkerkart port-forward svc/storefront 8080:80    ║"
echo "║                                                                  ║"
echo "║  Chaos SDK: Active on all 6 services                             ║"
echo "║  APM:       $([ -n "$S247_KEY" ] && echo "Enabled" || echo "Disabled (no license key)")                                      ║"
echo "║  Monitoring: $([ -n "$S247_KEY" ] && echo "Enabled" || echo "Disabled (no license key)")                                     ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
