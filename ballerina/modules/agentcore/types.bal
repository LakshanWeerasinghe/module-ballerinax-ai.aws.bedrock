// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;

# A service that runs on Amazon Bedrock AgentCore Runtime under the HTTP protocol.
# It declares `resource function get ping()` and `resource function post invocations(...)`.
public type InvocationService distinct service object {
    *http:Service;
};

# The configuration of an `agentcore:Listener`.
#
# + timeout - Seconds a connection may stay idle, including while the agent works on a response
# + requestLimits - Inbound request size limits
# + gracefulStopTimeout - Seconds to let in-flight requests finish on a graceful stop
public type ListenerConfiguration record {|
    *http:ListenerConfiguration;
    // bedrock-agentcore-limits: synchronous requests time out after 15 minutes. The http default of 60 seconds
    // would end a longer agent turn before AgentCore gives up.
    decimal timeout = 900;
    RequestLimitConfigs requestLimits = {};
    decimal gracefulStopTimeout = 30;
|};

# Inbound request size limits, with AgentCore's header allowance as the default.
#
# + maxHeaderSize - runtime-header-allowlist: up to 20 custom headers of up to 4 KB each, on
#                   top of the platform headers and a JWT. A value built as an
#                   `http:RequestLimitConfigs` carries http's 8 KB default instead.
public type RequestLimitConfigs record {|
    *http:RequestLimitConfigs;
    int maxHeaderSize = 98304;
|};

# The health status reported on `GET /ping`.
public enum PingStatus {
    # Ready to accept new work
    HEALTHY = "Healthy",
    # Running background work; AgentCore keeps the session alive
    HEALTHY_BUSY = "HealthyBusy"
}

# The AgentCore context of an invocation. Declare a parameter of this type to receive it.
#
# + sessionId - The runtime session ID, if the caller sent one
# + requestId - The request ID header if the caller sent one, else a generated UUID. Caller-controlled: never use it as
#               a trust or isolation key
# + userId - Always `()`: AgentCore Runtime doesn't forward the runtime user ID header
# + workloadAccessToken - The workload access token for AgentCore Identity
# + oauth2CallbackUrl - The OAuth2 callback URL for AgentCore Identity
# + authorization - The inbound `Authorization` header (with a custom JWT authorizer)
# + customHeaders - The allowlisted custom headers, keyed by lower-case name
# + requestHeaders - The request headers agent code may see, keyed by lower-case name (`Authorization` as is)
# + headers - The raw request headers
public type Context record {|
    string? sessionId = ();
    // AgentCore Runtime doesn't forward `X-Amzn-Bedrock-AgentCore-Runtime-Request-Id`, so in practice this is generated.
    string requestId;
    string? userId = ();
    string? workloadAccessToken = ();
    string? oauth2CallbackUrl = ();
    string? authorization = ();
    map<string> customHeaders = {};
    map<string> requestHeaders = {};
    http:Headers headers;
|};

// AgentCore Runtime HTTP protocol contract: "Serving port: 8080 by default".
// https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-http-protocol-contract.html
const int DEFAULT_PORT = 8080;

// Header names: bedrock-agentcore-sdk-python@fda8209 `src/bedrock_agentcore/runtime/models.py:17-24`.
const HEADER_SESSION_ID = "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id";
const HEADER_REQUEST_ID = "X-Amzn-Bedrock-AgentCore-Runtime-Request-Id";
const HEADER_IDENTITY_WAT = "X-Amz-Bedrock-AgentCore-Identity-WAT";
const HEADER_WORKLOAD_ACCESS_TOKEN = "WorkloadAccessToken";
const HEADER_OAUTH2_CALLBACK_URL = "OAuth2CallbackUrl";
const HEADER_AUTHORIZATION = "Authorization";
const HEADER_CUSTOM_PREFIX = "X-Amzn-Bedrock-AgentCore-Runtime-Custom-";
// InvokeAgentRuntime API reference (`runtimeUserId` request parameter); sdk-python `identity/auth.py:359`.
const HEADER_USER_ID = "X-Amzn-Bedrock-AgentCore-Runtime-User-Id";
