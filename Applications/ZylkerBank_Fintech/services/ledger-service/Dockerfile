# syntax=docker/dockerfile:1
# Build stage
FROM golang:1.26-alpine AS builder

# Mirror repo layout so go.mod replace directive resolves
WORKDIR /repo/Applications/ZylkerBank_Fintech/services/ledger-service

# Chaos SDK from named build context
COPY --from=chaos-libs go/ /repo/chaos-libs/go/

# Download dependencies first (cached layers)
COPY go.mod go.sum ./
RUN go mod download

# Copy source code and build statically linked binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags="-w -s" -o /out/ledger-service .

# Runtime stage
FROM alpine:3.19

RUN apk --no-cache add ca-certificates tzdata wget

WORKDIR /app

# Copy binary from builder
COPY --from=builder /out/ledger-service .

EXPOSE 8081

CMD ["./ledger-service"]
