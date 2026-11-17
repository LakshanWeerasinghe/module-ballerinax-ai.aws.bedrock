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

import ballerina/http.httpscerr;

# Returns the status the http module would send for an error (its `getStatusCode`). Copied from the Foundry
# listener's `statusCodeOf`.
#
# + err - The error
# + return - The status code; `500` for an error that carries none
isolated function statusCodeOf(error err) returns int {
    if err is httpscerr:'4XXStatusCodeError {
        return clientErrorStatusCodeOf(err);
    }
    if err is httpscerr:NotImplementedError {
        return 501;
    } else if err is httpscerr:BadGatewayError {
        return 502;
    } else if err is httpscerr:ServiceUnavailableError {
        return 503;
    } else if err is httpscerr:GatewayTimeoutError {
        return 504;
    } else if err is httpscerr:HTTPVersionNotSupportedError {
        return 505;
    } else if err is httpscerr:VariantAlsoNegotiatesError {
        return 506;
    } else if err is httpscerr:InsufficientStorageError {
        return 507;
    } else if err is httpscerr:LoopDetectedError {
        return 508;
    } else if err is httpscerr:NotExtendedError {
        return 510;
    } else if err is httpscerr:NetworkAuthenticationRequiredError {
        return 511;
    } else if err is httpscerr:DefaultStatusCodeError {
        int? statusCode = err.detail()?.statusCode;
        if statusCode is int {
            return statusCode;
        }
        error? cause = err.cause();
        if cause is error {
            return statusCodeOf(cause);
        }
    }
    return 500;
}

isolated function clientErrorStatusCodeOf(httpscerr:'4XXStatusCodeError err) returns int {
    if err is httpscerr:BadRequestError {
        return 400;
    } else if err is httpscerr:UnauthorizedError {
        return 401;
    } else if err is httpscerr:PaymentRequiredError {
        return 402;
    } else if err is httpscerr:ForbiddenError {
        return 403;
    } else if err is httpscerr:NotFoundError {
        return 404;
    } else if err is httpscerr:MethodNotAllowedError {
        return 405;
    } else if err is httpscerr:NotAcceptableError {
        return 406;
    } else if err is httpscerr:ProxyAuthenticationRequiredError {
        return 407;
    } else if err is httpscerr:RequestTimeoutError {
        return 408;
    } else if err is httpscerr:ConflictError {
        return 409;
    } else if err is httpscerr:GoneError {
        return 410;
    } else if err is httpscerr:LengthRequiredError {
        return 411;
    } else if err is httpscerr:PreconditionFailedError {
        return 412;
    } else if err is httpscerr:PayloadTooLargeError {
        return 413;
    } else if err is httpscerr:URITooLongError {
        return 414;
    } else if err is httpscerr:UnsupportedMediaTypeError {
        return 415;
    } else if err is httpscerr:RangeNotSatisfiableError {
        return 416;
    } else if err is httpscerr:ExpectationFailedError {
        return 417;
    } else if err is httpscerr:MisdirectedRequestError {
        return 421;
    } else if err is httpscerr:UnprocessableEntityError {
        return 422;
    } else if err is httpscerr:LockedError {
        return 423;
    } else if err is httpscerr:FailedDependencyError {
        return 424;
    } else if err is httpscerr:UpgradeRequiredError {
        return 426;
    } else if err is httpscerr:PreconditionRequiredError {
        return 428;
    } else if err is httpscerr:TooManyRequestsError {
        return 429;
    } else if err is httpscerr:RequestHeaderFieldsTooLargeError {
        return 431;
    } else if err is httpscerr:UnavailableDueToLegalReasonsError {
        return 451;
    }
    return 400;
}
