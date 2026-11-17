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

// The listener follows the AgentCore Runtime HTTP protocol contract. Sources cited in this module:
// - AWS devguide: runtime-http-protocol-contract, runtime-service-contract, runtime-header-allowlist,
//   runtime-configure-invocation, runtime-troubleshooting, bedrock-agentcore-limits
//   (https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/<page>.html).
// - botocore `bedrock-agentcore-control/2023-06-05/service-2.json` and `bedrock-agentcore/2024-02-28/service-2.json`.
// - `aws/bedrock-agentcore-sdk-python` at `fda8209ff1ac1ce62f642a1bc3ca28b8ff64f038`, cited as `py/<file>:<lines>`
//   relative to `src/bedrock_agentcore/`.
// - `aws/bedrock-agentcore-sdk-typescript` at `6f45fd0176847c5fceec167d6cae91a4a238edbe`, cited as `ts/<file>:<lines>`
//   relative to `src/`.
// The structure (dispatcher, native service link, reflective resource invoker) is adapted from the Foundry listener
// of `ballerina-platform/module-ballerinax-ai.azure` at `f4abc4e`.

# A listener that runs an `agentcore:InvocationService` on Amazon Bedrock AgentCore Runtime.
# It serves `GET /ping` and `POST /invocations` on port 8080 by default.
public isolated class Listener {
    private final http:Listener httpListener;

    # Initializes the listener.
    #
    # + listenOn - The port (8080 by default), or an `http:Listener` to share. A shared one keeps its own
    #              configuration; give it `timeout = 900` and `requestLimits = {maxHeaderSize: 98304}`
    # + config - The listener configuration; with a shared `http:Listener`, anything but the defaults is an error
    # + return - An error if the listener cannot be created, or if `config` is set with a shared `http:Listener`
    public isolated function init(int|http:Listener? listenOn = (), *ListenerConfiguration config) returns error? {
        if listenOn is http:Listener {
            // The shared listener is already created, so a configuration given here could never take effect.
            ListenerConfiguration defaults = {};
            if config != defaults {
                return error("An agentcore:Listener that shares an http:Listener can't apply a configuration of its "
                    + "own. Configure the http:Listener instead, or pass a port.");
            }
            string? warning = belowAgentCoreDefaults(listenOn.getConfig());
            if warning is string {
                log:printWarn(warning);
            }
            self.httpListener = listenOn;
        } else {
            self.httpListener = check new (listenOn ?: DEFAULT_PORT, config);
        }
    }

    # Attaches a service at the root base path.
    #
    # + agentCoreService - The service to attach
    # + name - The base path; only the root is accepted
    # + return - An error if the base path is not the root or the service is already attached
    public isolated function attach(InvocationService agentCoreService, string[]|string? name = ()) returns error? {
        if !isRootBasePath(name) {
            return error(string `An agentcore:InvocationService must be attached at the root base path, `
                + string `because AgentCore calls /ping and /invocations there: got '${basePathToString(name)}'`);
        }
        // The dispatcher stands in for the user's service on the http:Listener. It is linked before it is
        // attached, so it never serves a request without the link.
        DispatcherService dispatcher = new;
        setUserService(dispatcher, agentCoreService);
        if !registerDispatcher(agentCoreService, self, dispatcher) {
            unlinkUserService(dispatcher);
            return error("The agentcore:InvocationService is already attached to this agentcore:Listener");
        }
        error? result = self.httpListener.attach(dispatcher, name);
        if result is error {
            _ = removeDispatcher(agentCoreService, self);
            unlinkUserService(dispatcher);
            return result;
        }
    }

    # Detaches a service. Detaching a service that is not attached does nothing.
    #
    # + agentCoreService - The service to detach
    # + return - An error if the service cannot be detached
    public isolated function detach(InvocationService agentCoreService) returns error? {
        // Only this listener's dispatcher is detached, so the service keeps working on any other listener.
        DispatcherService? dispatcher = removeDispatcher(agentCoreService, self);
        if dispatcher is () {
            return;
        }
        error? result = self.httpListener.detach(dispatcher);
        if result is error {
            if !registerDispatcher(agentCoreService, self, dispatcher) {
                log:printError("The agentcore:InvocationService is still attached to the http:Listener after a "
                    + "failed detach, but another attach replaced its record, so detach can no longer reach it.");
            }
            return result;
        }
        // The dispatcher stays linked: requests that http accepted before the detach still run to completion, and the
        // dispatcher is released once they finish.
    }

    # Starts the listener.
    #
    # + return - An error if the listener cannot be started
    public isolated function 'start() returns error? {
        check self.httpListener.'start();
    }

    # Stops the listener after in-flight requests finish, up to `gracefulStopTimeout`.
    #
    # + return - An error if the listener cannot be stopped
    public isolated function gracefulStop() returns error? {
        check self.httpListener.gracefulStop();
    }

    # Stops the listener immediately.
    #
    # + return - An error if the listener cannot be stopped
    public isolated function immediateStop() returns error? {
        check self.httpListener.immediateStop();
    }
}

// A shared listener keeps its own configuration, which `getConfig` reads back, so only a timeout or header limit below
// AgentCore's is reported. A timeout of 0 disables it, which is fine.
isolated function belowAgentCoreDefaults(http:InferredListenerConfiguration shared) returns string? {
    ListenerConfiguration defaults = {};
    boolean shortTimeout = shared.timeout > 0d && shared.timeout < defaults.timeout;
    boolean smallHeaders = shared.requestLimits.maxHeaderSize < defaults.requestLimits.maxHeaderSize;
    if !shortTimeout && !smallHeaders {
        return ();
    }
    return string `The http:Listener shared with the agentcore:Listener has timeout = ${shared.timeout} and `
        + string `requestLimits.maxHeaderSize = ${shared.requestLimits.maxHeaderSize}. Use at least `
        + string `${defaults.timeout} and ${defaults.requestLimits.maxHeaderSize}, or long agent turns and large `
        + "header sets fail with a 424 from AgentCore.";
}

isolated function isRootBasePath(string[]|string? name) returns boolean {
    if name is () {
        return true;
    }
    if name is string {
        return re `/*`.isFullMatch(name.trim());
    }
    foreach string segment in name {
        if !re `/*`.isFullMatch(segment.trim()) {
            return false;
        }
    }
    return true;
}

isolated function basePathToString(string[]|string? name) returns string {
    if name is string[] {
        return "/" + string:'join("/", ...name);
    }
    return name ?: "";
}
