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

const APPLICATION_JSON = "application/json";

# The internal service the listener attaches in place of the user's `agentcore:Service`. The user's service is
# linked to it as native data, so it holds no Ballerina mutable state of its own.
isolated service class DispatcherService {
    *http:Service;

    # `GET /ping`.
    #
    # + return - The ping response
    isolated resource function get ping() returns http:Response {
        http:Response response = new;
        response.setJsonPayload({status: HEALTHY});
        return response;
    }
}
