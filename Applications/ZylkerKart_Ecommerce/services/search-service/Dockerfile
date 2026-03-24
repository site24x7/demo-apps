# Build stage
FROM golang:1.21-alpine AS builder

ARG GITHUB_TOKEN

WORKDIR /app

# Install git for module downloads
RUN apk add --no-cache git

# Configure git to use token for private GitHub repos
RUN git config --global url."https://${GITHUB_TOKEN}:x-oauth-basic@github.com/".insteadOf "https://github.com/"

# Set GOPRIVATE so Go doesn't try the public proxy for our modules
ENV GOPRIVATE=github.com/site24x7/*

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
