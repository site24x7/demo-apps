# syntax=docker/dockerfile:1
# ── Stage 1: Build dependencies ──────────────────────────────
FROM python:3.11-slim AS builder

# Mirror the repo layout so requirements.txt's --find-links path resolves
WORKDIR /repo/Applications/ZylkerKart_Ecommerce/services/payment-service

# Chaos SDK comes from the repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs python/ /repo/chaos-libs/python/

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# Install procps (provides pkill/pgrep/ps) for chaos tooling
RUN apt-get update && apt-get install -y --no-install-recommends procps && rm -rf /var/lib/apt/lists/*

# Add non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy installed packages
COPY --from=builder /install /usr/local

# Copy application
COPY app/ ./app/

ENV PORT=8084
ENV PYTHONUNBUFFERED=1
ENV CHAOS_SDK_ENABLED=true
ENV CHAOS_SDK_APP_NAME=payment-service
ENV CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults

USER appuser

EXPOSE 8084

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8084/health')" || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8084"]
