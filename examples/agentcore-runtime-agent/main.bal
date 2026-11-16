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

import ballerina/ai;
import ballerina/http;
import ballerina/log;
import ballerinax/ai.aws.bedrock;
import ballerinax/ai.aws.bedrock.agentcore;
import ballerinax/aws.auth;

// From Config.toml or the BAL_CONFIG_VAR_MODELID and BAL_CONFIG_VAR_REGION environment variables.
configurable string modelId = ?;
configurable string region = ?;

type Prompt record {
    string prompt;
};

final ai:ShortTermMemory memory = check new;

final ai:Agent agent = check new ({
    systemPrompt: {
        role: "Helpful Assistant",
        instructions: "You are a helpful assistant running on Amazon Bedrock AgentCore Runtime. Answer concisely."
    },
    // The default credential chain picks up the AgentCore execution role through the instance metadata service.
    model: check new bedrock:ConverseModelProvider(modelId, auth:DEFAULT_CREDENTIALS, region),
    // In-memory history, kept per memory key (see below). AgentCore gives each session its own microVM, which ends
    // after 15 idle minutes or 8 hours at most; use a persistent `ai:ShortTermMemoryStore` to keep history beyond that.
    memory
});

// `ai:Agent.run` requires the calls for one memory key to run one after another. A `lock` on an isolated object holds
// that object only, so each memory key gets its own `ConversationTurns`: turns of one conversation wait for each
// other, and different conversations run concurrently. Adapted from the Foundry hosted agent example of
// ballerinax/ai.azure.
isolated class ConversationTurns {
    private int count = 0;

    isolated function run(string message, string memoryKey) returns string|error {
        lock {
            self.count += 1;
            return agent.run(message, memoryKey);
        }
    }
}

isolated map<ConversationTurns> conversations = {};

isolated function conversationTurns(string memoryKey) returns ConversationTurns {
    lock {
        ConversationTurns? turns = conversations[memoryKey];
        if turns is ConversationTurns {
            return turns;
        }
        ConversationTurns created = new;
        conversations[memoryKey] = created;
        return created;
    }
}

isolated function forgetConversation(string memoryKey) {
    lock {
        _ = conversations.removeIfHasKey(memoryKey);
    }
    ai:MemoryError? deleted = memory.delete(memoryKey);
    if deleted is ai:MemoryError {
        log:printWarn("Dropping the conversation history failed", deleted);
    }
}

// Listens on 8080, the port AgentCore Runtime calls.
listener agentcore:Listener agentCoreListener = new;

service on agentCoreListener {

    // AgentCore's health check. Keep it cheap; it never calls the model.
    resource function get ping() returns agentcore:PingStatus => agentcore:HEALTHY;

    resource function post invocations(@http:Payload Prompt payload, agentcore:Context ctx) returns json|error {
        // One history per session. A call without a session ID gets the request ID, so sessionless calls never share
        // history.
        string memoryKey = ctx.sessionId ?: ctx.requestId;
        string|error reply = conversationTurns(memoryKey).run(payload.prompt, memoryKey);
        if ctx.sessionId is () {
            // A sessionless call is never continued, so its history is dropped.
            forgetConversation(memoryKey);
        }
        return {response: check reply};
    }
}
