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

isolated function newPingService() returns InvocationService => service object {
    resource function get ping() returns PingStatus => HEALTHY;

    resource function post invocations() returns json => "ok";
};

@test:Config
function testDefaultPort() returns error? {
    Listener agentCoreListener = check new;
    InvocationService agentCoreService = newPingService();
    check agentCoreListener.attach(agentCoreService);
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:8080");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check agentCoreListener.immediateStop();
}

@test:Config
function testExplicitPort() returns error? {
    Listener agentCoreListener = check new (19101);
    check agentCoreListener.attach(newPingService());
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19101");
    json body = check cl->get("/ping");
    test:assertEquals((check body.status), "Healthy");
    check agentCoreListener.immediateStop();
}

@test:Config
function testAttachRequiresRootBasePath() returns error? {
    Listener agentCoreListener = check new (19102);
    InvocationService agentCoreService = newPingService();
    error? result = agentCoreListener.attach(agentCoreService, "agent");
    test:assertTrue(result is error);
    test:assertTrue((<error>result).message().includes("root base path"));
    result = agentCoreListener.attach(agentCoreService, ["a", "b"]);
    test:assertTrue(result is error);
    check agentCoreListener.attach(agentCoreService, "/");
    check agentCoreListener.detach(agentCoreService);
    check agentCoreListener.attach(agentCoreService, ["", "/"]);
    check agentCoreListener.detach(agentCoreService);
    check agentCoreListener.attach(agentCoreService, "");
    check agentCoreListener.detach(agentCoreService);
}

@test:Config
function testDoubleAttachFails() returns error? {
    Listener agentCoreListener = check new (19103);
    InvocationService agentCoreService = newPingService();
    check agentCoreListener.attach(agentCoreService);
    error? result = agentCoreListener.attach(agentCoreService);
    test:assertTrue(result is error);
    test:assertTrue((<error>result).message().includes("already attached"));
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19103");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check agentCoreListener.immediateStop();
}

@test:Config
function testDetach() returns error? {
    Listener agentCoreListener = check new (19104);
    InvocationService agentCoreService = newPingService();
    check agentCoreListener.attach(agentCoreService);
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19104");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);

    check agentCoreListener.detach(agentCoreService);
    response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 404);
    // Detaching again does nothing.
    check agentCoreListener.detach(agentCoreService);
    // The service can be attached again after a detach.
    check agentCoreListener.attach(agentCoreService);
    response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check agentCoreListener.immediateStop();
}

@test:Config
function testDetachFromOneOfTwoListeners() returns error? {
    Listener first = check new (19105);
    Listener second = check new (19106);
    InvocationService agentCoreService = newPingService();
    check first.attach(agentCoreService);
    check second.attach(agentCoreService);
    check first.'start();
    check second.'start();
    http:Client firstClient = check new ("http://localhost:19105");
    http:Client secondClient = check new ("http://localhost:19106");

    check first.detach(agentCoreService);
    http:Response response = check firstClient->get("/ping");
    test:assertEquals(response.statusCode, 404);
    response = check secondClient->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check first.immediateStop();
    check second.immediateStop();
}

@test:Config
function testSharedHttpListener() returns error? {
    http:Listener httpListener = check new (19107);
    Listener agentCoreListener = check new (httpListener);
    check agentCoreListener.attach(newPingService());
    http:Service other = service object {
        resource function get hello() returns string => "hello";
    };
    check httpListener.attach(other, "other");
    check httpListener.'start();
    http:Client cl = check new ("http://localhost:19107");
    json body = check cl->get("/ping");
    test:assertEquals((check body.status), "Healthy");
    string hello = check cl->get("/other/hello");
    test:assertEquals(hello, "hello");
    check httpListener.immediateStop();
}

@test:Config
function testGracefulStop() returns error? {
    Listener agentCoreListener = check new (19108, gracefulStopTimeout = 1);
    check agentCoreListener.attach(newPingService());
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19108");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check agentCoreListener.gracefulStop();
    http:Response|error afterStop = cl->get("/ping");
    test:assertTrue(afterStop is error);
}

// runtime-header-allowlist: up to 20 custom headers of up to 4 KB each.
@test:Config
function testLargeAllowlistedHeadersAccepted() returns error? {
    map<string> headers = {};
    foreach int i in 1 ... 20 {
        headers[string `X-Amzn-Bedrock-AgentCore-Runtime-Custom-H${i}`] = string:'join("", ...from int _ in 0 ..< 4000 select "a");
    }
    Listener agentCoreListener = check new (19109);
    check agentCoreListener.attach(newPingService());
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19109");
    http:Response response = check cl->post("/invocations", {}, headers);
    test:assertEquals(response.statusCode, 200);
    check agentCoreListener.immediateStop();

    // Overriding another limit keeps the header allowance.
    Listener partialLimits = check new (19111, requestLimits = {maxEntityBodySize: 2097152});
    check partialLimits.attach(newPingService());
    check partialLimits.'start();
    http:Client partialClient = check new ("http://localhost:19111");
    response = check partialClient->post("/invocations", {}, headers);
    test:assertEquals(response.statusCode, 200);
    check partialLimits.immediateStop();

    // The http default of 8 KB rejects the same request.
    http:Listener httpListener = check new (19110);
    Listener sharing = check new (httpListener);
    check sharing.attach(newPingService());
    check httpListener.'start();
    http:Client defaultClient = check new ("http://localhost:19110");
    response = check defaultClient->post("/invocations", {}, headers);
    test:assertEquals(response.statusCode, 431);
    check httpListener.immediateStop();
}

@test:Config
function testRequestLimitsMergeFieldByField() {
    // Setting another limit keeps AgentCore's header allowance.
    ListenerConfiguration partial = {requestLimits: {maxEntityBodySize: 2097152}};
    test:assertEquals(partial.requestLimits.maxHeaderSize, 98304);
    test:assertEquals(partial.requestLimits.maxEntityBodySize, 2097152);
    // Every value stays selectable, including http's own default.
    ListenerConfiguration explicit = {requestLimits: {maxHeaderSize: 8192}};
    test:assertEquals(explicit.requestLimits.maxHeaderSize, 8192);
    // A value built as `http:RequestLimitConfigs` keeps http's default.
    http:RequestLimitConfigs httpLimits = {};
    test:assertEquals(httpLimits.maxHeaderSize, 8192);
    ListenerConfiguration fromHttp = {requestLimits: httpLimits};
    test:assertEquals(fromHttp.requestLimits.maxHeaderSize, 8192);
}

@test:Config
function testListenerConfigurationDefaults() {
    ListenerConfiguration config = {};
    test:assertEquals(config.host, "0.0.0.0");
    test:assertEquals(config.timeout, 900d);
    test:assertEquals(config.requestLimits.maxHeaderSize, 98304);
    test:assertEquals(config.gracefulStopTimeout, 30d);
}
