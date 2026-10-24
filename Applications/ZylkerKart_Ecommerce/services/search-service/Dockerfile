# syntax=docker/dockerfile:1
# Build stage
FROM golang:1.25-alpine AS builder

# Mirror the repo layout so go.mod's replace path resolves
WORKDIR /repo/Applications/ZylkerKart_Ecommerce/services/search-service

# Chaos SDK comes from the repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs go/ /repo/chaos-libs/go/

# Download dependencies first (better layer caching)
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o /out/search-service .

# Runtime stage
FROM alpine:3.18

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copy binary from builder
COPY --from=builder /out/search-service .

EXPOSE 8083

CMD ["./search-service"]
