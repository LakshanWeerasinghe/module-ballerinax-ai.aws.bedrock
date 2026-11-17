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
import ballerina/http.httpscerr;
import ballerina/lang.runtime;
import ballerina/test;

const RESPONSES_PORT = 19501;
const NON_ISOLATED_PORT = 19502;
const TIMEOUT_PORT = 19503;

// Each request picks what the resource returns through its `kind` field.
type ResultRequest record {|
    string kind;
|};

isolated boolean streamClosed = false;

isolated class ClosableStream {
    public isolated function next() returns record {|string value;|}|error? => {value: "chunk"};

    public isolated function close() returns error? {
        lock {
            streamClosed = true;
        }
    }
}

final Listener responsesListener = check new (RESPONSES_PORT);

@test:BeforeSuite
function startResponsesListener() returns error? {
    check responsesListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload ResultRequest request)
                returns anydata|http:Response|http:StatusCodeResponse|stream<string, error?>|error {
            match request.kind {
                "nil" => {
                    return ();
                }
                "string" => {
                    return "plain text";
                }
                "int" => {
                    return 42;
                }
                "record" => {
                    return {answer: "yes", items: [1, 2]};
                }
                "response" => {
                    http:Response response = new;
                    response.statusCode = 418;
                    response.setHeader("x-agent", "teapot");
                    response.setTextPayload("short and stout");
                    return response;
                }
                "accepted" => {
                    http:Accepted accepted = {body: {queued: true}};
                    return accepted;
                }
                "notFoundRecord" => {
                    http:NotFound notFound = {body: {'error: "no such thing"}};
                    return notFound;
                }
                "error" => {
                    return error("database password=hunter2 rejected");
                }
                "notFoundError" => {
                    return error httpscerr:NotFoundError("The order was not found");
                }
                "unavailable" => {
                    return error httpscerr:ServiceUnavailableError("upstream detail");
                }
                "status200" => {
                    return error httpscerr:DefaultStatusCodeError("looks like success", statusCode = 200);
                }
                "status302" => {
                    return error httpscerr:DefaultStatusCodeError("looks like a redirect", statusCode = 302);
                }
                "status0" => {
                    return error httpscerr:DefaultStatusCodeError("no status", statusCode = 0);
                }
                "status999" => {
                    return error httpscerr:DefaultStatusCodeError("out of range", statusCode = 999);
                }
                "panic" => {
                    panic error("boom");
                }
                "stream" => {
                    return new stream<string, error?>(new ClosableStream());
                }
                "cyclic" => {
                    map<anydata> cyclic = {};
                    cyclic["self"] = cyclic;
                    return cyclic;
                }
            }
            return "unknown";
        }
    });
    check responsesListener.'start();
}

@test:AfterSuite
function stopResponsesListener() returns error? {
    check responsesListener.immediateStop();
}

isolated function invokeKind(string kind) returns http:Response|error {
    http:Client cl = check new (string `http://localhost:${RESPONSES_PORT}`, timeout = 10);
    return cl->post("/invocations", {kind});
}

isolated function postInvocation(http:Client cl, json body, map<string> headers = {}) returns http:Response|error {
    return cl->post("/invocations", body, headers);
}

isolated function assertRawJson(http:Response response, int status, string body) returns error? {
    test:assertEquals(response.statusCode, status);
    test:assertEquals(response.getContentType(), APPLICATION_JSON);
    test:assertEquals(check response.getTextPayload(), body);
}

@test:Config
function testAnydataResults() returns error? {
    check assertRawJson(check invokeKind("nil"), 200, "null");
    check assertRawJson(check invokeKind("string"), 200, "\"plain text\"");
    check assertRawJson(check invokeKind("int"), 200, "42");
    check assertRawJson(check invokeKind("record"), 200, "{\"answer\":\"yes\", \"items\":[1, 2]}");
}

@test:Config
function testResponsePassesThrough() returns error? {
    http:Response response = check invokeKind("response");
    test:assertEquals(response.statusCode, 418);
    test:assertEquals(check response.getHeader("x-agent"), "teapot");
    test:assertEquals(check response.getTextPayload(), "short and stout");
}

@test:Config
function testStatusCodeResponsePassesThrough() returns error? {
    http:Response response = check invokeKind("accepted");
    test:assertEquals(response.statusCode, 202);
    test:assertEquals(check response.getJsonPayload(), {queued: true});
    response = check invokeKind("notFoundRecord");
    test:assertEquals(response.statusCode, 404);
    test:assertEquals(check response.getJsonPayload(), {'error: "no such thing"});
}

@test:Config
function testErrorIsGeneric500() returns error? {
    check assertRawJson(check invokeKind("error"), 500, "{\"error\":\"Internal server error\"}");
}

@test:Config
function testStatusCodeErrors() returns error? {
    check assertRawJson(check invokeKind("notFoundError"), 404, "{\"error\":\"The order was not found\"}");
    check assertRawJson(check invokeKind("unavailable"), 503, "{\"error\":\"Internal server error\"}");
}

@test:Config
function testNonErrorStatusesBecome500() returns error? {
    foreach string kind in ["status200", "status302", "status0", "status999"] {
        check assertRawJson(check invokeKind(kind), 500, "{\"error\":\"Internal server error\"}");
    }
}

@test:Config
function testPanicIs500() returns error? {
    check assertRawJson(check invokeKind("panic"), 500, "{\"error\":\"Internal server error\"}");
    // The listener keeps serving after a panic.
    check assertRawJson(check invokeKind("int"), 200, "42");
}

@test:Config
function testStreamIsClosedAnd500() returns error? {
    check assertRawJson(check invokeKind("stream"), 500, "{\"error\":\"Internal server error\"}");
    lock {
        test:assertTrue(streamClosed);
    }
}

@test:Config
function testCyclicResultIs500() returns error? {
    check assertRawJson(check invokeKind("cyclic"), 500, "{\"error\":\"Internal server error\"}");
}

const ISOLATED_PORT = 19504;

@test:Config
function testIsolatedServiceRunsAndPanics() returns error? {
    Listener agentCoreListener = check new (ISOLATED_PORT);
    InvocationService isolatedService = isolated service object {
        isolated resource function get ping() returns PingStatus => HEALTHY;

        isolated resource function post invocations(@http:Payload ResultRequest request) returns json {
            if request.kind == "panic" {
                panic error("isolated boom");
            }
            return request.kind;
        }
    };
    check agentCoreListener.attach(isolatedService);
    check agentCoreListener.'start();
    http:Client cl = check new (string `http://localhost:${ISOLATED_PORT}`, timeout = 10);
    check assertRawJson(check postInvocation(cl, {kind: "ok"}), 200, "\"ok\"");
    check assertRawJson(check postInvocation(cl, {kind: "panic"}), 500, "{\"error\":\"Internal server error\"}");
    check agentCoreListener.immediateStop();
}

@test:Config
function testUnknownKindDefaultsToString() returns error? {
    check assertRawJson(check invokeKind("other"), 200, "\"unknown\"");
}

// A non-isolated service with a non-isolated resource and mutable state runs under the runtime's lock, as it would on
// an http:Listener.
service class CountingService {
    *InvocationService;
    int count = 0;

    resource function get ping() returns PingStatus => HEALTHY;

    resource function post invocations() returns int {
        self.count += 1;
        return self.count;
    }
}

@test:Config
function testNonIsolatedService() returns error? {
    Listener agentCoreListener = check new (NON_ISOLATED_PORT);
    check agentCoreListener.attach(new CountingService());
    check agentCoreListener.'start();
    http:Client cl = check new (string `http://localhost:${NON_ISOLATED_PORT}`);
    future<http:Response|error>[] calls = [];
    foreach int i in 0 ..< 20 {
        future<http:Response|error> call = start postInvocation(cl, ());
        calls.push(call);
    }
    int[] results = [];
    foreach future<http:Response|error> call in calls {
        http:Response|error result = wait call;
        http:Response response = check result;
        test:assertEquals(response.statusCode, 200);
        int count = check (check response.getJsonPayload()).ensureType();
        results.push(count);
    }
    test:assertEquals(results.sort(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
    check agentCoreListener.immediateStop();
}

@test:Config
function testConcurrentSessions() returns error? {
    http:Client cl = check clientFor(PAYLOAD_FIRST_PORT);
    future<http:Response|error>[] calls = [];
    foreach int i in 0 ..< 20 {
        future<http:Response|error> call = start postInvocation(cl, {i}, {[HEADER_SESSION_ID]: string `session-${i}`});
        calls.push(call);
    }
    foreach int i in 0 ..< 20 {
        http:Response|error result = wait calls[i];
        http:Response response = check result;
        check assertJsonResponse(response, 200, {payload: {i}, sessionId: string `session-${i}`});
    }
}

// The http listener timeout also bounds the time an agent takes to respond, which is why the listener raises it to
// AgentCore's 15-minute synchronous limit.
@test:Config
function testListenerTimeoutBoundsAgentTime() returns error? {
    Listener agentCoreListener = check new (TIMEOUT_PORT, timeout = 1);
    check agentCoreListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns string {
            runtime:sleep(3);
            return "late";
        }
    });
    check agentCoreListener.'start();
    http:Client cl = check new (string `http://localhost:${TIMEOUT_PORT}`, timeout = 10);
    http:Response|error response = cl->post("/invocations", ());
    test:assertTrue(response is error || response.statusCode >= 500);
    check agentCoreListener.immediateStop();
}

const EDGE_RESPONSES_PORT = 19505;
const NO_RETURN_TYPE_PORT = 19506;

type OrderNotFoundError distinct httpscerr:NotFoundError;

type ScoreRow record {|
    int score;
|};

isolated function recurseForever(int depth) returns int => recurseForever(depth + 1) + 1;

final Listener edgeResponsesListener = check new (EDGE_RESPONSES_PORT);

@test:BeforeSuite
function startEdgeResponsesListener() returns error? {
    check edgeResponsesListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload ResultRequest request)
                returns anydata|http:Response|http:StatusCodeResponse|error {
            match request.kind {
                "decimal" => {
                    return 1.10d;
                }
                "negativeZero" => {
                    return -0.0;
                }
                "nan" => {
                    return float:NaN;
                }
                "infinity" => {
                    return {value: float:Infinity};
                }
                "unicode" => {
                    return {text: "héllo 世界 😀", quote: "say \"hi\"\n"};
                }
                "xml" => {
                    return xml `<a>b</a>`;
                }
                "table" => {
                    table<ScoreRow> scores = table [{score: 1}, {score: 2}];
                    return scores;
                }
                "response500" => {
                    http:Response response = new;
                    response.statusCode = 500;
                    response.setTextPayload("agent-chosen body");
                    return response;
                }
                "internalServerErrorRecord" => {
                    http:InternalServerError failure = {body: {detail: "agent-chosen detail"}};
                    return failure;
                }
                "badRequestWithCause" => {
                    return error httpscerr:BadRequestError("The prompt is missing",
                        error("cause-marker-5e1a"));
                }
                "distinctNotFound" => {
                    return error OrderNotFoundError("No such order");
                }
                "quotedMessage" => {
                    return error httpscerr:ConflictError("say \"hi\"\n\tthen 世界");
                }
                "status429" => {
                    return error httpscerr:DefaultStatusCodeError("Slow down", statusCode = 429);
                }
                "cyclicArray" => {
                    anydata[] cyclic = [];
                    cyclic.push(cyclic);
                    return cyclic;
                }
                "stackOverflow" => {
                    return recurseForever(0);
                }
                "deep" => {
                    anydata deep = ();
                    foreach int _ in 0 ..< 100000 {
                        deep = [deep];
                    }
                    return deep;
                }
            }
            return "unknown";
        }
    });
    check edgeResponsesListener.'start();
}

@test:AfterSuite
function stopEdgeResponsesListener() returns error? {
    check edgeResponsesListener.immediateStop();
}

isolated function invokeEdgeKind(string kind) returns http:Response|error {
    http:Client cl = check new (string `http://localhost:${EDGE_RESPONSES_PORT}`, timeout = 30);
    return cl->post("/invocations", {kind});
}

@test:Config
function testDecimalAndNegativeZeroResults() returns error? {
    check assertRawJson(check invokeEdgeKind("decimal"), 200, "1.10");
    check assertRawJson(check invokeEdgeKind("negativeZero"), 200, "-0.0");
}

// A float that JSON can't represent must not reach the caller as a `200` with an invalid JSON body.
@test:Config {enable: false}
function testNonFiniteFloatResultIsNotInvalidJson() returns error? {
    foreach string kind in ["nan", "infinity"] {
        http:Response response = check invokeEdgeKind(kind);
        if response.statusCode == 200 {
            json|error body = response.getJsonPayload();
            test:assertTrue(body !is error, string `${kind}: ${check response.getTextPayload()}`);
        }
    }
    // A body number out of float range binds to Infinity and is echoed back.
    http:Response echoed = check postRaw(JSON_PORT, "1e400");
    if echoed.statusCode == 200 {
        json|error body = echoed.getJsonPayload();
        test:assertTrue(body !is error, check echoed.getTextPayload());
    }
}

@test:Config
function testUnicodeResult() returns error? {
    http:Response response = check invokeEdgeKind("unicode");
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(check response.getJsonPayload(), {text: "héllo 世界 😀", quote: "say \"hi\"\n"});
}

@test:Config
function testXmlAndTableResultsSentAsJson() returns error? {
    check assertRawJson(check invokeEdgeKind("xml"), 200, "\"<a>b</a>\"");
    check assertRawJson(check invokeEdgeKind("table"), 200, "[{\"score\":1}, {\"score\":2}]");
}

@test:Config
function testServerErrorResponsesPassThrough() returns error? {
    // A status the agent builds itself is its choice, so its body is not replaced by the generic message.
    http:Response response = check invokeEdgeKind("response500");
    test:assertEquals(response.statusCode, 500);
    test:assertEquals(check response.getTextPayload(), "agent-chosen body");
    response = check invokeEdgeKind("internalServerErrorRecord");
    test:assertEquals(response.statusCode, 500);
    test:assertEquals(check response.getJsonPayload(), {detail: "agent-chosen detail"});
}

@test:Config
function testClientErrorKeepsMessageButNotCause() returns error? {
    http:Response response = check invokeEdgeKind("badRequestWithCause");
    check assertRawJson(response, 400, "{\"error\":\"The prompt is missing\"}");
}

@test:Config
function testDistinctClientErrorSubtype() returns error? {
    check assertRawJson(check invokeEdgeKind("distinctNotFound"), 404, "{\"error\":\"No such order\"}");
}

@test:Config
function testClientErrorMessageIsEscaped() returns error? {
    http:Response response = check invokeEdgeKind("quotedMessage");
    test:assertEquals(response.statusCode, 409);
    test:assertEquals(check response.getJsonPayload(), {'error: "say \"hi\"\n\tthen 世界"});
}

@test:Config
function testDefaultStatusCodeClientError() returns error? {
    check assertRawJson(check invokeEdgeKind("status429"), 429, "{\"error\":\"Slow down\"}");
}

@test:Config
function testUnserializableResultsAre500() returns error? {
    foreach string kind in ["cyclicArray", "deep"] {
        check assertRawJson(check invokeEdgeKind(kind), 500, "{\"error\":\"Internal server error\"}");
    }
}

@test:Config
function testStackOverflowIs500() returns error? {
    check assertRawJson(check invokeEdgeKind("stackOverflow"), 500, "{\"error\":\"Internal server error\"}");
    check assertRawJson(check invokeEdgeKind("decimal"), 200, "1.10");
}

@test:Config
function testErrorStatusBoundaries() returns error? {
    Context ctx = {requestId: "r-1", headers: createHeaders(new http:Request())};
    [int, int, string][] cases = [
        [399, 500, INTERNAL_SERVER_ERROR_MESSAGE],
        [400, 400, "e"],
        [499, 499, "e"],
        [500, 500, INTERNAL_SERVER_ERROR_MESSAGE],
        [599, 599, INTERNAL_SERVER_ERROR_MESSAGE],
        [600, 500, INTERNAL_SERVER_ERROR_MESSAGE],
        [-1, 500, INTERNAL_SERVER_ERROR_MESSAGE]
    ];
    foreach [int, int, string] [given, expected, message] in cases {
        http:Response response = errorResultResponse(
            error httpscerr:DefaultStatusCodeError("e", statusCode = given), ctx);
        test:assertEquals(response.statusCode, expected, given.toString());
        test:assertEquals(check response.getJsonPayload(), {'error: message}, given.toString());
    }
}

@test:Config
function testResourceWithoutReturnType() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() {
        }
    };
    Listener agentCoreListener = check startOn(NO_RETURN_TYPE_PORT, agentCoreService);
    http:Client cl = check clientFor(NO_RETURN_TYPE_PORT);
    check assertRawJson(check postInvocation(cl, {}), 200, "null");
    check agentCoreListener.immediateStop();
}
