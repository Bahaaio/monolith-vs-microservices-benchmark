# Multi-stage build for product-service
# Build context must be project root (context: . in docker-compose)
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app

# Build shared-lib first
COPY shared-lib/pom.xml shared-lib/pom.xml
RUN mvn -f shared-lib/pom.xml dependency:go-offline -B
COPY shared-lib/src shared-lib/src
RUN mvn -f shared-lib/pom.xml install -DskipTests -B

# Build product-service
COPY microservices/product-service/pom.xml microservices/product-service/pom.xml
RUN mvn -f microservices/product-service/pom.xml dependency:go-offline -B
COPY microservices/product-service/src microservices/product-service/src
RUN mvn -f microservices/product-service/pom.xml package -DskipTests -B

FROM eclipse-temurin:17-jre-jammy
WORKDIR /app
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/microservices/product-service/target/*.jar app.jar
EXPOSE 8080
ENV JAVA_OPTS="-Xms128m -Xmx256m -XX:+UseG1GC -XX:MaxGCPauseMillis=200"
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
