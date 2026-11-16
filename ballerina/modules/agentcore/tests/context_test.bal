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
import ballerina/lang.regexp;
import ballerina/test;

const CONTEXT_PORT = 19301;

final regexp:RegExp UUID_PATTERN = re `[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}`;

final Listener contextListener = check new (CONTEXT_PORT);

// Echoes what the resource received; only for these tests, which use dummy values.
@test:BeforeSuite
function startContextListener() returns error? {
    check contextListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(Context ctx) returns json {
            string? rawSession = ();
            string|http:HeaderNotFoundError raw = ctx.headers.getHeader(HEADER_SESSION_ID);
            if raw is string {
                rawSession = raw;
            }
            return {
                sessionId: ctx.sessionId,
                requestId: ctx.requestId,
                userId: ctx.userId,
                workloadAccessToken: ctx.workloadAccessToken,
                oauth2CallbackUrl: ctx.oauth2CallbackUrl,
                authorization: ctx.authorization,
                customHeaders: ctx.customHeaders,
                requestHeaders: ctx.requestHeaders,
                rawSession
            };
        }
    });
    check contextListener.'start();
}

@test:AfterSuite
function stopContextListener() returns error? {
    check contextListener.immediateStop();
}

isolated function invokeWithHeaders(map<string> headers) returns map<json>|error {
    http:Client cl = check clientFor(CONTEXT_PORT);
    return cl->post("/invocations", {}, headers);
}

@test:Config
function testContextMapsEveryField() returns error? {
    map<json> ctx = check invokeWithHeaders({
        [HEADER_SESSION_ID]: "session-0123456789-0123456789-0123456789",
        [HEADER_REQUEST_ID]: "request-1",
        [HEADER_USER_ID]: "user-1",
        [HEADER_IDENTITY_WAT]: "dummy-wat",
        [HEADER_OAUTH2_CALLBACK_URL]: "https://example.com/callback",
        [HEADER_AUTHORIZATION]: "Bearer dummy-jwt",
        "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant": "tenant-a",
        "X-Custom-App": "app-1"
    });
    test:assertEquals(ctx["sessionId"], "session-0123456789-0123456789-0123456789");
    test:assertEquals(ctx["rawSession"], "session-0123456789-0123456789-0123456789");
    test:assertEquals(ctx["requestId"], "request-1");
    test:assertEquals(ctx["userId"], "user-1");
    test:assertEquals(ctx["workloadAccessToken"], "dummy-wat");
    test:assertEquals(ctx["oauth2CallbackUrl"], "https://example.com/callback");
    test:assertEquals(ctx["authorization"], "Bearer dummy-jwt");
    test:assertEquals(ctx["customHeaders"], {"x-amzn-bedrock-agentcore-runtime-custom-tenant": "tenant-a"});
    map<json> requestHeaders = check ctx["requestHeaders"].ensureType();
    test:assertEquals(requestHeaders[HEADER_AUTHORIZATION], "Bearer dummy-jwt");
    test:assertEquals(valueIgnoringCase(requestHeaders, "x-custom-app"), "app-1");
    test:assertEquals(valueIgnoringCase(requestHeaders, "x-amzn-bedrock-agentcore-runtime-custom-tenant"), "tenant-a");
    // `py/runtime/models.py:192-194`: the WAT header is the one `x-amz-` header agent code may see.
    test:assertEquals(valueIgnoringCase(requestHeaders, HEADER_IDENTITY_WAT), "dummy-wat");
}

@test:Config
function testRequestIdGeneratedWhenMissing() returns error? {
    map<json> first = check invokeWithHeaders({});
    map<json> second = check invokeWithHeaders({});
    string firstId = check first["requestId"].ensureType();
    test:assertTrue(UUID_PATTERN.isFullMatch(firstId), firstId);
    test:assertNotEquals(firstId, second["requestId"]);
}

@test:Config
function testMissingSessionId() returns error? {
    map<json> ctx = check invokeWithHeaders({});
    test:assertEquals(ctx["sessionId"], ());
    test:assertEquals(ctx["userId"], ());
    test:assertEquals(ctx["workloadAccessToken"], ());
    test:assertEquals(ctx["authorization"], ());
    test:assertEquals(ctx["customHeaders"], {});
}

@test:Config
function testWorkloadAccessTokenPriority() returns error? {
    map<json> ctx = check invokeWithHeaders({[HEADER_IDENTITY_WAT]: "wat-header", [HEADER_WORKLOAD_ACCESS_TOKEN]: "legacy"});
    test:assertEquals(ctx["workloadAccessToken"], "wat-header");
    ctx = check invokeWithHeaders({[HEADER_WORKLOAD_ACCESS_TOKEN]: "legacy"});
    test:assertEquals(ctx["workloadAccessToken"], "legacy");
}

@test:Config
function testHeaderNamesAreCaseInsensitive() returns error? {
    map<json> ctx = check invokeWithHeaders({
        "x-amzn-bedrock-agentcore-runtime-session-id": "lower-session",
        "X-AMZN-BEDROCK-AGENTCORE-RUNTIME-USER-ID": "upper-user",
        "authorization": "Bearer lower",
        "x-amzn-BEDROCK-agentcore-runtime-CUSTOM-Mixed": "mixed"
    });
    test:assertEquals(ctx["sessionId"], "lower-session");
    test:assertEquals(ctx["userId"], "upper-user");
    test:assertEquals(ctx["authorization"], "Bearer lower");
    test:assertEquals(ctx["customHeaders"], {"x-amzn-bedrock-agentcore-runtime-custom-mixed": "mixed"});
    map<json> requestHeaders = check ctx["requestHeaders"].ensureType();
    test:assertEquals(requestHeaders[HEADER_AUTHORIZATION], "Bearer lower");
}

@test:Config
function testRestrictedHeadersExcluded() returns error? {
    map<json> ctx = check invokeWithHeaders({
        "Cookie": "c=1",
        "X-Forwarded-For": "10.0.0.1",
        "X-Amz-Date": "20260101T000000Z",
        "X-Amz-Security-Token": "dummy",
        "X-Amzn-Trace-Id": "Root=1-0",
        [HEADER_SESSION_ID]: "s",
        [HEADER_USER_ID]: "u",
        "traceparent": "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"
    });
    map<json> requestHeaders = check ctx["requestHeaders"].ensureType();
    foreach string name in ["cookie", "x-forwarded-for", "x-amz-date", "x-amz-security-token", "x-amzn-trace-id",
            "content-type", "content-length", "host", "user-agent", HEADER_SESSION_ID.toLowerAscii(),
            HEADER_USER_ID.toLowerAscii()] {
        test:assertEquals(valueIgnoringCase(requestHeaders, name), (), name);
    }
    test:assertEquals(valueIgnoringCase(requestHeaders, "traceparent"),
        "00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01");
}

@test:Config
function testIsForwardableHeader() {
    test:assertFalse(isForwardableHeader("accept"));
    test:assertFalse(isForwardableHeader("sec-websocket-key"));
    test:assertFalse(isForwardableHeader(":path"));
    test:assertFalse(isForwardableHeader("x-amz-content-sha256"));
    test:assertFalse(isForwardableHeader("x-amzn-requestid"));
    test:assertTrue(isForwardableHeader("x-amz-bedrock-agentcore-identity-wat"));
    test:assertTrue(isForwardableHeader("x-amzn-bedrock-agentcore-runtime-custom-a"));
    test:assertTrue(isForwardableHeader("x-my-header"));
    test:assertTrue(isForwardableHeader("baggage"));
}

isolated function valueIgnoringCase(map<json> headers, string name) returns json {
    foreach [string, json] [key, value] in headers.entries() {
        if key.toLowerAscii() == name.toLowerAscii() {
            return value;
        }
    }
    return ();
}
