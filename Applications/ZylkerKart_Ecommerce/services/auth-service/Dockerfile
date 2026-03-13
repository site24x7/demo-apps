# ── Stage 1: Build ────────────────────────────────────────────
FROM --platform=linux/amd64 mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY AuthService.csproj ./
COPY chaos-sdk/ ./chaos-sdk/
RUN dotnet restore

# Copy app source files only (not chaos-sdk again — already restored above)
COPY appsettings.json ./
COPY Program.cs ./
COPY Controllers/ ./Controllers/
COPY Data/ ./Data/
COPY DTOs/ ./DTOs/
COPY Models/ ./Models/
COPY Services/ ./Services/
RUN dotnet publish -c Release -o /app/publish --no-restore

# ── Stage 2: Runtime ─────────────────────────────────────────
FROM --platform=linux/amd64 mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app

# Add non-root user and install curl for healthcheck
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/* \
    && groupadd -r appgroup && useradd -r -g appgroup appuser

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8085
ENV PORT=8085
ENV CHAOS_SDK_ENABLED=true
ENV CHAOS_SDK_APP_NAME=auth-service
ENV CHAOS_SDK_CONFIG_DIR=/var/site24x7-labs/faults

USER appuser

EXPOSE 8085

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -f http://localhost:8085/health || exit 1

ENTRYPOINT ["dotnet", "AuthService.dll"]
