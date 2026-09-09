# ---- Stage 1: Build ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Seed local m2 with Chaos SDK (offline fallback when GitHub Packages auth fails)
COPY vendor/chaos/ /tmp/chaos-vendor/
RUN mvn install:install-file -Dfile=/tmp/chaos-vendor/chaos-sdk-core-1.1.2.jar \
      -DpomFile=/tmp/chaos-vendor/chaos-sdk-core-1.1.2.pom \
      -DgroupId=com.site24x7.labs -DartifactId=chaos-sdk-core -Dversion=1.1.2 -Dpackaging=jar && \
    mvn install:install-file -Dfile=/tmp/chaos-vendor/chaos-sdk-spring-boot-3-1.1.2.jar \
      -DpomFile=/tmp/chaos-vendor/chaos-sdk-spring-boot-3-1.1.2.pom \
      -DgroupId=com.site24x7.labs -DartifactId=chaos-sdk-spring-boot-3 -Dversion=1.1.2 -Dpackaging=jar

# Optional GitHub Packages auth still supported for other deps
ARG GITHUB_TOKEN
RUN mkdir -p /root/.m2 && printf '<settings>\n  <servers>\n    <server>\n      <id>github</id>\n      <username>token</username>\n      <password>%s</password>\n    </server>\n  </servers>\n</settings>' "$GITHUB_TOKEN" > /root/.m2/settings.xml

COPY pom.xml .
RUN mvn dependency:go-offline -B || true
COPY src ./src
RUN mvn package -DskipTests -B

# ---- Stage 2: Runtime ----
FROM eclipse-temurin:17-jre
WORKDIR /app

# Create non-root user
RUN groupadd -r appgroup && useradd -r -g appgroup appuser

# Copy the built JAR
COPY --from=build /app/target/*.jar app.jar

# Site24x7 Java Agent placeholder
RUN mkdir -p /opt/site24x7

EXPOSE 8081

USER appuser

ENTRYPOINT ["java", "-Xms256m", "-Xmx512m", "-jar", "app.jar"]
