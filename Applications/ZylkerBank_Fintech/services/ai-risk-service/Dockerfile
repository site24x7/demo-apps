# syntax=docker/dockerfile:1
# ── Stage 1: Build dependencies ──────────────────────────────
FROM python:3.11-slim AS builder

# Mirror the repo layout so requirements.txt's --find-links path resolves
WORKDIR /repo/Applications/ZylkerBank_Fintech/services/ai-risk-service

# Chaos SDK comes from the repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs python/ /repo/chaos-libs/python/

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM python:3.11-slim

WORKDIR /app

# curl for healthchecks; procps for chaos tooling (pkill/pgrep)
RUN apt-get update && apt-get install -y --no-install-recommends curl procps \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appgroup && useradd -r -g appgroup appuser

COPY --from=builder /install /usr/local
COPY app/ ./app/

ENV PORT=8083
ENV PYTHONUNBUFFERED=1
ENV CHAOS_SDK_ENABLED=true
ENV CHAOS_SDK_APP_NAME=ai-risk-service
ENV CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults

USER appuser

EXPOSE 8083

HEALTHCHECK --interval=20s --timeout=5s --start-period=15s --retries=3 \
  CMD curl -f http://localhost:8083/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8083"]
