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
import ballerina/jballerina.java;
import ballerina/uuid;

// Headers agent code may not see, from the runtime-header-allowlist page as listed in `py/runtime/models.py:29-159`.
// Stored lower-case.
final readonly & map<()> RESTRICTED_HEADERS = {
    // Authentication and authorization
    "proxy-authorization": (),
    "www-authenticate": (),
    // Content negotiation
    "accept": (),
    "accept-charset": (),
    "accept-encoding": (),
    "accept-language": (),
    "content-type": (),
    "content-length": (),
    "content-encoding": (),
    "content-language": (),
    "content-location": (),
    "content-range": (),
    // Caching
    "cache-control": (),
    "etag": (),
    "expires": (),
    "if-match": (),
    "if-modified-since": (),
    "if-none-match": (),
    "if-range": (),
    "if-unmodified-since": (),
    "last-modified": (),
    "pragma": (),
    "vary": (),
    // Connection management
    "connection": (),
    "keep-alive": (),
    "proxy-connection": (),
    "upgrade": (),
    // Request context
    "host": (),
    "user-agent": (),
    "referer": (),
    "from": (),
    // Range and transfer
    "range": (),
    "accept-ranges": (),
    "transfer-encoding": (),
    "te": (),
    "trailer": (),
    // Server information
    "server": (),
    "date": (),
    "location": (),
    "retry-after": (),
    // Cookies
    "set-cookie": (),
    "cookie": (),
    // Security
    "content-security-policy": (),
    "content-security-policy-report-only": (),
    "strict-transport-security": (),
    "x-content-type-options": (),
    "x-frame-options": (),
    "x-xss-protection": (),
    "referrer-policy": (),
    "permissions-policy": (),
    "cross-origin-embedder-policy": (),
    "cross-origin-opener-policy": (),
    "cross-origin-resource-policy": (),
    // CORS
    "access-control-allow-origin": (),
    "access-control-allow-methods": (),
    "access-control-allow-headers": (),
    "access-control-allow-credentials": (),
    "access-control-expose-headers": (),
    "access-control-max-age": (),
    "access-control-request-method": (),
    "access-control-request-headers": (),
    "origin": (),
    // Client hints
    "accept-ch": (),
    "accept-ch-lifetime": (),
    "dpr": (),
    "width": (),
    "viewport-width": (),
    "downlink": (),
    "ect": (),
    "rtt": (),
    "save-data": (),
    // Experimental or proposed
    "clear-site-data": (),
    "feature-policy": (),
    "expect-ct": (),
    "public-key-pins": (),
    "public-key-pins-report-only": (),
    // Proxy
    "via": (),
    "forwarded": (),
    "x-forwarded-for": (),
    "x-forwarded-host": (),
    "x-forwarded-proto": (),
    "x-real-ip": (),
    "x-requested-with": (),
    "x-csrf-token": (),
    // IP spoofing and URL manipulation
    "true-client-ip": (),
    "x-client-ip": (),
    "x-cluster-client-ip": (),
    "x-originating-ip": (),
    "x-source-ip": (),
    "x-original-url": (),
    "x-original-host": (),
    "x-rewrite-url": (),
    // CDN and proxy
    "cf-ray": (),
    "cf-connecting-ip": (),
    "x-amz-cf-id": (),
    "x-cache": (),
    "x-served-by": (),
    // HTTP/2 pseudo-headers
    ":method": (),
    ":path": (),
    ":scheme": (),
    ":authority": (),
    ":status": (),
    // Server push
    "link": (),
    // WebSocket
    "sec-websocket-key": (),
    "sec-websocket-accept": (),
    "sec-websocket-version": (),
    "sec-websocket-protocol": (),
    "sec-websocket-extensions": ()
};

final string CUSTOM_PREFIX_LOWER = HEADER_CUSTOM_PREFIX.toLowerAscii();
final string AUTHORIZATION_LOWER = HEADER_AUTHORIZATION.toLowerAscii();
final string IDENTITY_WAT_LOWER = HEADER_IDENTITY_WAT.toLowerAscii();

# Builds the `agentcore:Context` of a request (`py/runtime/app.py:405-434`).
#
# + request - The request
# + return - The context
isolated function contextFromRequest(http:Request request) returns Context {
    map<string> customHeaders = {};
    map<string> requestHeaders = {};
    foreach string name in request.getHeaderNames() {
        string|http:HeaderNotFoundError value = request.getHeader(name);
        if value is http:HeaderNotFoundError {
            continue;
        }
        string lower = name.toLowerAscii();
        if lower.startsWith(CUSTOM_PREFIX_LOWER) {
            customHeaders[lower] = value;
        }
        // `py/runtime/app.py:430-434`: Authorization is kept under its canonical name; the rest follow the allowlist,
        // keyed by lower-case name as Starlette's `headers.items()` yields them.
        if lower == AUTHORIZATION_LOWER {
            requestHeaders[HEADER_AUTHORIZATION] = value;
        } else if isForwardableHeader(lower) {
            requestHeaders[lower] = value;
        }
    }
    return {
        sessionId: headerValue(request, HEADER_SESSION_ID),
        // `py/runtime/app.py:409-411`, `ts/runtime/app.ts:571`.
        requestId: headerValue(request, HEADER_REQUEST_ID) ?: uuid:createType4AsString(),
        userId: headerValue(request, HEADER_USER_ID),
        // `py/runtime/app.py:416`, `ts/runtime/app.ts:597`: the WAT header takes priority.
        workloadAccessToken: headerValue(request, HEADER_IDENTITY_WAT)
            ?: headerValue(request, HEADER_WORKLOAD_ACCESS_TOKEN),
        oauth2CallbackUrl: headerValue(request, HEADER_OAUTH2_CALLBACK_URL),
        authorization: headerValue(request, HEADER_AUTHORIZATION),
        customHeaders,
        requestHeaders,
        headers: createHeaders(request)
    };
}

# Returns whether agent code may see a header, as `is_forwardable_header` (`py/runtime/models.py:178-198`) decides.
#
# + lowerName - The header name in lower case
# + return - `true` when the header is forwardable
isolated function isForwardableHeader(string lowerName) returns boolean {
    if RESTRICTED_HEADERS.hasKey(lowerName) {
        return false;
    }
    if lowerName.startsWith("x-amz-") {
        return lowerName == IDENTITY_WAT_LOWER;
    }
    return !lowerName.startsWith("x-amzn-") || lowerName.startsWith(CUSTOM_PREFIX_LOWER);
}

# Returns the first value of a header (names are case-insensitive), or `()` when it is absent or empty.
#
# + request - The request
# + name - The header name
# + return - The value, or `()`
isolated function headerValue(http:Request request, string name) returns string? {
    string|http:HeaderNotFoundError value = request.getHeader(name);
    return value is string && value != "" ? value : ();
}

isolated function createHeaders(http:Request request) returns http:Headers = @java:Method {
    'class: "io.ballerina.lib.ai.aws.bedrock.agentcore.NativeResourceInvoker"
} external;
