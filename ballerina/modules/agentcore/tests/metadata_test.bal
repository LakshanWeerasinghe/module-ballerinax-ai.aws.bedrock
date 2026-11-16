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

import ballerina/io;
import ballerina/test;

// Tests run from the package root, where the metadata lives.
const TRIGGER_METADATA = "metadata/trigger-metadata.json";
const TRIGGER_UI_METADATA = "metadata/trigger-ui-metadata.json";

@test:Config
function testTriggerMetadataMatchesDispatcher() returns error? {
    json metadata = check io:fileReadJson(TRIGGER_METADATA);
    json[] listeners = check (check metadata.listeners).ensureType();
    test:assertEquals(check listeners[0].'type.name, "Listener");
    test:assertEquals(check listeners[0].'type.packageInfo.moduleName, "ai.aws.bedrock.agentcore");
    // The metadata names the package version, so a version bump must update it too.
    string ballerinaToml = check io:fileReadString("Ballerina.toml");
    string version = check listeners[0].'type.packageInfo.version;
    test:assertTrue(ballerinaToml.includes(string `version = "${version}"`), version);

    json[] serviceTypes = check (check metadata.serviceTypes).ensureType();
    test:assertEquals(check serviceTypes[0].'type.name, "Service");
    json[] handlers = check (check serviceTypes[0].handlers.options).ensureType();
    map<string> pathsByAccessor = {};
    foreach json handler in handlers {
        string[] accessors = check (check handler.accessor.values).cloneWithType();
        string[] paths = check (check handler.path.values).cloneWithType();
        test:assertEquals(check handler.presence, "required");
        pathsByAccessor[accessors[0]] = paths[0];
    }
    test:assertEquals(pathsByAccessor, {get: PING_PATH, post: INVOCATIONS_PATH});
}

@test:Config
function testTriggerUiMetadataTargetsExist() returns error? {
    json metadata = check io:fileReadJson(TRIGGER_METADATA);
    string metadataText = metadata.toJsonString();
    json ui = check io:fileReadJson(TRIGGER_UI_METADATA);
    test:assertEquals(check ui.trigger.displayName, "Amazon Bedrock AgentCore Service");
    json[] serviceTypes = check (check ui.serviceTypes).ensureType();
    json[] handlers = check (check serviceTypes[0].handlers).ensureType();
    foreach json handler in handlers {
        string target = check handler.target;
        test:assertTrue(metadataText.includes(string `"${target}"`), target);
    }
    json[] listeners = check (check ui.listeners).ensureType();
    test:assertEquals(check listeners[0].formFields.listenOn.placeholder, DEFAULT_PORT.toString());
}
