# syntax=docker/dockerfile:1
# ---- Stage 1: Build ----
FROM maven:3.9-eclipse-temurin-17 AS build

# Mirror the repo layout so pom.xml's relative chaos-libs repository resolves
WORKDIR /repo/Applications/ZylkerKart_Ecommerce/services/product-service

# Chaos SDK comes from the repo-root chaos-libs/ (named build context)
COPY --from=chaos-libs java/ /repo/chaos-libs/java/

COPY pom.xml .
RUN mvn dependency:go-offline -B
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre
WORKDIR /app

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy the built JAR
COPY --from=build /repo/Applications/ZylkerKart_Ecommerce/services/product-service/target/*.jar app.jar

# Site24x7 Java Agent placeholder
RUN mkdir -p /opt/site24x7

EXPOSE 8081

USER appuser

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "app.jar"]
