# AgentCore Runtime agent

A Ballerina `ai:Agent` that runs on [Amazon Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agents-tools-runtime.html) under the [HTTP protocol contract](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html). It uses `bedrock:ConverseModelProvider` with the default AWS credential chain, and keeps one conversation history per user and session.

The service accepts `{"prompt": "..."}` on `POST /invocations` and answers `{"response": "..."}`.

## Run locally

```bash
cp Config.toml.template Config.toml   # fill in modelId and region; never commit Config.toml
bal run
```

```bash
curl -s localhost:8080/ping
curl -s localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -H 'X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: local-session-0123456789-0123456789' \
  -d '{"prompt": "Hello"}'
```

The body is always read as JSON. A `string` payload parameter expects a JSON string, so send `-d '"hello"'`, not `-d hello`. A body that doesn't bind to the declared type gets `400`.

## Build the ARM64 image

AgentCore Runtime requires an ARM64 image.

```bash
bal build
docker build --platform linux/arm64 -t agentcore-runtime-agent:v1 .
```

No configuration is baked into the image.

## Push to Amazon ECR

```bash
aws ecr create-repository --repository-name agentcore-runtime-agent --region <REGION>
aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
docker tag agentcore-runtime-agent:v1 <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/agentcore-runtime-agent:v1
docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/agentcore-runtime-agent:v1
```

## Create the runtime

The execution role must allow AgentCore to pull the image, write logs, and call `bedrock:InvokeModel` (and `bedrock:InvokeModelWithResponseStream` if you stream) on the model you configure. See [the runtime permissions](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html).

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --region <REGION> \
  --agent-runtime-name agentcore_runtime_agent \
  --agent-runtime-artifact 'containerConfiguration={containerUri=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/agentcore-runtime-agent:v1}' \
  --role-arn <EXECUTION_ROLE_ARN> \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --environment-variables BAL_CONFIG_VAR_MODELID=<MODEL_ID>,BAL_CONFIG_VAR_REGION=<REGION>
```

### Enable MMDSv2 before the first invocation

Since June 30, 2026, AgentCore Runtime rejects invocations of a runtime whose `metadataConfiguration.requireMMDSV2` is not `true` ([troubleshooting](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-troubleshooting.html)). The setting is accepted only by `UpdateAgentRuntime`: in the AWS API model (botocore `bedrock-agentcore-control`), `metadataConfiguration` is a member of `UpdateAgentRuntimeRequest`, not of `CreateAgentRuntimeRequest`.

Update the runtime once it is created, and invoke it only after the update. Re-send every field the create call set: the API model doesn't say whether omitted optional fields are kept, and losing the environment variables would stop the agent at startup. If you set `--request-header-configuration` or other options on create, send them again too.

```bash
aws bedrock-agentcore-control update-agent-runtime \
  --region <REGION> \
  --agent-runtime-id <AGENT_RUNTIME_ID> \
  --agent-runtime-artifact 'containerConfiguration={containerUri=<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/agentcore-runtime-agent:v1}' \
  --role-arn <EXECUTION_ROLE_ARN> \
  --network-configuration networkMode=PUBLIC \
  --protocol-configuration serverProtocol=HTTP \
  --environment-variables BAL_CONFIG_VAR_MODELID=<MODEL_ID>,BAL_CONFIG_VAR_REGION=<REGION> \
  --metadata-configuration requireMMDSV2=true

aws bedrock-agentcore-control get-agent-runtime --region <REGION> --agent-runtime-id <AGENT_RUNTIME_ID> \
  --query '{status: status, requireMMDSV2: metadataConfiguration.requireMMDSV2, env: keys(environmentVariables)}'
```

Wait until the status is `READY`. The default credential chain reads the execution role from the metadata service with IMDSv2 session tokens, which MMDSv2 requires.

## Configuration through environment variables

Ballerina reads a configurable from an environment variable named `BAL_CONFIG_VAR_` followed by the configurable's key in upper case, with `.` replaced by `_`. For this package's root module the key is just the variable name, so `modelId` is `BAL_CONFIG_VAR_MODELID` and `region` is `BAL_CONFIG_VAR_REGION`. A configurable in another module is `BAL_CONFIG_VAR_<ORG>_<MODULE>_<NAME>`.

Every `BAL_CONFIG_VAR_*` variable must match a configurable: an unused one is an error and the agent doesn't start. AgentCore allows 4 KB of environment variables in total.

## Invoke

The session ID must be at least 33 characters long. Calls with the same session ID reach the same session, and the agent keeps their history.

```bash
aws bedrock-agentcore invoke-agent-runtime \
  --region <REGION> \
  --agent-runtime-arn <AGENT_RUNTIME_ARN> \
  --runtime-session-id "$(uuidgen)-$(uuidgen)" \
  --content-type application/json \
  --cli-binary-format raw-in-base64-out \
  --payload '{"prompt": "Hello"}' \
  response.json
cat response.json
```

Add `--runtime-user-id <USER_ID>` to call the agent on behalf of a user; the agent then sees `ctx.userId` and keeps a separate history for that user.

With boto3:

```python
import json, uuid, boto3

client = boto3.client("bedrock-agentcore", region_name="<REGION>")
response = client.invoke_agent_runtime(
    agentRuntimeArn="<AGENT_RUNTIME_ARN>",
    runtimeSessionId=f"{uuid.uuid4()}-{uuid.uuid4()}",
    contentType="application/json",
    payload=json.dumps({"prompt": "Hello"}),
)
print(json.loads(response["response"].read()))
```

## Limits and errors

- A synchronous invocation times out after 15 minutes, and the payload can be up to 100 MB ([quotas](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html)).
- When the agent answers with a 4xx or 5xx, the caller gets `424` with `x-amzn-ErrorType: RuntimeClientError`, not the agent's own response. The listener logs the cause with the request and session IDs: check the runtime's logs in CloudWatch.
