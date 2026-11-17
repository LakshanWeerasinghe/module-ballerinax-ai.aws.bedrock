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
    readonly string id;
|};

type XmlDocument xml;

type JsonOrXml json|xml;

type XmlOrText xml|string;

type AgentContext agentcore:Context;

type ContextAlias AgentContext;

service on new agentcore:Listener(9201) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload readonly & xml payload) returns json => "ok";
}

service on new agentcore:Listener(9202) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload xml? payload) returns json => "ok";
}

service on new agentcore:Listener(9203) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload XmlDocument payload) returns json => "ok";
}

service on new agentcore:Listener(9204) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload JsonOrXml payload) returns json => "ok";
}

service on new agentcore:Listener(9205) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload xml:Element payload) returns json => "ok";
}

service on new agentcore:Listener(9206) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload table<Row> key(id) payload) returns json => "ok";
}

service on new agentcore:Listener(9207) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload string:RegExp? payload) returns json => "ok";
}

// A union member that is itself a union is flattened into the outer union, so its xml is a direct member.
service on new agentcore:Listener(9208) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload XmlOrText|int payload) returns json => "ok";
}

// Accepted: the xml is not the declared type or a direct union member, so a request gets a 400.
service on new agentcore:Listener(9209) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload xml[] payload) returns json => "ok";
}

service on new agentcore:Listener(9210) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload map<xml> payload) returns json => "ok";
}

service on new agentcore:Listener(9211) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload anydata payload, ContextAlias ctx) returns anydata => payload;
}

service on new agentcore:Listener(9212) {
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(readonly & agentcore:Context ctx) returns json => ctx.sessionId;
}
