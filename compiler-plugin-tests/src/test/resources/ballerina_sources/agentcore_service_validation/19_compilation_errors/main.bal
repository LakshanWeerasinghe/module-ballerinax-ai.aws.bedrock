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

// Fine itself, but the module has errors: the structural rules still run, the type rules wait.
service agentcore:InvocationService on new agentcore:Listener(9101) {
    resource function post invocations(@http:Payload error payload) returns json => "ok";
}

// An error inside the service: the compiler's diagnostic is the only one.
service agentcore:InvocationService on new agentcore:Listener(9102) {
    resource function post invocations() returns json => undefinedValue;
}

function unrelated() {
    int count = "not a number";
}
