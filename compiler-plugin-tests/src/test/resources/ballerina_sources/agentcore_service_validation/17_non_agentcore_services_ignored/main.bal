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

listener http:Listener httpListener = new (9090);

service /api on httpListener {
    resource function get status(http:Request request) returns json => "ok";

    resource function post invocations(string extra) returns xml => xml `<ok/>`;
}

service class HttpService {
    *http:Service;

    resource function get anything() returns json => "ok";
}

http:Service httpObject = service object {
    resource function get other(int count) returns json => count;
};

// Referencing the module keeps the import used.
agentcore:PingStatus status = agentcore:HEALTHY;
