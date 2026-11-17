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
import ballerinax/ai.aws.bedrock.agentcore;

type Question record {|
    string prompt;
|};

listener agentcore:Listener agentCoreListener = new;

service agentcore:InvocationService on agentCoreListener {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(agentcore:Context ctx, @http:Payload Question question) returns json|error {
        return {answer: question.prompt, sessionId: ctx.sessionId};
    }
}

service on new agentcore:Listener(9090) {
    isolated resource function get ping() returns agentcore:PingStatus|error => agentcore:HEALTHY_BUSY;

    isolated resource function post invocations(@http:Payload byte[] body, agentcore:Context ctx)
            returns http:Response|http:Accepted|error {
        return new http:Response();
    }
}

service "/" on new agentcore:Listener(9091) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations() {
    }

    function helper() returns int => 1;
}

service class Agent {
    *agentcore:InvocationService;

    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload string? text) returns readonly & (json|error) => text;
}
