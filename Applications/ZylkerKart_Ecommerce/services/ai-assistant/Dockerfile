FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appgroup && useradd -r -g appgroup appuser

COPY --from=builder /install /usr/local
COPY app/ ./app/

ENV PORT=8086
ENV PYTHONUNBUFFERED=1
ENV OTEL_SERVICE_NAME=zylkerkart-ai-assistant

USER appuser

EXPOSE 8086

HEALTHCHECK --interval=20s --timeout=5s --start-period=20s --retries=5 \
  CMD curl -f http://localhost:8086/health || exit 1

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8086"]