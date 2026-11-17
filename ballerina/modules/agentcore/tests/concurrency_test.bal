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

const ISOLATED_PARALLEL_PORT = 19801;
const NON_ISOLATED_PARALLEL_PORT = 19802;
const MIXED_QUALIFIERS_PORT = 19803;

const PARALLEL_CALLS = 10;

// Not isolated: only a resource that holds the runtime's lock may touch it.
int unguardedCount = 0;

service class SleepingService {
    *InvocationService;

    resource function get ping() returns PingStatus => HEALTHY;

    resource function post invocations() returns string {
        runtime:sleep(1);
        return "done";
    }
}

// Sends the calls at once and returns how long they took together, in seconds.
function parallelCalls(int port) returns decimal|error {
    http:Client cl = check new (string `http://localhost:${port}`, timeout = 30);
    time:Utc started = time:utcNow();
    future<http:Response|error>[] calls = [];
    foreach int _ in 0 ..< PARALLEL_CALLS {
        future<http:Response|error> call = start postInvocation(cl, {});
        calls.push(call);
    }
    foreach future<http:Response|error> call in calls {
        http:Response response = check wait call;
        check assertRawJson(response, 200, "\"done\"");
    }
    return time:utcDiffSeconds(time:utcNow(), started);
}

@test:Config
function testIsolatedServiceServesInParallel() returns error? {
    InvocationService agentCoreService = isolated service object {
        isolated resource function get ping() returns PingStatus => HEALTHY;

        isolated resource function post invocations() returns string {
            runtime:sleep(1);
            return "done";
        }
    };
    Listener agentCoreListener = check startOn(ISOLATED_PARALLEL_PORT, agentCoreService);
    decimal elapsed = check parallelCalls(ISOLATED_PARALLEL_PORT);
    test:assertTrue(elapsed < 5d, elapsed.toString());
    check agentCoreListener.immediateStop();
}

// The runtime's lock is released while a resource waits, as on an http:Listener, so waiting calls still overlap.
@test:Config
function testNonIsolatedServiceWaitsInParallel() returns error? {
    Listener agentCoreListener = check startOn(NON_ISOLATED_PARALLEL_PORT, new SleepingService());
    decimal elapsed = check parallelCalls(NON_ISOLATED_PARALLEL_PORT);
    test:assertTrue(elapsed < 5d, elapsed.toString());
    check agentCoreListener.immediateStop();
}

// A resource that is not isolated runs under the runtime's lock even in an isolated service.
@test:Config
function testNonIsolatedResourceOfIsolatedService() returns error? {
    InvocationService agentCoreService = isolated service object {
        isolated resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations() returns int {
            int current = unguardedCount;
            unguardedCount = current + 1;
            return unguardedCount;
        }
    };
    Listener agentCoreListener = check startOn(MIXED_QUALIFIERS_PORT, agentCoreService);
    http:Client cl = check clientFor(MIXED_QUALIFIERS_PORT);
    future<http:Response|error>[] calls = [];
    foreach int _ in 0 ..< 50 {
        future<http:Response|error> call = start postInvocation(cl, ());
        calls.push(call);
    }
    int[] results = [];
    foreach future<http:Response|error> call in calls {
        http:Response response = check wait call;
        int count = check (check response.getJsonPayload()).ensureType();
        results.push(count);
    }
    test:assertEquals(results.sort(), from int i in 1 ... 50 select i);
    check agentCoreListener.immediateStop();
}
