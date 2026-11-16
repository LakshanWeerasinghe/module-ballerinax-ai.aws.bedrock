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

import ballerina/data.jsondata;
import ballerina/http;
import ballerina/jballerina.java;
import ballerina/log;

// http-protocol-contract: the platform calls `GET /ping` and `POST /invocations`.
const PING_PATH = "ping";
const INVOCATIONS_PATH = "invocations";

// 400 messages for a body that can't be bound. They never quote the body.
const PAYLOAD_EMPTY_MESSAGE = "The request body is empty.";
const PAYLOAD_UNREADABLE_MESSAGE = "The request body could not be read.";
const PAYLOAD_NOT_JSON_MESSAGE = "The request body is not valid JSON.";
const PAYLOAD_STRING_NOT_JSON_MESSAGE = "The request body must be JSON; a `string` payload is read as a JSON string.";
const PAYLOAD_TYPE_MISMATCH_MESSAGE = "The request body does not match the expected payload type.";

const NATIVE_SERVICE_ADAPTOR = "io.ballerina.lib.ai.aws.bedrock.agentcore.NativeServiceAdaptor";
const NATIVE_RESOURCE_INVOKER = "io.ballerina.lib.ai.aws.bedrock.agentcore.NativeResourceInvoker";

# What the dispatcher needs to know about a resource before calling it.
#
# + payloadType - The declared `@http:Payload` type, or `()` when there is none
# + hasContext - Whether the resource declares an `agentcore:Context` parameter
type ResourceSignature record {|
    typedesc<anydata>? payloadType;
    boolean hasContext;
|};

# The request body can't be bound to the declared payload type. The message never quotes the body.
type PayloadBindingError distinct error;

isolated function bindPayload(http:Request request, typedesc<anydata> payloadType)
        returns anydata|PayloadBindingError {
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is http:ClientError {
        return payloadBindingError(PAYLOAD_UNREADABLE_MESSAGE, body);
    }
    return bindPayloadBytes(body, payloadType);
}

# Binds the body to the declared type: `byte[]` gets the raw bytes; any other type is parsed from JSON,
# as `py/runtime/app.py:547` reads every body as JSON.
#
# + body - The request body
# + payloadType - The declared payload type
# + return - The payload, or an error whose message is safe to send
isolated function bindPayloadBytes(byte[] body, typedesc<anydata> payloadType)
        returns anydata|PayloadBindingError {
    anydata nil = ();
    if body.length() == 0 && nil.ensureType(payloadType) !is error {
        return ();
    }
    if payloadType is typedesc<byte[]?> {
        anydata|error bytes = body.ensureType(payloadType);
        return bytes is error ? payloadBindingError(PAYLOAD_TYPE_MISMATCH_MESSAGE, bytes) : bytes;
    }
    if body.length() == 0 {
        return payloadBindingError(PAYLOAD_EMPTY_MESSAGE);
    }
    // Strict, as the http module's record binding is: a closed record rejects unknown fields. The parse is
    // trapped because some malformed bodies make `parseBytes` panic, which would leave the request unanswered.
    anydata|error payload = trap jsondata:parseBytes(body, {allowDataProjection: false}, payloadType);
    if payload !is error {
        return payload;
    }
    json|error document = trap jsondata:parseBytes(body);
    if document !is error {
        return payloadBindingError(PAYLOAD_TYPE_MISMATCH_MESSAGE, payload);
    }
    return payloadBindingError(payloadType is typedesc<string?> ? PAYLOAD_STRING_NOT_JSON_MESSAGE
        : PAYLOAD_NOT_JSON_MESSAGE, payload);
}

# Creates a payload binding error. Parser messages quote the body, so only the cause's type is logged, at debug.
#
# + message - The message sent to the caller
# + cause - The underlying error, if any
# + return - The payload binding error
isolated function payloadBindingError(string message, error? cause = ()) returns PayloadBindingError {
    if cause is error {
        log:printDebug("Request body binding failed: " + message, causeType = errorTypeName(cause));
    }
    return error PayloadBindingError(message);
}

isolated function errorTypeName(error err) returns string = @java:Method {
    'class: NATIVE_RESOURCE_INVOKER
} external;

isolated function getResourceSignature(DispatcherService dispatcher, string accessor, string[] path)
        returns ResourceSignature|error? = @java:Method {
    'class: NATIVE_RESOURCE_INVOKER
} external;

isolated function invokeResource(DispatcherService dispatcher, string accessor, string[] path, anydata payload,
        Context? context) returns any|error = @java:Method {
    'class: NATIVE_RESOURCE_INVOKER
} external;

isolated function setUserService(DispatcherService dispatcher, Service agentCoreService) = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;

isolated function getUserService(DispatcherService dispatcher) returns Service? = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;

isolated function unlinkUserService(DispatcherService dispatcher) = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;

isolated function registerDispatcher(Service agentCoreService, Listener agentCoreListener,
        DispatcherService dispatcher) returns boolean = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;

isolated function getDispatcher(Service agentCoreService, Listener agentCoreListener)
        returns DispatcherService? = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;

isolated function removeDispatcher(Service agentCoreService, Listener agentCoreListener)
        returns DispatcherService? = @java:Method {
    'class: NATIVE_SERVICE_ADAPTOR
} external;
