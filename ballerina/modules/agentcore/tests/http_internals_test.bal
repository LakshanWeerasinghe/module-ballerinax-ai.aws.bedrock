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

// Guards for the http module internals `NativeResourceInvoker` relies on, so an http upgrade that changes them fails
// the build instead of a request: the private `request` field of `http:Headers`, and the `$param$.<name>` annotation
// key with `ballerina/http:<major>:Payload` for `@http:Payload`.

@test:Config
function testHeadersBackedByRequest() returns error? {
    http:Request request = new;
    request.setHeader("x-test-header", "value-1");
    request.addHeader("x-test-header", "value-2");
    http:Headers headers = createHeaders(request);
    test:assertEquals(check headers.getHeader("x-test-header"), "value-1");
    test:assertEquals(check headers.getHeaders("x-test-header"), ["value-1", "value-2"]);
    test:assertTrue(headers.getHeader("x-missing") is http:HeaderNotFoundError);
}

type InternalsPayload record {|
    string message;
|};

@test:Config
function testPayloadAnnotationDetected() returns error? {
    Service agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(Context ctx, @http:Payload InternalsPayload payload) returns json =>
            payload.message;
    };
    DispatcherService dispatcher = new;
    setUserService(dispatcher, agentCoreService);
    ResourceSignature? signature = check getResourceSignature(dispatcher, "post", ["invocations"]);
    if signature is () {
        test:assertFail("no 'post invocations' resource found");
    }
    test:assertEquals((<typedesc<anydata>>signature.payloadType).toString(), InternalsPayload.toString());
    test:assertTrue(signature.hasContext);

    signature = check getResourceSignature(dispatcher, "get", ["ping"]);
    if signature is () {
        test:assertFail("no 'get ping' resource found");
    }
    test:assertEquals(signature.payloadType, ());
    test:assertFalse(signature.hasContext);
    unlinkUserService(dispatcher);
}

@test:Config
function testUnannotatedParameterRejected() returns error? {
    Service agentCoreService = service object {
        resource function get ping() returns PingStatus => HEALTHY;

        resource function post invocations(json payload) returns json => payload;
    };
    DispatcherService dispatcher = new;
    setUserService(dispatcher, agentCoreService);
    ResourceSignature|error? signature = getResourceSignature(dispatcher, "post", ["invocations"]);
    test:assertTrue(signature is error);
    unlinkUserService(dispatcher);
}

@test:Config
function testUnlinkedDispatcher() {
    DispatcherService dispatcher = new;
    test:assertTrue(getResourceSignature(dispatcher, "post", ["invocations"]) is error);
    test:assertTrue(invokeResource(dispatcher, "post", ["invocations"], (), ()) is error);
}
