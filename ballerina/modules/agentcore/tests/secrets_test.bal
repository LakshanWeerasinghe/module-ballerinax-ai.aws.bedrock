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
import ballerina/io;
import ballerina/log;
import ballerina/test;

const SECRETS_PORT = 19601;
const SECRETS_LOG = "target/agentcore-secrets-test.log";

const WAT_MARKER = "wat-marker-7f3a";
const LEGACY_TOKEN_MARKER = "legacy-token-marker-91c2";
const AUTHORIZATION_MARKER = "jwt-marker-4d8e";
const CUSTOM_VALUE_MARKER = "custom-value-marker-2b6f";
const BODY_MARKER = "body-marker-c15d";

@test:Config {groups: ["secrets"]}
function testSecretsNeverLoggedOrReturned() returns error? {
    // Logs are captured to a file for this test; the level is DEBUG so the payload binding logs are included.
    check log:setOutputFile(SECRETS_LOG, log:OVERWRITE);
    check log:root().setLevel(log:DEBUG);
    Listener agentCoreListener = check new (SECRETS_PORT);
    check agentCoreListener.attach(service object {
        resource function get ping() returns PingStatus|error => error("ping is down");

        resource function post invocations(Context ctx, @http:Payload record {|string kind; string note;|} request)
                returns json|error {
            if request.kind == "panic" {
                panic error("panicked");
            }
            if request.kind == "error" {
                return error("failed");
            }
            return "ok";
        }
    });
    check agentCoreListener.'start();
    http:Client cl = check new (string `http://localhost:${SECRETS_PORT}`);
    map<string> headers = {
        [HEADER_IDENTITY_WAT]: WAT_MARKER,
        [HEADER_WORKLOAD_ACCESS_TOKEN]: LEGACY_TOKEN_MARKER,
        [HEADER_AUTHORIZATION]: "Bearer " + AUTHORIZATION_MARKER,
        "X-Amzn-Bedrock-AgentCore-Runtime-Custom-Tenant": CUSTOM_VALUE_MARKER,
        [HEADER_SESSION_ID]: "session-for-secrets-test-0123456789"
    };
    string[] responses = [];
    foreach string kind in ["ok", "error", "panic"] {
        http:Response response = check cl->post("/invocations", {kind, note: BODY_MARKER}, headers);
        responses.push(check response.getTextPayload());
    }
    foreach string body in [string `{"kind":"ok","note":"${BODY_MARKER}","extra":1}`,
            string `{"kind":"ok","note":"${BODY_MARKER}"`, BODY_MARKER] {
        http:Request request = new;
        request.setTextPayload(body, APPLICATION_JSON);
        foreach [string, string] [name, value] in headers.entries() {
            request.setHeader(name, value);
        }
        http:Response response = check cl->post("/invocations", request);
        test:assertEquals(response.statusCode, 400);
        responses.push(check response.getTextPayload());
    }
    http:Response pingResponse = check cl->get("/ping", headers);
    responses.push(check pingResponse.getTextPayload());
    check agentCoreListener.immediateStop();
    check log:root().setLevel(log:INFO);

    string logs = check io:fileReadString(SECRETS_LOG);
    // The test is only meaningful if the error paths were logged.
    test:assertTrue(logs.includes("The invocation failed"), logs);
    test:assertTrue(logs.includes("Request body binding failed"), logs);
    test:assertTrue(logs.includes("session-for-secrets-test-0123456789"), logs);
    foreach string marker in [WAT_MARKER, LEGACY_TOKEN_MARKER, AUTHORIZATION_MARKER, CUSTOM_VALUE_MARKER,
            BODY_MARKER] {
        test:assertFalse(logs.includes(marker), string `'${marker}' was logged`);
        foreach string body in responses {
            test:assertFalse(body.includes(marker), string `'${marker}' was returned: ${body}`);
        }
    }
}
