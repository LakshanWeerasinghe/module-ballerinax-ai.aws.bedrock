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
import ballerina/test;

@test:Config
function testClientErrorStatusCodes() {
    [error, int][] cases = [
        [error httpscerr:BadRequestError("e"), 400],
        [error httpscerr:UnauthorizedError("e"), 401],
        [error httpscerr:PaymentRequiredError("e"), 402],
        [error httpscerr:ForbiddenError("e"), 403],
        [error httpscerr:NotFoundError("e"), 404],
        [error httpscerr:MethodNotAllowedError("e"), 405],
        [error httpscerr:NotAcceptableError("e"), 406],
        [error httpscerr:ProxyAuthenticationRequiredError("e"), 407],
        [error httpscerr:RequestTimeoutError("e"), 408],
        [error httpscerr:ConflictError("e"), 409],
        [error httpscerr:GoneError("e"), 410],
        [error httpscerr:LengthRequiredError("e"), 411],
        [error httpscerr:PreconditionFailedError("e"), 412],
        [error httpscerr:PayloadTooLargeError("e"), 413],
        [error httpscerr:URITooLongError("e"), 414],
        [error httpscerr:UnsupportedMediaTypeError("e"), 415],
        [error httpscerr:RangeNotSatisfiableError("e"), 416],
        [error httpscerr:ExpectationFailedError("e"), 417],
        [error httpscerr:MisdirectedRequestError("e"), 421],
        [error httpscerr:UnprocessableEntityError("e"), 422],
        [error httpscerr:LockedError("e"), 423],
        [error httpscerr:FailedDependencyError("e"), 424],
        [error httpscerr:UpgradeRequiredError("e"), 426],
        [error httpscerr:PreconditionRequiredError("e"), 428],
        [error httpscerr:TooManyRequestsError("e"), 429],
        [error httpscerr:RequestHeaderFieldsTooLargeError("e"), 431],
        [error httpscerr:UnavailableDueToLegalReasonsError("e"), 451],
        [error httpscerr:'4XXStatusCodeError("e"), 400]
    ];
    foreach [error, int] [err, expected] in cases {
        test:assertEquals(statusCodeOf(err), expected, errorTypeName(err));
    }
}

@test:Config
function testServerErrorStatusCodes() {
    [error, int][] cases = [
        [error httpscerr:InternalServerErrorError("e"), 500],
        [error httpscerr:NotImplementedError("e"), 501],
        [error httpscerr:BadGatewayError("e"), 502],
        [error httpscerr:ServiceUnavailableError("e"), 503],
        [error httpscerr:GatewayTimeoutError("e"), 504],
        [error httpscerr:HTTPVersionNotSupportedError("e"), 505],
        [error httpscerr:VariantAlsoNegotiatesError("e"), 506],
        [error httpscerr:InsufficientStorageError("e"), 507],
        [error httpscerr:LoopDetectedError("e"), 508],
        [error httpscerr:NotExtendedError("e"), 510],
        [error httpscerr:NetworkAuthenticationRequiredError("e"), 511],
        [error httpscerr:'5XXStatusCodeError("e"), 500],
        [error("plain"), 500]
    ];
    foreach [error, int] [err, expected] in cases {
        test:assertEquals(statusCodeOf(err), expected, errorTypeName(err));
    }
}

@test:Config
function testDefaultStatusCodeError() {
    // An explicit status code wins; without one, the cause decides; with neither, it is a 500.
    test:assertEquals(statusCodeOf(error httpscerr:DefaultStatusCodeError("e", statusCode = 418)), 418);
    test:assertEquals(statusCodeOf(error httpscerr:DefaultStatusCodeError("e",
        error httpscerr:ConflictError("cause"))), 409);
    test:assertEquals(statusCodeOf(error httpscerr:DefaultStatusCodeError("e")), 500);
}
