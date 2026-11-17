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

type Order record {
    string id;
};

listener agentcore:Listener agentCoreListener = new;

service agentcore:InvocationService on agentCoreListener {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload xml payload) returns json => "ok";
}

service agentcore:InvocationService on new agentcore:Listener(9104) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload table<Row> payload) returns json => "ok";
}

service agentcore:InvocationService on new agentcore:Listener(9105) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload string:RegExp payload) returns json => "ok";
}

service agentcore:InvocationService on new agentcore:Listener(9106) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload json|xml payload) returns json => "ok";
}

// An open record's rest field is `anydata`, which is not expanded, and `byte[]` gets the raw body.
service agentcore:InvocationService on new agentcore:Listener(9107) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload Order payload) returns json => payload.id;
}

service agentcore:InvocationService on new agentcore:Listener(9108) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload byte[] payload) returns json => payload.length();
}
