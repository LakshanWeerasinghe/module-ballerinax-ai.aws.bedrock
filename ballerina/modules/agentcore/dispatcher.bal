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
import ballerina/time;

const APPLICATION_JSON = "application/json";
const INTERNAL_SERVER_ERROR_MESSAGE = "Internal server error";

# What `post invocations` sends: a built response, or a status-code record the http module maps as it would for the
# user's own resource.
type InvocationResponse http:Response|http:StatusCodeResponse;

# The internal service the listener attaches in place of the user's `agentcore:InvocationService`. The user's service is
# linked to it as native data, so it holds no Ballerina mutable state of its own.
isolated service class DispatcherService {
    *http:Service;

    private final PingTracker pingTracker = new;

    # `GET /ping`, served by the user's `get ping` resource.
    #
    # + return - The ping response
    isolated resource function get ping() returns http:Response {
        ResourceSignature|error? signature = getResourceSignature(self, http:HTTP_GET, [PING_PATH]);
        if signature is () {
            return pingResponse(HEALTHY, self.pingTracker.timeOfLastUpdate(HEALTHY));
        }
        any|error result;
        if signature is error {
            result = signature;
        } else if signature.payloadType !is () || signature.hasContext {
            // The compiler plugin rejects ping parameters; a service that slips past it is never called with nil.
            result = error("the 'get ping' resource must declare no parameters");
        } else {
            result = invokeResource(self, http:HTTP_GET, [PING_PATH], (), ());
        }
        if result is PingStatus {
            return pingResponse(result, self.pingTracker.timeOfLastUpdate(result));
        }
        // http-protocol-contract: a timestamp that advances on every ping keeps the session alive until MaxLifetime,
        // and without one "the platform tracks status changes on its own". So the fallback sends none and leaves the
        // tracker alone; `py/runtime/app.py:624` sends the current time here instead.
        error cause = result is error ? result : error("the 'get ping' resource returned a value that is not an "
            + "agentcore:PingStatus");
        log:printWarn("The ping resource failed; reporting Healthy", cause);
        return pingResponse(HEALTHY);
    }

    # `POST /invocations`, served by the user's `post invocations` resource.
    #
    # + request - The request
    # + return - The response
    isolated resource function post invocations(http:Request request) returns InvocationResponse {
        time:Utc started = time:utcNow();
        Context context = contextFromRequest(request);
        InvocationResponse response = self.invoke(request, context);
        int status = response is http:Response ? response.statusCode : response.status.code;
        log:printInfo("Invocation completed", requestId = context.requestId, sessionId = context.sessionId,
                status = status, durationMs = <int>(time:utcDiffSeconds(time:utcNow(), started) * 1000));
        return response;
    }

    isolated function invoke(http:Request request, Context context) returns InvocationResponse {
        ResourceSignature|error? signature = getResourceSignature(self, http:HTTP_POST, [INVOCATIONS_PATH]);
        if signature is () {
            return errorResultResponse(error("the agentcore:InvocationService declares no 'post invocations' resource"),
                    context);
        }
        if signature is error {
            return errorResultResponse(signature, context);
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
        return toInvocationResponse(invokeResource(self, http:HTTP_POST, [INVOCATIONS_PATH], payload, context),
                context);
    }
}

# Remembers when the ping status last changed. The http-protocol-contract asks for `time_of_last_update` to be set
# "only on an actual status change".
isolated class PingTracker {
    private PingStatus? lastStatus = ();
    private int lastUpdate = 0;

    # Records a status and returns when the status last changed.
    #
    # + status - The current status
    # + return - The Unix time in seconds of the last status change
    isolated function timeOfLastUpdate(PingStatus status) returns int {
        lock {
            if self.lastStatus != status {
                self.lastStatus = status;
                self.lastUpdate = time:utcNow()[0];
            }
            return self.lastUpdate;
        }
    }
}

# Builds the `GET /ping` body of the http-protocol-contract: `{"status": ..., "time_of_last_update": ...}`.
#
# + status - The status
# + timeOfLastUpdate - The Unix time in seconds of the last status change, or `()` to leave it out
# + return - The response
isolated function pingResponse(PingStatus status, int? timeOfLastUpdate = ()) returns http:Response {
    http:Response response = new;
    response.setJsonPayload(timeOfLastUpdate is int ? {status, time_of_last_update: timeOfLastUpdate} : {status});
    return response;
}

# Maps what the user's `post invocations` resource returned to the response.
#
# + result - The return value, or the error it returned or panicked with
# + context - The request context, for logging
# + return - The response
isolated function toInvocationResponse(any|error result, Context context) returns InvocationResponse {
    if result is error {
        return errorResultResponse(result, context);
    }
    if result is anydata {
        return jsonResponse(result, context);
    }
    if result is InvocationResponse {
        return result;
    }
    if result is stream<any|error, error?> {
        // Streaming is not supported yet; the compiler plugin rejects a stream return type.
        error? closed = result.close();
        if closed is error {
            log:printDebug("Closing the unsent stream failed", closed);
        }
    }
    return errorResultResponse(error("the 'post invocations' resource returned a value the listener can't send"),
            context);
}

# Sends any `anydata` value, including `()` and `string`, as `200 application/json`.
#
# + value - The value
# + context - The request context, for logging
# + return - The response
isolated function jsonResponse(anydata value, Context context) returns http:Response {
    // As `py/runtime/app.py:600-601` does with `json.dumps`. Built explicitly so the http module doesn't answer a
    // `post` resource with `201`. A cyclic value can't be serialized, and `toJsonString` panics on it.
    string|error body = trap value.toJsonString();
    if body is error {
        return errorResultResponse(body, context);
    }
    http:Response response = new;
    response.setTextPayload(body, APPLICATION_JSON);
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

# Maps an error of the user's resource to a response.
#
# + err - The error
# + context - The request context, for logging
# + return - The response
isolated function errorResultResponse(error err, Context context) returns http:Response {
    // A 4xx `httpscerr` error keeps its status and message. Anything else gets its status (500 for a plain error) and
    // a generic message: AgentCore shows the caller only a 424, and the message could leak internals. The error and its
    // cause chain are logged, since CloudWatch is the only place to diagnose a 424.
    int statusCode = statusCodeOf(err);
    // A `DefaultStatusCodeError` can carry any status; outside 4xx and 5xx it would read as a success or a redirect.
    if statusCode < 400 || statusCode > 599 {
        statusCode = http:STATUS_INTERNAL_SERVER_ERROR;
    }
    if statusCode < 500 {
        log:printWarn("The invocation was rejected", err, requestId = context.requestId,
                sessionId = context.sessionId, status = statusCode);
        return errorResponse(statusCode, err.message());
    }
    log:printError("The invocation failed", err, requestId = context.requestId, sessionId = context.sessionId,
            status = statusCode);
    return errorResponse(statusCode, INTERNAL_SERVER_ERROR_MESSAGE);
}
