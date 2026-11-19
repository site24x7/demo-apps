# syntax=docker/dockerfile:1
# ---- Stage 1: Build ----
FROM maven:3.9-eclipse-temurin-17 AS build

# Mirror repo layout so pom.xml's relative chaos-libs repository resolves
WORKDIR /repo/Applications/ZylkerBank_Fintech/services/banking-portal

# Chaos SDK comes from repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs java/ /repo/chaos-libs/java/

COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre
WORKDIR /app

# Install curl for container health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy the built application JAR
COPY --from=build /repo/Applications/ZylkerBank_Fintech/services/banking-portal/target/*.jar app.jar

# Site24x7 Java Agent placeholder directory
RUN mkdir -p /opt/site24x7

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=3 CMD curl -f http://localhost:8080/health || exit 1

USER appuser

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "app.jar"]
