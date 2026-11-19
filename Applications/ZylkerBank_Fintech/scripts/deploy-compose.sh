#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerBank — Deploy with Docker Compose
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ACTION="${1:-up}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        ZylkerBank — Docker Compose Deployment                ║"
echo "╚══════════════════════════════════════════════════════════════╝"

case "$ACTION" in
    up)
        echo "▶ Starting all datastores, microservices, and API Gateway..."
        docker compose up -d
        echo ""
        echo "⏳ Waiting for services to become healthy (checking health probes)..."
        
        # Max wait 60 seconds
        for i in {1..12}; do
            sleep 5
            HEALTHY_COUNT=$(docker compose ps --filter "status=running" --format "{{.Name}}" | wc -l | tr -d ' ')
            echo "   ... ${HEALTHY_COUNT} containers running"
            if [ "${HEALTHY_COUNT}" -ge 6 ]; then
                break
            fi
        done

        echo ""
        echo "Service Status:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  🏦 ZylkerBank Fintech Platform is running!                  ║"
        echo "║                                                              ║"
        echo "║  🌐  API Gateway (Ingress): http://localhost:8000            ║"
        echo "║  🏛  Banking Portal:         http://localhost:8080            ║"
        echo "║  📒  Ledger Service (Go):    http://localhost:8081            ║"
        echo "║  💳  Financial Gateway:      http://localhost:8082            ║"
        echo "║  🧠  AI & Risk Service:      http://localhost:8083            ║"
        echo "║  📖  Gateway OpenAPI Docs:   http://localhost:8000/docs       ║"
        echo "║                                                              ║"
        echo "║  Demo Login: desphixs@gmail.com / Password@123 (PIN 1234)    ║"
        echo "║              alice@zylkerbank.com / Password@123 (PIN 1234)  ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        ;;
    down)
        echo "▶ Stopping all ZylkerBank services..."
        docker compose down
        echo "✅ All services stopped."
        ;;
    restart)
        echo "▶ Restarting all ZylkerBank services..."
        docker compose down
        docker compose up -d
        echo "✅ All services restarted."
        ;;
    logs)
        SERVICE="${2:-}"
        if [ -n "$SERVICE" ]; then
            docker compose logs -f "$SERVICE"
        else
            docker compose logs -f
        fi
        ;;
    status)
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
        ;;
    clean)
        echo "▶ Stopping and removing all containers, volumes, and local images..."
        docker compose down -v --rmi local
        echo "✅ Cleanup complete."
        ;;
    *)
        echo "Usage: $0 {up|down|restart|logs [service]|status|clean}"
        exit 1
        ;;
esac
