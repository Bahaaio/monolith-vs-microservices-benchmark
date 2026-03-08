# Multi-stage build for API gateway
# Build context must be project root (context: . in docker-compose)
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Build gateway (no shared-lib dependency needed)
COPY microservices/gateway/pom.xml microservices/gateway/pom.xml
RUN mvn -f microservices/gateway/pom.xml dependency:go-offline -B
COPY microservices/gateway/src microservices/gateway/src
RUN mvn -f microservices/gateway/pom.xml package -DskipTests -B

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/microservices/gateway/target/*.jar app.jar
EXPOSE 8080
ENV JAVA_OPTS="-Xms128m -Xmx256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
