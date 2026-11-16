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
import ballerina/time;

isolated PingStatus pingValue = HEALTHY;
isolated boolean pingFails = false;
isolated boolean pingPanics = false;

isolated function setPing(PingStatus value, boolean fails = false, boolean panics = false) {
    lock {
        pingValue = value;
    }
    lock {
        pingFails = fails;
    }
    lock {
        pingPanics = panics;
    }
}

isolated function currentPing() returns PingStatus|error {
    boolean panics;
    lock {
        panics = pingPanics;
    }
    if panics {
        panic error("ping panicked");
    }
    boolean fails;
    lock {
        fails = pingFails;
    }
    if fails {
        return error("ping failed");
    }
    lock {
        return pingValue;
    }
}

const PING_PORT = 19401;
const NO_PING_PORT = 19402;
const PING_PARAMS_PORT = 19403;

final Listener pingListener = check new (PING_PORT);

@test:BeforeSuite
function startPingListener() returns error? {
    check pingListener.attach(service object {
        resource function get ping() returns PingStatus|error => currentPing();

        resource function post invocations() returns json => "ok";
    });
    check pingListener.'start();
}

@test:AfterSuite
function stopPingListener() returns error? {
    check pingListener.immediateStop();
}

isolated function ping(int port = PING_PORT) returns map<json>|error {
    http:Client cl = check clientFor(port);
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    test:assertEquals(response.getContentType(), APPLICATION_JSON);
    return (check response.getJsonPayload()).ensureType();
}

@test:Config {groups: ["ping"]}
function testPingUsesServiceValue() returns error? {
    setPing(HEALTHY_BUSY);
    test:assertEquals((check ping())["status"], "HealthyBusy");
    setPing(HEALTHY);
    test:assertEquals((check ping())["status"], "Healthy");
}

@test:Config {groups: ["ping"], dependsOn: [testPingUsesServiceValue]}
function testTimeOfLastUpdateChangesOnlyOnStatusChange() returns error? {
    setPing(HEALTHY);
    int first = check (check ping())["time_of_last_update"].ensureType();
    int now = time:utcNow()[0];
    test:assertTrue(first > 0 && first <= now, first.toString());
    runtime:sleep(1.1);
    test:assertEquals((check ping())["time_of_last_update"], first);

    setPing(HEALTHY_BUSY);
    int busySince = check (check ping())["time_of_last_update"].ensureType();
    test:assertTrue(busySince > first, string `${busySince} <= ${first}`);
    runtime:sleep(1.1);
    test:assertEquals((check ping())["time_of_last_update"], busySince);
}

@test:Config {groups: ["ping"], dependsOn: [testTimeOfLastUpdateChangesOnlyOnStatusChange]}
function testPingErrorReportsHealthyWithoutTimestamp() returns error? {
    setPing(HEALTHY_BUSY);
    int busySince = check (check ping())["time_of_last_update"].ensureType();
    setPing(HEALTHY_BUSY, fails = true);
    test:assertEquals(check ping(), {status: "Healthy"});
    setPing(HEALTHY_BUSY, panics = true);
    test:assertEquals(check ping(), {status: "Healthy"});
    // The fallback left the tracker alone: the status is still HealthyBusy since the same time.
    setPing(HEALTHY_BUSY);
    test:assertEquals(check ping(), {status: "HealthyBusy", time_of_last_update: busySince});
    setPing(HEALTHY);
}

@test:Config
function testPingTracker() {
    PingTracker tracker = new;
    int first = tracker.timeOfLastUpdate(HEALTHY);
    test:assertTrue(first > 0);
    test:assertEquals(tracker.timeOfLastUpdate(HEALTHY), first);
}

@test:Config
function testPingResponseShape() returns error? {
    test:assertEquals(check pingResponse(HEALTHY).getJsonPayload(), {status: "Healthy"});
    test:assertEquals(check pingResponse(HEALTHY_BUSY, 1700000000).getJsonPayload(),
        {status: "HealthyBusy", time_of_last_update: 1700000000});
}

@test:Config
function testPingWithoutResource() returns error? {
    // The compiler plugin requires `get ping`; without it the listener still answers.
    Listener agentCoreListener = check new (NO_PING_PORT);
    check agentCoreListener.attach(service object {
        resource function post invocations() returns json => "ok";
    });
    check agentCoreListener.'start();
    map<json> body = check ping(NO_PING_PORT);
    test:assertEquals(body["status"], "Healthy");
    test:assertTrue(body["time_of_last_update"] is int);
    check agentCoreListener.immediateStop();
}

@test:Config
function testPingWithParametersReportsHealthyWithoutTimestamp() returns error? {
    // The compiler plugin rejects ping parameters; the listener still never calls the resource with nil.
    Listener agentCoreListener = check new (PING_PARAMS_PORT);
    check agentCoreListener.attach(service object {
        resource function get ping(Context ctx) returns PingStatus => HEALTHY_BUSY;

        resource function post invocations() returns json => "ok";
    });
    check agentCoreListener.'start();
    test:assertEquals(check ping(PING_PARAMS_PORT), {status: "Healthy"});
    check agentCoreListener.immediateStop();
}
