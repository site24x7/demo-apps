# syntax=docker/dockerfile:1
# ── Stage 1: Build dependencies ──────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /repo/Applications/ZylkerBank_Fintech/services/api-gateway

# Chaos SDK comes from the repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs python/ /repo/chaos-libs/python/

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl procps \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appgroup && useradd -r -g appgroup appuser

COPY --from=builder /install /usr/local
COPY app/ ./app/

ENV PORT=8000
ENV PYTHONUNBUFFERED=1
ENV CHAOS_SDK_ENABLED=true
ENV CHAOS_SDK_APP_NAME=api-gateway
ENV CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
