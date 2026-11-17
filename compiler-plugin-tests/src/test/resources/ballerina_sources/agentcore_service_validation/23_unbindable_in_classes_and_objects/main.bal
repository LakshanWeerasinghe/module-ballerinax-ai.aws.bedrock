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

type Row record {|
    string id;
|};

service class XmlAgent {
    *agentcore:InvocationService;

    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload xml payload) returns json => "ok";
}

agentcore:InvocationService tableService = service object {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload table<Row> payload) returns json => "ok";
};

function attachInline() returns error? {
    agentcore:Listener agentCoreListener = check new (9301);
    check agentCoreListener.attach(service object {
        resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

        resource function post invocations(@http:Payload string:RegExp payload) returns json => "ok";
    });
}

listener agentcore:Listener agentCoreListener = new (9302);

service on agentCoreListener {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(agentcore:Context ctx, @http:Payload json|xml payload) returns json => "ok";
}
