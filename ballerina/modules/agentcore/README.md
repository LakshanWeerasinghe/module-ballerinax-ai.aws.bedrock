## Overview

This module runs a Ballerina agent on [Amazon Bedrock AgentCore Runtime](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/agents-tools-runtime.html) under the [HTTP protocol contract](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html).

The `agentcore:Listener` listens on `0.0.0.0:8080` and serves:

- `GET /ping`, the health check, through the service's `get ping` resource
- `POST /invocations`, the agent's entry point, through the service's `post invocations` resource

It reads the AgentCore request headers into an `agentcore:Context` and maps results and errors to JSON responses, so the service holds only agent logic.

## Usage

```ballerina
import ballerina/http;
import ballerinax/ai.aws.bedrock.agentcore;

listener agentcore:Listener agentCoreListener = new;

service on agentCoreListener {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload json payload, agentcore:Context ctx) returns json|error {
        return {response: "Hello"};
    }
}
```

The service must declare both resources, at the root base path. The compiler rejects any other resource or remote function.

- `get ping` takes no parameters and returns `agentcore:HEALTHY`, or `agentcore:HEALTHY_BUSY` while the agent runs background work. AgentCore keeps a `HealthyBusy` session alive. The listener adds `time_of_last_update` and changes it only when the status changes.
- `post invocations` can declare an `@http:Payload` parameter of any `anydata` type and an `agentcore:Context` parameter, in any order.

## Payload

The request body is read as JSON and bound strictly to the declared type: a closed record rejects unknown fields. A `byte[]` parameter receives the raw body.

A `string` parameter expects a JSON string: `curl -d '"hello"'` binds `hello`, while `curl -d hello` is rejected with `400`. An empty body binds to `()` when the type allows it. Error messages never echo the body.

## Responses

- Any `anydata` result, including `()` and a `string`, is sent as `200` with a JSON body.
- An `http:Response` or a status-code record such as `http:Accepted` is sent as is.
- An error is sent as `500` with `{"error": "Internal server error"}`. A 4xx `httpscerr` error, such as `httpscerr:NotFoundError`, keeps its status and message.

AgentCore shows the caller a `424` for any 4xx or 5xx from the agent, so the listener logs each error with its cause, request ID and session ID. Look for them in CloudWatch.

## Context

`agentcore:Context` holds the session ID, the request ID (generated when AgentCore sends none), the user ID passed to `InvokeAgentRuntimeForUser`, the workload access token, the OAuth2 callback URL, the inbound `Authorization` header, the allowlisted custom headers and the request headers. The listener never logs the token, `Authorization`, custom header values or the body.

## Listener configuration

`new agentcore:Listener()` listens on 8080. Pass a port, or an `http:Listener` to share. The `http:ListenerConfiguration` fields apply, with defaults suited to AgentCore: a 900-second timeout (AgentCore allows 15-minute synchronous requests) and 96 KB of request headers.

Streaming responses, a custom invocation path and WebSocket are not supported yet.

See the [AgentCore Runtime agent example](https://github.com/ballerina-platform/module-ballerinax-ai.aws.bedrock/tree/main/examples/agentcore-runtime-agent) for building, deploying and invoking an agent.
