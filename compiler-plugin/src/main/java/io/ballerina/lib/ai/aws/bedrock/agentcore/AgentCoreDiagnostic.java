/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.ai.aws.bedrock.agentcore;

import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticFactory;
import io.ballerina.tools.diagnostics.DiagnosticInfo;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;

import static io.ballerina.tools.diagnostics.DiagnosticSeverity.ERROR;

/**
 * Compilation diagnostics for an {@code agentcore:InvocationService}. Each message is a {@link java.text.MessageFormat}
 * template.
 *
 * @since 1.1.0
 */
public enum AgentCoreDiagnostic {

    MISSING_INVOCATIONS_RESOURCE("AI_AWS_BEDROCK_AGENTCORE_101",
            "an `agentcore:InvocationService` must declare a `resource function post invocations`, "
                    + "which serves `POST /invocations`.", ERROR),
    MISSING_PING_RESOURCE("AI_AWS_BEDROCK_AGENTCORE_102",
            "an `agentcore:InvocationService` must declare a `resource function get ping`, which "
                    + "serves the `GET /ping` health check.", ERROR),
    UNSUPPORTED_RESOURCE("AI_AWS_BEDROCK_AGENTCORE_103",
            "the resource ''{0}'' is not supported in an `agentcore:InvocationService`, which "
                    + "serves only `get ping` and `post invocations`.", ERROR),
    REMOTE_FUNCTION_NOT_ALLOWED("AI_AWS_BEDROCK_AGENTCORE_104",
            "the remote function ''{0}'' is not allowed in an `agentcore:InvocationService`; "
                    + "declare resource functions instead.", ERROR),
    PING_PARAMETER_NOT_ALLOWED("AI_AWS_BEDROCK_AGENTCORE_105",
            "the parameter ''{0}'' of the resource ''get ping'' is not supported: the resource must declare no "
                    + "parameters.", ERROR),
    INVALID_PING_RETURN_TYPE("AI_AWS_BEDROCK_AGENTCORE_106",
            "the resource ''get ping'' must return a subtype of `agentcore:PingStatus|error`, found ''{0}''.",
            ERROR),
    UNSUPPORTED_PARAMETER("AI_AWS_BEDROCK_AGENTCORE_107",
            "the parameter ''{0}'' of the resource ''post invocations'' is not supported. Declare only an "
                    + "`@http:Payload` parameter and an `agentcore:Context` parameter.", ERROR),
    DUPLICATE_PAYLOAD_PARAMETER("AI_AWS_BEDROCK_AGENTCORE_108",
            "the resource ''post invocations'' declares more than one `@http:Payload` parameter.", ERROR),
    DUPLICATE_CONTEXT_PARAMETER("AI_AWS_BEDROCK_AGENTCORE_109",
            "the resource ''post invocations'' declares more than one `agentcore:Context` parameter.", ERROR),
    INVALID_PAYLOAD_TYPE("AI_AWS_BEDROCK_AGENTCORE_110",
            "the `@http:Payload` parameter ''{0}'' of the resource ''post invocations'' must be a subtype of "
                    + "`anydata`, found ''{1}''.", ERROR),
    INVALID_RETURN_TYPE("AI_AWS_BEDROCK_AGENTCORE_111",
            "the resource ''post invocations'' must return a subtype of "
                    + "`anydata|http:Response|http:StatusCodeResponse|error`, found ''{0}''.", ERROR),
    STREAM_RETURN_TYPE("AI_AWS_BEDROCK_AGENTCORE_112",
            "the resource ''{0}'' returns a stream (''{1}''), but streaming is not supported yet; return the "
                    + "complete response instead.", ERROR),
    INVALID_BASE_PATH("AI_AWS_BEDROCK_AGENTCORE_113",
            "an `agentcore:InvocationService` must be attached at the root base path, because "
                    + "AgentCore calls `/ping` and `/invocations` at the root; remove the base path ''{0}''.", ERROR);

    private final String code;
    private final String message;
    private final DiagnosticSeverity severity;

    AgentCoreDiagnostic(String code, String message, DiagnosticSeverity severity) {
        this.code = code;
        this.message = message;
        this.severity = severity;
    }

    public static Diagnostic createDiagnostic(AgentCoreDiagnostic diagnostic, Location location, Object... args) {
        DiagnosticInfo info = new DiagnosticInfo(diagnostic.code, diagnostic.message, diagnostic.severity);
        return DiagnosticFactory.createDiagnostic(info, location, args);
    }

    public String getCode() {
        return code;
    }
}
