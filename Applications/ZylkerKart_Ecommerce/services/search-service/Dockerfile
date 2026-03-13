# Build stage
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Install git for module downloads
RUN apk add --no-cache git

# Copy Chaos SDK source (local dependency, not published to Go proxy)
COPY chaos-sdk/ ./chaos-sdk/

# Copy all source code
COPY . .

# Resolve dependencies and build
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o search-service .

# Runtime stage
FROM alpine:3.18

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/search-service .

EXPOSE 8083

CMD ["./search-service"]
