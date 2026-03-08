# Multi-stage build for monolith application
# Build context must be project root (context: . in docker-compose)
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Build shared-lib first
COPY shared-lib/pom.xml shared-lib/pom.xml
RUN mvn -f shared-lib/pom.xml dependency:go-offline -B
COPY shared-lib/src shared-lib/src
RUN mvn -f shared-lib/pom.xml install -DskipTests -B

# Build monolith
COPY monolith/pom.xml monolith/pom.xml
RUN mvn -f monolith/pom.xml dependency:go-offline -B
COPY monolith/src monolith/src
RUN mvn -f monolith/pom.xml package -DskipTests -B

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/monolith/target/*.jar app.jar

EXPOSE 8080

# JVM tuning for benchmarking - configurable via env vars
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
