# Runs the agent built by `bal build` (target/bin/agentcore_runtime_agent.jar) on port 8080.
# AgentCore Runtime requires an ARM64 image:
#   bal build
#   docker build --platform linux/arm64 -t agentcore-runtime-agent:v1 .
# No configuration is copied into the image: pass it as environment variables.
FROM --platform=linux/arm64 eclipse-temurin:25-jre

RUN useradd --system --create-home --uid 10001 ballerina
WORKDIR /home/ballerina
COPY --chown=ballerina target/bin/agentcore_runtime_agent.jar agent.jar
USER 10001

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "agent.jar"]
