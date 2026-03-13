# ── Stage 1: Generate SQL seed from CSV using Python ─────────
FROM python:3.11-slim AS seed-builder

WORKDIR /build

# Copy CSV and seed generator script
COPY product_datasets.csv .
COPY seed/generate_seed_sql.py .

# Generate the SQL insert file from CSV
RUN python generate_seed_sql.py product_datasets.csv /build/02-seed.sql

# ── Stage 2: Final MySQL image (no Python) ───────────────────
FROM mysql:8.0

# Copy schema SQL (runs first alphabetically)
COPY 01-schema.sql /docker-entrypoint-initdb.d/01-schema.sql

# Copy generated seed SQL from builder
COPY --from=seed-builder /build/02-seed.sql /docker-entrypoint-initdb.d/02-seed.sql
