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

final Listener jsonListener = check new (JSON_PORT);
final Listener recordListener = check new (RECORD_PORT);
final Listener stringListener = check new (STRING_PORT);
final Listener bytesListener = check new (BYTES_PORT);
final Listener optionalListener = check new (OPTIONAL_PORT);
final Listener contextOnlyListener = check new (CONTEXT_ONLY_PORT);
final Listener noParamsListener = check new (NO_PARAMS_PORT);
final Listener payloadFirstListener = check new (PAYLOAD_FIRST_PORT);

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
    foreach Listener l in [jsonListener, recordListener, stringListener, bytesListener, optionalListener,
            contextOnlyListener, noParamsListener, payloadFirstListener] {
        check l.'start();
    }
}

@test:AfterSuite
function stopInvocationListeners() returns error? {
    foreach Listener l in [jsonListener, recordListener, stringListener, bytesListener, optionalListener,
            contextOnlyListener, noParamsListener, payloadFirstListener] {
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
    check assertJsonResponse(response, 400, {'error: PAYLOAD_TYPE_MISMATCH_MESSAGE});
    test:assertEquals(invocationCountValue(), before);
}

@test:Config
function testMalformedJsonNotEchoed() returns error? {
    string body = "{\"secret-body-marker\": ";
    http:Response response = check postRaw(JSON_PORT, body);
    check assertJsonResponse(response, 400, {'error: PAYLOAD_NOT_JSON_MESSAGE});
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
    check assertJsonResponse(response, 400, {'error: PAYLOAD_STRING_NOT_JSON_MESSAGE});
}

@test:Config
function testStringPayloadRejectsOtherJson() returns error? {
    http:Response response = check postRaw(STRING_PORT, "{\"a\":1}");
    check assertJsonResponse(response, 400, {'error: PAYLOAD_TYPE_MISMATCH_MESSAGE});
}

@test:Config
function testBytesPayload() returns error? {
    http:Response response = check postRaw(BYTES_PORT, [0, 1, 2, 255], "application/octet-stream");
    check assertJsonResponse(response, 200, 4);
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
