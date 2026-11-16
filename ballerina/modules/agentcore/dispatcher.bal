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
import ballerina/log;

const APPLICATION_JSON = "application/json";
const INTERNAL_SERVER_ERROR_MESSAGE = "Internal server error";

# The internal service the listener attaches in place of the user's `agentcore:Service`. The user's service is
# linked to it as native data, so it holds no Ballerina mutable state of its own.
isolated service class DispatcherService {
    *http:Service;

    # `GET /ping`, served by the user's `get ping` resource.
    #
    # + return - The ping response
    isolated resource function get ping() returns http:Response {
        ResourceSignature|error? signature = getResourceSignature(self, http:HTTP_GET, [PING_PATH]);
        if signature is () {
            return pingResponse(HEALTHY);
        }
        any|error result = signature is error ? signature : invokeResource(self, http:HTTP_GET, [PING_PATH], (), ());
        if result is PingStatus {
            return pingResponse(result);
        }
        error cause = result is error ? result : error("the 'get ping' resource returned a value that is not an "
            + "agentcore:PingStatus");
        log:printWarn("The ping resource failed; reporting Healthy", cause);
        return pingResponse(HEALTHY);
    }

    # `POST /invocations`, served by the user's `post invocations` resource.
    #
    # + request - The request
    # + return - The response
    isolated resource function post invocations(http:Request request) returns http:Response {
        Context context = contextFromRequest(request);
        ResourceSignature|error? signature = getResourceSignature(self, http:HTTP_POST, [INVOCATIONS_PATH]);
        if signature is () {
            return internalErrorResponse(error("the agentcore:Service declares no 'post invocations' resource"),
                    context);
        }
        if signature is error {
            return internalErrorResponse(signature, context);
        }
        anydata payload = ();
        typedesc<anydata>? payloadType = signature.payloadType;
        if payloadType is typedesc<anydata> {
            anydata|PayloadBindingError bound = bindPayload(request, payloadType);
            if bound is PayloadBindingError {
                return errorResponse(http:STATUS_BAD_REQUEST, bound.message());
            }
            payload = bound;
        }
        any|error result = invokeResource(self, http:HTTP_POST, [INVOCATIONS_PATH], payload, context);
        if result is error {
            return internalErrorResponse(result, context);
        }
        if result is anydata {
            return jsonResponse(result);
        }
        return internalErrorResponse(error("the 'post invocations' resource returned a value the listener can't send"),
                context);
    }
}

isolated function pingResponse(PingStatus status) returns http:Response {
    http:Response response = new;
    response.setJsonPayload({status});
    return response;
}

# Sends any `anydata` value as `200 application/json`, as `py/runtime/app.py:597-600` does with `json.dumps`.
#
# + value - The value
# + return - The response
isolated function jsonResponse(anydata value) returns http:Response {
    http:Response response = new;
    response.setTextPayload(value.toJsonString(), APPLICATION_JSON);
    return response;
}

# Builds an error response with the `{"error": "..."}` body of `py/runtime/app.py:611-615`.
#
# + statusCode - The status code
# + message - The message
# + return - The response
isolated function errorResponse(int statusCode, string message) returns http:Response {
    http:Response response = new;
    response.statusCode = statusCode;
    response.setJsonPayload({'error: message});
    return response;
}

isolated function internalErrorResponse(error err, Context context) returns http:Response {
    log:printError("The invocation failed", err, requestId = context.requestId, sessionId = context.sessionId);
    return errorResponse(http:STATUS_INTERNAL_SERVER_ERROR, INTERNAL_SERVER_ERROR_MESSAGE);
}
