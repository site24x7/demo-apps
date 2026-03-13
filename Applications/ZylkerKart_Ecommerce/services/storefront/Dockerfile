# ---- Stage 1: Build ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Copy pre-built Chaos SDK JARs into Maven local repo (not published to Maven Central)
COPY chaos-sdk/ /root/.m2/repository/com/site24x7/labs/

COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre
WORKDIR /app

# Install curl for health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy the built JAR
COPY --from=build /app/target/*.jar app.jar

# Site24x7 Java Agent placeholder
RUN mkdir -p /opt/site24x7

EXPOSE 80

USER appuser

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "app.jar"]
