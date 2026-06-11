FROM maven:3.9-eclipse-temurin-21-alpine AS builder

WORKDIR /app

COPY Springboot-API-REST-DESPACHO/pom.xml ./
RUN mvn dependency:go-offline -B

COPY Springboot-API-REST-DESPACHO/src ./src
RUN mvn package -DskipTests -B

FROM eclipse-temurin:21-jre-alpine AS production

RUN apk add --no-cache wget

WORKDIR /app

# Crear usuario no root para ejecutar la app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /app/target/*.jar app.jar

# Asignar permisos al usuario no root
RUN chown appuser:appgroup app.jar

USER appuser

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD wget -qO- http://localhost:8082/actuator/health || exit 1

ENV SPRING_PROFILES_ACTIVE=prod \
    JAVA_OPTS="-Xms256m -Xmx512m"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
