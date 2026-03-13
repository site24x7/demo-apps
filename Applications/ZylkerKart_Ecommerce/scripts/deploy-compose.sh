#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# ZylkerKart — Deploy with Docker Compose
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ACTION="${1:-up}"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        ZylkerKart — Docker Compose Deployment               ║"
echo "╚══════════════════════════════════════════════════════════════╝"

case "$ACTION" in
    up)
        echo "▶ Building and starting all services..."
        docker compose up --build -d
        echo ""
        echo "⏳ Waiting for services to become healthy..."
        sleep 10

        echo ""
        echo "Service Status:"
        docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

        echo ""
        echo "╔══════════════════════════════════════════════════════════════╗"
        echo "║  ZylkerKart is running!                                     ║"
        echo "║                                                             ║"
        echo "║  🛒  Storefront:      http://localhost:8080                 ║"
        echo "║  📦  Product Service:  http://localhost:8081                 ║"
        echo "║  🛍  Order Service:    http://localhost:8082                 ║"
        echo "║  �  Search:           http://localhost:8083                 ║"
        echo "║  💳  Payment:          http://localhost:8084                 ║"
        echo "║  🔐  Auth:             http://localhost:8085                 ║"
        echo "║                                                             ║"
        echo "║  Demo login: demo@zylkerkart.com / Demo@123                ║"
        echo "╚══════════════════════════════════════════════════════════════╝"
        ;;
    down)
        echo "▶ Stopping all services..."
        docker compose down
        echo "✅ All services stopped."
        ;;
    restart)
        echo "▶ Restarting all services..."
        docker compose down
        docker compose up --build -d
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
        echo "▶ Stopping and removing all containers, volumes, and images..."
        docker compose down -v --rmi local
        echo "✅ Cleanup complete."
        ;;
    *)
        echo "Usage: $0 {up|down|restart|logs [service]|status|clean}"
        exit 1
        ;;
esac
