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

@test:Config
function testSharedListenerRejectsConfig() returns error? {
    http:Listener httpListener = check new (19130);
    Listener|error agentCoreListener = new (httpListener, timeout = 120);
    if agentCoreListener !is error {
        test:assertFail("a configuration with a shared http:Listener was accepted");
    }
    test:assertTrue(agentCoreListener.message().includes("can't apply a configuration of its own"));
    // A configuration equal to the defaults changes nothing, so it is accepted.
    Listener _ = check new (httpListener, timeout = 900);
}

@test:Config
function testSharedListenerBelowAgentCoreDefaults() returns error? {
    http:Listener defaults = check new (19112);
    string? warning = belowAgentCoreDefaults(defaults.getConfig());
    if warning !is string {
        test:assertFail("no warning for a shared listener with the http defaults");
    }
    test:assertTrue(warning.includes("timeout = 60"));
    test:assertTrue(warning.includes("requestLimits.maxHeaderSize = 8192"));

    http:Listener shortTimeout = check new (19113, timeout = 120, requestLimits = {maxHeaderSize: 98304});
    test:assertTrue(belowAgentCoreDefaults(shortTimeout.getConfig()) is string);
    http:Listener smallHeaders = check new (19114, timeout = 900);
    test:assertTrue(belowAgentCoreDefaults(smallHeaders.getConfig()) is string);
}

@test:Config
function testSharedListenerAtAgentCoreDefaults() returns error? {
    http:Listener configured = check new (19115, timeout = 900, requestLimits = {maxHeaderSize: 98304});
    test:assertEquals(belowAgentCoreDefaults(configured.getConfig()), ());
    // A timeout of 0 disables it.
    http:Listener noTimeout = check new (19116, timeout = 0, requestLimits = {maxHeaderSize: 131072});
    test:assertEquals(belowAgentCoreDefaults(noTimeout.getConfig()), ());
}

@test:Config
function testRootBasePathVariantsServe() returns error? {
    Listener agentCoreListener = check new (19117);
    InvocationService agentCoreService = newPingService();
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19117");
    (string|string[])[] names = ["/", "//", " / ", "", ["", "/"], ["/", "/"]];
    foreach string|string[] name in names {
        check agentCoreListener.attach(agentCoreService, name);
        http:Response response = check cl->get("/ping");
        test:assertEquals(response.statusCode, 200, name.toString());
        response = check cl->post("/invocations", {});
        test:assertEquals(response.statusCode, 200, name.toString());
        check agentCoreListener.detach(agentCoreService);
    }
    check agentCoreListener.immediateStop();
}

@test:Config
function testSecondServiceOnSameListenerFails() returns error? {
    Listener agentCoreListener = check new (19118);
    InvocationService first = newPingService();
    InvocationService second = service object {
        resource function get ping() returns PingStatus => HEALTHY_BUSY;

        resource function post invocations() returns json => "second";
    };
    check agentCoreListener.attach(first);
    error? result = agentCoreListener.attach(second);
    test:assertTrue(result is error);
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19118");
    string body = check cl->post("/invocations", {});
    test:assertEquals(body, "ok");
    // The failed attach left no record behind, so the second service attaches once the first is gone.
    check agentCoreListener.detach(second);
    check agentCoreListener.detach(first);
    check agentCoreListener.attach(second);
    body = check cl->post("/invocations", {});
    test:assertEquals(body, "second");
    check agentCoreListener.immediateStop();
}

@test:Config
function testTwoAgentCoreListenersOnOneHttpListener() returns error? {
    http:Listener httpListener = check new (19119, timeout = 900, requestLimits = {maxHeaderSize: 98304});
    Listener first = check new (httpListener);
    Listener second = check new (httpListener);
    InvocationService agentCoreService = newPingService();
    check first.attach(agentCoreService);
    // Both would serve the same root of the same http:Listener.
    error? result = second.attach(agentCoreService);
    test:assertTrue(result is error);
    check httpListener.'start();
    http:Client cl = check new ("http://localhost:19119");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check first.detach(agentCoreService);
    check second.attach(agentCoreService);
    response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check httpListener.immediateStop();
}

@test:Config
function testDetachFromAnotherListenerDoesNothing() returns error? {
    Listener attached = check new (19120);
    Listener other = check new (19121);
    InvocationService agentCoreService = newPingService();
    check attached.attach(agentCoreService);
    check attached.'start();
    check other.detach(agentCoreService);
    http:Client cl = check new ("http://localhost:19120");
    http:Response response = check cl->get("/ping");
    test:assertEquals(response.statusCode, 200);
    check attached.immediateStop();
}

@test:Config
function testGracefulStopFinishesInFlightRequest() returns error? {
    Listener agentCoreListener = check new (19122, gracefulStopTimeout = 10);
    check agentCoreListener.attach(service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns json {
            runtime:sleep(1.5);
            return "finished";
        }
    });
    check agentCoreListener.'start();
    http:Client cl = check new ("http://localhost:19122", timeout = 10);
    future<http:Response|error> call = start postInvocation(cl, {});
    runtime:sleep(0.5);
    check agentCoreListener.gracefulStop();
    http:Response finished = check wait call;
    check assertRawJson(finished, 200, "\"finished\"");
}

@test:Config
function testSharedListenerAcceptsConfigEqualToDefaults() returns error? {
    http:Listener httpListener = check new (19123);
    Listener _ = check new (httpListener, requestLimits = {});
    Listener _ = check new (httpListener, requestLimits = {maxHeaderSize: 98304}, host = "0.0.0.0");
    Listener|error rejected = new (httpListener, requestLimits = {maxEntityBodySize: 1024});
    test:assertTrue(rejected is error);
    rejected = new (httpListener, gracefulStopTimeout = 5);
    test:assertTrue(rejected is error);
}
