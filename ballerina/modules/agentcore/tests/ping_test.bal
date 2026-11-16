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
function testPingErrorReportsHealthy() returns error? {
    setPing(HEALTHY_BUSY, fails = true);
    test:assertEquals(check ping(), {status: "Healthy"});
    setPing(HEALTHY_BUSY, panics = true);
    test:assertEquals(check ping(), {status: "Healthy"});
    setPing(HEALTHY);
}

@test:Config
function testPingWithoutResource() returns error? {
    // The compiler plugin requires `get ping`; without it the listener still answers.
    Listener agentCoreListener = check new (NO_PING_PORT);
    check agentCoreListener.attach(service object {
        resource function post invocations() returns json => "ok";
    });
    check agentCoreListener.'start();
    test:assertEquals((check ping(NO_PING_PORT))["status"], "Healthy");
    check agentCoreListener.immediateStop();
}
