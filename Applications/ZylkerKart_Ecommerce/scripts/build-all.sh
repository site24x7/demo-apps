#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Build All Multi-Arch Docker Images
# Usage:  ./build-all.sh
#
# Builds linux/amd64 + linux/arm64 images for all services EXCEPT auth-service
# which only supports linux/amd64 (Site24x7 .NET CLR profiler is x86_64-only).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

TAG="${IMAGE_TAG:-latest}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PUSH_TO_HUB=false
PULL_ONLY=false
REGISTRY="impazhani"

# Multi-arch platforms
MULTI_PLATFORMS="linux/amd64,linux/arm64"
# auth-service: .NET CLR profiler (libClrProfilerAgent.so) is x86_64 only
AUTH_PLATFORMS="linux/amd64"

BUILDX_BUILDER="zylkerkart-builder"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     ZylkerKart — Building All Multi-Arch Docker Images      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Ask: local build / push / pull ──
echo "How would you like to proceed?"
echo "  1) Build locally only (loads to local Docker)"
echo "  2) Build and push to Docker Hub (multi-arch manifest)"
echo "  3) Pull pre-built images from Docker Hub"
read -rp "Enter choice [1/2/3]: " BUILD_CHOICE
echo ""

case "$BUILD_CHOICE" in
    2)
        PUSH_TO_HUB=true
        read -rp "🐳 Docker Hub Registry ID [${REGISTRY}]: " input_reg
        REGISTRY="${input_reg:-$REGISTRY}"
        echo ""
        echo "▶ Logging in to Docker Hub..."
        if ! docker login; then
            echo "❌ Docker login failed. Aborting."
            exit 1
        fi
        echo "  ✅ Docker login successful"
        echo ""
        ;;
    3)
        PULL_ONLY=true
        read -rp "🐳 Docker Hub Registry ID to pull from [${REGISTRY}]: " input_reg
        REGISTRY="${input_reg:-$REGISTRY}"
        echo ""
        ;;
    1|*)
        read -rp "🐳 Image registry prefix [${REGISTRY}]: " input_reg
        REGISTRY="${input_reg:-$REGISTRY}"
        echo ""
        ;;
esac

# ── Skip buildx setup when pulling ──
if [ "$PULL_ONLY" = false ]; then
    echo "▶ Setting up Docker Buildx builder..."
    if ! docker buildx inspect "${BUILDX_BUILDER}" > /dev/null 2>&1; then
        docker buildx create --name "${BUILDX_BUILDER}" --driver docker-container --bootstrap
        echo "  ✅ Created buildx builder: ${BUILDX_BUILDER}"
    else
        echo "  ✅ Using existing buildx builder: ${BUILDX_BUILDER}"
    fi
    docker buildx use "${BUILDX_BUILDER}"
    echo ""
fi

if [ "$PULL_ONLY" = true ]; then
    MODE="pull"
elif [ "$PUSH_TO_HUB" = true ]; then
    MODE="build+push"
else
    MODE="build-local"
fi

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Registry   : ${REGISTRY}"
echo "║  Tag        : ${TAG}"
echo "║  Mode       : ${MODE}"
echo "║  Multi-Arch : ${MULTI_PLATFORMS}"
echo "║  Auth-Only  : ${AUTH_PLATFORMS} (x86_64 profiler)"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# service-name:build-context
SERVICES=(
    "mysql:db"
    "product-service:services/product-service"
    "order-service:services/order-service"
    "search-service:services/search-service"
    "payment-service:services/payment-service"
    "auth-service:services/auth-service"
    "storefront:services/storefront"
)

FAILED=()

for entry in "${SERVICES[@]}"; do
    IFS=':' read -r name path <<< "$entry"
    image="${REGISTRY}/${name}:${TAG}"

    # auth-service only supports amd64 (CLR profiler is x86_64-only)
    if [ "$name" = "auth-service" ]; then
        platforms="${AUTH_PLATFORMS}"
    else
        platforms="${MULTI_PLATFORMS}"
    fi

    echo "────────────────────────────────────────────────────────────────"
    if [ "$PULL_ONLY" = true ]; then
        echo "▶ Pulling ${image}"
    else
        echo "▶ Building ${image}"
        echo "  Context   : ${path}"
        echo "  Platforms : ${platforms}"
    fi
    echo "────────────────────────────────────────────────────────────────"

    if [ "$PULL_ONLY" = true ]; then
        # Pull pre-built image from Docker Hub
        if docker pull "${image}"; then
            echo "✅ ${image} pulled"
        else
            echo "❌ ${image} FAILED"
            FAILED+=("${name}")
        fi
    elif [ "$PUSH_TO_HUB" = true ]; then
        # Build and push multi-arch manifest directly
        BUILD_ARGS=(
            --platform "${platforms}"
            -t "${image}"
            "${ROOT_DIR}/${path}"
        )
        if docker buildx build --push "${BUILD_ARGS[@]}"; then
            echo "✅ ${image} built & pushed (${platforms})"
        else
            echo "❌ ${image} FAILED"
            FAILED+=("${name}")
        fi
    else
        # Local build: --load only works with a single platform, so build
        # for the current host platform and tag it locally
        BUILD_ARGS=(
            --platform "${platforms}"
            -t "${image}"
            "${ROOT_DIR}/${path}"
        )
        if docker buildx build --load "${BUILD_ARGS[@]}"; then
            echo "✅ ${image} built locally (${platforms})"
        else
            echo "❌ ${image} FAILED"
            FAILED+=("${name}")
        fi
    fi
    echo ""
done

echo "════════════════════════════════════════════════════════════════"
if [ ${#FAILED[@]} -eq 0 ]; then
    echo "✅ All ${#SERVICES[@]} images built successfully!"
else
    echo "❌ ${#FAILED[@]} image(s) failed: ${FAILED[*]}"
    exit 1
fi
echo ""

echo "Images:"
docker images --filter "reference=${REGISTRY}/*:${TAG}" --format "  {{.Repository}}:{{.Tag}}\t{{.Size}}"
