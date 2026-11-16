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

import ballerina/jballerina.java;

const NATIVE_SERVICE_ADAPTOR = "io.ballerina.lib.ai.aws.bedrock.agentcore.NativeServiceAdaptor";

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
