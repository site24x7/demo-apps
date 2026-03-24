# ── Stage 1: Build ────────────────────────────────────────────
FROM node:18-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only (Chaos SDK pulled from npm registry)
RUN npm install --omit=dev && npm cache clean --force

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM node:18-alpine

WORKDIR /app

# Add non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application source
COPY package*.json ./
COPY src/ ./src/

# Set environment
ENV NODE_ENV=production
ENV PORT=8082

# Switch to non-root user
USER appuser

EXPOSE 8082

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8082/health || exit 1

CMD ["node", "src/app.js"]
