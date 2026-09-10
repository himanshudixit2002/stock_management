# Two stages: the build tools do not belong in the thing that runs.
#
# Dependencies are resolved in their own layer, before the source is copied, so
# an ordinary code change rebuilds in seconds instead of re-downloading the
# whole Spring dependency tree.
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build

COPY pom.xml .
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Not root. A reporting service reads a database and answers HTTP; nothing it
# does needs the ability to write to its own image.
RUN addgroup -S app && adduser -S app -G app
USER app

COPY --from=build /build/target/reporting-service-*.jar app.jar

# The JVM's default heap sizing predates containers being told their own limits.
# MaxRAMPercentage lets it size against the cgroup rather than the host, which
# is the difference between a container that respects its memory limit and one
# the platform kills.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+UseSerialGC -XX:TieredStopAtLevel=1"
ENV PORT=8081
EXPOSE 8081

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD wget -qO- http://localhost:${PORT}/actuator/health/readiness || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar --server.port=${PORT}"]
