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
import ballerina/test;

type Order record {|
    string id;
    int quantity;
|};

isolated int invocationCount = 0;

isolated function countInvocation() {
    lock {
        invocationCount += 1;
    }
}

isolated function invocationCountValue() returns int {
    lock {
        return invocationCount;
    }
}

// One listener per payload type, each on its own port.
const JSON_PORT = 19201;
const RECORD_PORT = 19202;
const STRING_PORT = 19203;
const BYTES_PORT = 19204;
const OPTIONAL_PORT = 19205;
const CONTEXT_ONLY_PORT = 19206;
const NO_PARAMS_PORT = 19207;
const PAYLOAD_FIRST_PORT = 19208;
const READONLY_BYTES_PORT = 19209;
const MUTABLE_BYTES_PORT = 19210;

type ReadonlyBytes byte[] & readonly;

final Listener jsonListener = check new (JSON_PORT);
final Listener recordListener = check new (RECORD_PORT);
final Listener stringListener = check new (STRING_PORT);
final Listener bytesListener = check new (BYTES_PORT);
final Listener optionalListener = check new (OPTIONAL_PORT);
final Listener contextOnlyListener = check new (CONTEXT_ONLY_PORT);
final Listener noParamsListener = check new (NO_PARAMS_PORT);
final Listener payloadFirstListener = check new (PAYLOAD_FIRST_PORT);
final Listener readonlyBytesListener = check new (READONLY_BYTES_PORT);
final Listener mutableBytesListener = check new (MUTABLE_BYTES_PORT);

@test:BeforeSuite
function startInvocationListeners() returns error? {
    check jsonListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(Context ctx, @http:Payload json payload) returns json {
            countInvocation();
            return {received: payload};
        }
    });
    check recordListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload Order 'order) returns json {
            countInvocation();
            return {id: 'order.id, total: 'order.quantity * 2};
        }
    });
    check stringListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload string text) returns string {
            countInvocation();
            return text.toUpperAscii();
        }
    });
    check bytesListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload byte[] bytes) returns int => bytes.length();
    });
    check optionalListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload Order? 'order) returns json => 'order is () ? "none" : 'order.id;
    });
    check contextOnlyListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(Context ctx) returns json => {requestId: ctx.requestId};
    });
    check noParamsListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns json => "no params";
    });
    check payloadFirstListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload json payload, Context ctx) returns json =>
            {payload, sessionId: ctx.sessionId};
    });
    check readonlyBytesListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload ReadonlyBytes bytes) returns json =>
            {length: bytes.length(), isReadOnly: bytes is readonly};
    });
    check mutableBytesListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload byte[] bytes) returns int {
            bytes.push(0);
            return bytes.length();
        }
    });
    foreach Listener l in [jsonListener, recordListener, stringListener, bytesListener, optionalListener,
            contextOnlyListener, noParamsListener, payloadFirstListener, readonlyBytesListener, mutableBytesListener] {
        check l.'start();
    }
}

@test:AfterSuite
function stopInvocationListeners() returns error? {
    foreach Listener l in [jsonListener, recordListener, stringListener, bytesListener, optionalListener,
            contextOnlyListener, noParamsListener, payloadFirstListener, readonlyBytesListener, mutableBytesListener] {
        check l.immediateStop();
    }
}

isolated function clientFor(int port) returns http:Client|error => new (string `http://localhost:${port}`);

isolated function postRaw(int port, string|byte[] body, string contentType = APPLICATION_JSON)
        returns http:Response|error {
    http:Client cl = check clientFor(port);
    http:Request request = new;
    if body is string {
        request.setTextPayload(body, contentType);
    } else {
        request.setBinaryPayload(body, contentType);
    }
    return cl->post("/invocations", request);
}

isolated function assertJsonResponse(http:Response response, int status, json expected) returns error? {
    test:assertEquals(response.statusCode, status);
    test:assertEquals(response.getContentType(), APPLICATION_JSON);
    test:assertEquals(check response.getJsonPayload(), expected);
}

@test:Config
function testJsonPayload() returns error? {
    http:Response response = check postRaw(JSON_PORT, "{\"prompt\":\"hi\",\"n\":[1,2]}");
    check assertJsonResponse(response, 200, {received: {prompt: "hi", n: [1, 2]}});
}

@test:Config
function testRecordPayload() returns error? {
    http:Response response = check postRaw(RECORD_PORT, "{\"id\":\"o1\",\"quantity\":3}");
    check assertJsonResponse(response, 200, {id: "o1", total: 6});
}

@test:Config
function testClosedRecordRejectsUnknownField() returns error? {
    int before = invocationCountValue();
    http:Response response = check postRaw(RECORD_PORT, "{\"id\":\"o1\",\"quantity\":3,\"extra\":true}");
    check assertJsonResponse(response, 400, {'error: PAYLOAD_INVALID_MESSAGE});
    test:assertEquals(invocationCountValue(), before);
}

@test:Config
function testMalformedJsonNotEchoed() returns error? {
    string body = "{\"secret-body-marker\": ";
    http:Response response = check postRaw(JSON_PORT, body);
    check assertJsonResponse(response, 400, {'error: PAYLOAD_INVALID_MESSAGE});
    test:assertFalse((check response.getTextPayload()).includes("secret-body-marker"));
}

@test:Config
function testStringPayloadIsJsonString() returns error? {
    http:Response response = check postRaw(STRING_PORT, "\"hello\"");
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(response.getContentType(), APPLICATION_JSON);
    test:assertEquals(check response.getTextPayload(), "\"HELLO\"");
}

@test:Config
function testStringPayloadRejectsPlainText() returns error? {
    http:Response response = check postRaw(STRING_PORT, "hello", "text/plain");
    check assertJsonResponse(response, 400, {'error: PAYLOAD_STRING_INVALID_MESSAGE});
}

@test:Config
function testStringPayloadRejectsOtherJson() returns error? {
    http:Response response = check postRaw(STRING_PORT, "{\"a\":1}");
    check assertJsonResponse(response, 400, {'error: PAYLOAD_STRING_INVALID_MESSAGE});
}

@test:Config
function testBytesPayload() returns error? {
    http:Response response = check postRaw(BYTES_PORT, [0, 1, 2, 255], "application/octet-stream");
    check assertJsonResponse(response, 200, 4);
}

@test:Config
function testReadonlyBytesPayload() returns error? {
    check assertJsonResponse(check postRaw(READONLY_BYTES_PORT, [1, 2, 3], "application/octet-stream"), 200,
        {length: 3, isReadOnly: true});
}

@test:Config
function testMutableBytesPayload() returns error? {
    check assertJsonResponse(check postRaw(MUTABLE_BYTES_PORT, [1, 2, 3], "application/octet-stream"), 200, 4);
}

@test:Config
function testEmptyBody() returns error? {
    // `byte[]` gets an empty array, an optional type gets `()`, any other type is a 400.
    check assertJsonResponse(check postRaw(BYTES_PORT, ""), 200, 0);
    check assertJsonResponse(check postRaw(OPTIONAL_PORT, ""), 200, "none");
    check assertJsonResponse(check postRaw(RECORD_PORT, ""), 400, {'error: PAYLOAD_EMPTY_MESSAGE});
    check assertJsonResponse(check postRaw(OPTIONAL_PORT, "{\"id\":\"o2\",\"quantity\":1}"), 200, "o2");
}

@test:Config
function testContextOnlyResource() returns error? {
    http:Client cl = check clientFor(CONTEXT_ONLY_PORT);
    http:Response response = check cl->post("/invocations", "not json at all",
        {[HEADER_REQUEST_ID]: "req-1"});
    // Without a payload parameter, the body is never read.
    check assertJsonResponse(response, 200, {requestId: "req-1"});
}

@test:Config
function testNoParamsResource() returns error? {
    check assertJsonResponse(check postRaw(NO_PARAMS_PORT, "{}"), 200, "no params");
}

@test:Config
function testPayloadBeforeContext() returns error? {
    http:Client cl = check clientFor(PAYLOAD_FIRST_PORT);
    http:Response response = check cl->post("/invocations", {q: 1}, {[HEADER_SESSION_ID]: "s-1"});
    check assertJsonResponse(response, 200, {payload: {q: 1}, sessionId: "s-1"});
}

@test:Config
function testUnknownRoutes() returns error? {
    http:Client cl = check clientFor(NO_PARAMS_PORT);
    http:Response response = check cl->get("/invocations");
    test:assertEquals(response.statusCode, 405);
    response = check cl->get("/other");
    test:assertEquals(response.statusCode, 404);
}

const READONLY_RECORD_PORT = 19211;
const NILABLE_UNION_PORT = 19212;
const NIL_TYPE_PORT = 19213;
const INT_PAYLOAD_PORT = 19214;
const ANYDATA_PAYLOAD_PORT = 19215;
const FINITE_PAYLOAD_PORT = 19216;

@test:Config
function testEmptyBodyBindsNilForJson() returns error? {
    check assertJsonResponse(check postRaw(JSON_PORT, ""), 200, {received: ()});
    check assertJsonResponse(check postRaw(JSON_PORT, "null"), 200, {received: ()});
}

@test:Config
function testWhitespaceBodyIsNotEmpty() returns error? {
    // Only a zero-length body is empty; whitespace is invalid JSON, as it is for `json.loads`.
    check assertJsonResponse(check postRaw(JSON_PORT, "  \n"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    check assertJsonResponse(check postRaw(OPTIONAL_PORT, "  \n"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
}

@test:Config
function testNullBody() returns error? {
    check assertJsonResponse(check postRaw(OPTIONAL_PORT, "null"), 200, "none");
    check assertJsonResponse(check postRaw(RECORD_PORT, "null"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
}

@test:Config
function testTrailingContentRejected() returns error? {
    check assertJsonResponse(check postRaw(JSON_PORT, "{\"a\":1} {\"b\":2}"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    check assertJsonResponse(check postRaw(JSON_PORT, "{\"a\":1} trailing"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    check assertJsonResponse(check postRaw(JSON_PORT, " {\"a\":1}\n"), 200, {received: {a: 1}});
}

@test:Config
function testDuplicateKeysLastWins() returns error? {
    // As `json.loads` does.
    check assertJsonResponse(check postRaw(RECORD_PORT, "{\"id\":\"a\",\"id\":\"b\",\"quantity\":1}"), 200,
        {id: "b", total: 2});
}

@test:Config
function testContentTypeIgnored() returns error? {
    foreach string contentType in ["text/plain", "application/xml", "application/octet-stream",
            "application/json; charset=utf-8"] {
        check assertJsonResponse(check postRaw(JSON_PORT, "{\"a\":1}", contentType), 200, {received: {a: 1}});
    }
    http:Client cl = check clientFor(JSON_PORT);
    http:Request request = new;
    request.setTextPayload("{\"a\":1}");
    check request.removeHeader("Content-Type");
    http:Response response = check cl->post("/invocations", request);
    check assertJsonResponse(response, 200, {received: {a: 1}});
}

@test:Config
function testUnicodePayloadRoundTrip() returns error? {
    http:Response response = check postRaw(JSON_PORT,
        "{\"text\":\"héllo 世界 😀\",\"escaped\":\"\\u00e9\\ud83d\\ude00\"}");
    check assertJsonResponse(response, 200, {received: {text: "héllo 世界 😀", escaped: "é😀"}});
}

// Built by doubling, so a long string doesn't cost an object per character.
isolated function repeated(string unit, int times) returns string {
    string result = "";
    string chunk = unit;
    int remaining = times;
    while remaining > 0 {
        if remaining % 2 == 1 {
            result += chunk;
        }
        chunk += chunk;
        remaining /= 2;
    }
    return result;
}

@test:Config
function testDeeplyNestedBodyRejected() returns error? {
    string open = repeated("[", 100000);
    string close = repeated("]", 100000);
    check assertJsonResponse(check postRaw(RECORD_PORT, open + close), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    check assertJsonResponse(check postRaw(RECORD_PORT, "{\"id\":\"o1\",\"quantity\":1}"), 200, {id: "o1", total: 2});
}

@test:Config
function testLargeBodies() returns error? {
    byte[] bytes = [];
    bytes.setLength(8 * 1024 * 1024);
    check assertJsonResponse(check postRaw(BYTES_PORT, bytes, "application/octet-stream"), 200, bytes.length());
    string text = repeated("a", 1024 * 1024);
    http:Response response = check postRaw(STRING_PORT, string `"${text}"`);
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(check response.getTextPayload(), string `"${text.toUpperAscii()}"`);
}

@test:Config
function testChunkedRequestBody() returns error? {
    http:Client cl = check new (string `http://localhost:${JSON_PORT}`,
        http1Settings = {chunking: http:CHUNKING_ALWAYS});
    http:Request request = new;
    request.setTextPayload("{\"a\":1}", APPLICATION_JSON);
    http:Response response = check cl->post("/invocations", request);
    check assertJsonResponse(response, 200, {received: {a: 1}});
}

@test:Config
function testReadonlyRecordPayload() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload readonly & Order 'order) returns json =>
            {id: 'order.id, isReadOnly: 'order is readonly};
    };
    Listener agentCoreListener = check startOn(READONLY_RECORD_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(READONLY_RECORD_PORT, "{\"id\":\"o1\",\"quantity\":1}"), 200,
        {id: "o1", isReadOnly: true});
    check assertJsonResponse(check postRaw(READONLY_RECORD_PORT, "{\"id\":\"o1\",\"quantity\":1,\"x\":0}"), 400,
        {'error: PAYLOAD_INVALID_MESSAGE});
    check agentCoreListener.immediateStop();
}

@test:Config
function testNilableUnionPayload() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload Order|string? payload) returns json {
            if payload is () {
                return "nil";
            }
            return payload is string ? "string" : "record";
        }
    };
    Listener agentCoreListener = check startOn(NILABLE_UNION_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(NILABLE_UNION_PORT, "{\"id\":\"o1\",\"quantity\":1}"), 200, "record");
    check assertJsonResponse(check postRaw(NILABLE_UNION_PORT, "\"text\""), 200, "string");
    check assertJsonResponse(check postRaw(NILABLE_UNION_PORT, "null"), 200, "nil");
    check assertJsonResponse(check postRaw(NILABLE_UNION_PORT, ""), 200, "nil");
    check assertJsonResponse(check postRaw(NILABLE_UNION_PORT, "42"), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    check agentCoreListener.immediateStop();
}

@test:Config
function testNilPayloadType() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload () nothing) returns json => "nil";
    };
    Listener agentCoreListener = check startOn(NIL_TYPE_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(NIL_TYPE_PORT, ""), 200, "nil");
    check assertJsonResponse(check postRaw(NIL_TYPE_PORT, "null"), 200, "nil");
    http:Response response = check postRaw(NIL_TYPE_PORT, "1");
    test:assertEquals(response.statusCode, 400);
    check agentCoreListener.immediateStop();
}

@test:Config
function testIntPayload() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload int n) returns int => n + 1;
    };
    Listener agentCoreListener = check startOn(INT_PAYLOAD_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(INT_PAYLOAD_PORT, "41"), 200, 42);
    check assertJsonResponse(check postRaw(INT_PAYLOAD_PORT, "-9223372036854775807"), 200, -9223372036854775806);
    foreach string body in ["\"41\"", "1.5", "9223372036854775808", "true"] {
        check assertJsonResponse(check postRaw(INT_PAYLOAD_PORT, body), 400, {'error: PAYLOAD_INVALID_MESSAGE});
    }
    check agentCoreListener.immediateStop();
}

@test:Config
function testAnydataPayload() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload anydata payload) returns anydata => payload;
    };
    Listener agentCoreListener = check startOn(ANYDATA_PAYLOAD_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(ANYDATA_PAYLOAD_PORT, "{\"a\":[1,\"x\",null,true,{\"b\":-2}]}"), 200,
        {a: [1, "x", (), true, {b: -2}]});
    check assertJsonResponse(check postRaw(ANYDATA_PAYLOAD_PORT, ""), 200, ());
    check agentCoreListener.immediateStop();
}

@test:Config
function testFiniteStringPayload() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload "yes"|"no" answer) returns string => answer;
    };
    Listener agentCoreListener = check startOn(FINITE_PAYLOAD_PORT, agentCoreService);
    check assertJsonResponse(check postRaw(FINITE_PAYLOAD_PORT, "\"yes\""), 200, "yes");
    http:Response response = check postRaw(FINITE_PAYLOAD_PORT, "\"maybe\"");
    test:assertEquals(response.statusCode, 400);
    test:assertFalse((check response.getTextPayload()).includes("maybe"));
    check agentCoreListener.immediateStop();
}
