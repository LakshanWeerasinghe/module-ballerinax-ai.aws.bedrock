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
import ballerina/lang.runtime;
import ballerina/test;

// Services the compiler plugin would reject. They reach the dispatcher only when the plugin doesn't run, as in these
// tests, and the listener must still answer every request.

const BAD_PING_PARAM_PORT = 19701;
const BAD_PING_VALUE_PORT = 19702;
const NO_INVOCATIONS_PORT = 19703;
const BAD_INVOCATIONS_PARAM_PORT = 19704;
const STREAM_CLOSE_FAILS_PORT = 19705;
const DETACH_IN_FLIGHT_PORT = 19707;
const XML_PAYLOAD_PORT = 19708;
const TABLE_PAYLOAD_PORT = 19709;
const REGEXP_PAYLOAD_PORT = 19710;
const MIXED_UNION_PAYLOAD_PORT = 19711;
const OPEN_RECORD_PAYLOAD_PORT = 19712;

type PayloadRow record {|
    string id;
|};

type OpenOrder record {
    string id;
};

isolated class FailingCloseStream {
    public isolated function next() returns record {|string value;|}|error? => {value: "chunk"};

    public isolated function close() returns error? => error("close failed");
}

isolated function startOn(int port, InvocationService agentCoreService) returns Listener|error {
    Listener agentCoreListener = check new (port);
    check agentCoreListener.attach(agentCoreService);
    check agentCoreListener.'start();
    return agentCoreListener;
}

@test:Config
function testPingWithUnsupportedParameter() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping(string extra) returns PingStatus => HEALTHY_BUSY;

        resource function post invocations() returns json => "ok";
    };
    Listener agentCoreListener = check startOn(BAD_PING_PARAM_PORT, agentCoreService);
    test:assertEquals(check ping(BAD_PING_PARAM_PORT), {status: "Healthy"});
    check agentCoreListener.immediateStop();
}

@test:Config
function testPingReturningNonStatus() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns string => "Bogus";

        resource function post invocations() returns json => "ok";
    };
    Listener agentCoreListener = check startOn(BAD_PING_VALUE_PORT, agentCoreService);
    test:assertEquals(check ping(BAD_PING_VALUE_PORT), {status: "Healthy"});
    check agentCoreListener.immediateStop();
}

@test:Config
function testServiceWithoutInvocations() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;
    };
    Listener agentCoreListener = check startOn(NO_INVOCATIONS_PORT, agentCoreService);
    http:Client cl = check clientFor(NO_INVOCATIONS_PORT);
    check assertRawJson(check postInvocation(cl, {}), 500, "{\"error\":\"Internal server error\"}");
    check agentCoreListener.immediateStop();
}

@test:Config
function testInvocationsWithUnsupportedParameter() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(json payload) returns json => payload;
    };
    Listener agentCoreListener = check startOn(BAD_INVOCATIONS_PARAM_PORT, agentCoreService);
    http:Client cl = check clientFor(BAD_INVOCATIONS_PARAM_PORT);
    check assertRawJson(check postInvocation(cl, {}), 500, "{\"error\":\"Internal server error\"}");
    check agentCoreListener.immediateStop();
}

@test:Config
function testStreamWhoseCloseFails() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns stream<string, error?> =>
            new stream<string, error?>(new FailingCloseStream());
    };
    Listener agentCoreListener = check startOn(STREAM_CLOSE_FAILS_PORT, agentCoreService);
    http:Client cl = check clientFor(STREAM_CLOSE_FAILS_PORT);
    check assertRawJson(check postInvocation(cl, {}), 500, "{\"error\":\"Internal server error\"}");
    check agentCoreListener.immediateStop();
}

@test:Config
function testDispatcherRegistry() returns error? {
    Listener agentCoreListener = check new (19706);
    InvocationService agentCoreService = newPingService();
    check agentCoreListener.attach(agentCoreService);
    error? again = agentCoreListener.attach(agentCoreService);
    test:assertTrue(again is error && again.message().includes("already attached"));
    check agentCoreListener.detach(agentCoreService);
    check agentCoreListener.detach(agentCoreService);
    check agentCoreListener.attach(agentCoreService);
    check agentCoreListener.detach(agentCoreService);
}

@test:Config
function testDetachLetsInFlightRequestFinish() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns json {
            runtime:sleep(1.5);
            return "finished";
        }
    };
    Listener agentCoreListener = check startOn(DETACH_IN_FLIGHT_PORT, agentCoreService);
    http:Client cl = check clientFor(DETACH_IN_FLIGHT_PORT);
    future<http:Response|error> call = start postInvocation(cl, {});
    runtime:sleep(0.5);
    check agentCoreListener.detach(agentCoreService);
    http:Response finished = check wait call;
    check assertRawJson(finished, 200, "\"finished\"");
    http:Response afterDetach = check postInvocation(cl, {});
    test:assertEquals(afterDetach.statusCode, 404);
    check agentCoreListener.immediateStop();
}

@test:Config
function testContextDefaults() {
    Context ctx = {requestId: "r-1", headers: createHeaders(new http:Request())};
    test:assertEquals(ctx.sessionId, ());
    test:assertEquals(ctx.customHeaders, {});
    test:assertEquals(ctx.requestHeaders, {});
}

function assertUnbindablePayload(int port, InvocationService agentCoreService) returns error? {
    Listener agentCoreListener = check startOn(port, agentCoreService);
    http:Client cl = check clientFor(port);
    check assertRawJson(check postInvocation(cl, {id: "o1"}), 500, "{\"error\":\"Internal server error\"}");
    check agentCoreListener.immediateStop();
}

@test:Config
function testXmlPayloadRejected() returns error? {
    check assertUnbindablePayload(XML_PAYLOAD_PORT, service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload xml payload) returns json => "called";
    });
}

@test:Config
function testTablePayloadRejected() returns error? {
    check assertUnbindablePayload(TABLE_PAYLOAD_PORT, service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload table<PayloadRow> payload) returns json => "called";
    });
}

@test:Config
function testRegExpPayloadRejected() returns error? {
    check assertUnbindablePayload(REGEXP_PAYLOAD_PORT, service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload string:RegExp payload) returns json => "called";
    });
}

@test:Config
function testUnionWithUnbindableMemberRejected() returns error? {
    check assertUnbindablePayload(MIXED_UNION_PAYLOAD_PORT, service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload json|xml payload) returns json => "called";
    });
}

@test:Config
function testOpenRecordPayloadAccepted() returns error? {
    InvocationService agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(@http:Payload OpenOrder payload) returns anydata => payload;
    };
    Listener agentCoreListener = check startOn(OPEN_RECORD_PAYLOAD_PORT, agentCoreService);
    http:Client cl = check clientFor(OPEN_RECORD_PAYLOAD_PORT);
    check assertRawJson(check postInvocation(cl, {id: "o1", note: "extra"}), 200,
        "{\"id\":\"o1\", \"note\":\"extra\"}");
    check agentCoreListener.immediateStop();
}
