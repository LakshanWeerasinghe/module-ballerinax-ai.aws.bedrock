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

import io.ballerina.projects.DiagnosticResult;
import io.ballerina.projects.Project;
import io.ballerina.projects.ProjectEnvironmentBuilder;
import io.ballerina.projects.directory.ProjectLoader;
import io.ballerina.projects.environment.Environment;
import io.ballerina.projects.environment.EnvironmentBuilder;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.text.LinePosition;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Collectors;

/**
 * Tests the compile-time validation of {@code agentcore:InvocationService}.
 *
 * <p>Each test compiles a sample package against a Ballerina distribution holding the freshly built
 * {@code ballerinax/ai.aws.bedrock} bala (see the {@code prepareBallerinaDistribution} task) and asserts the exact
 * AgentCore diagnostics: code, severity, message and position, in source order. Adapted from the Foundry tests in
 * {@code ballerina-platform/module-ballerinax-ai.azure} at {@code f4abc4e}.
 */
public class AgentCoreServiceValidationTest {

    private static final Path RESOURCE_DIRECTORY = Paths.get("src", "test", "resources", "ballerina_sources",
            "agentcore_service_validation").toAbsolutePath();
    private static final Path DISTRIBUTION_PATH = Paths.get(System.getProperty("ai.aws.bedrock.test.distribution",
            Paths.get("build", "ballerina-runtime").toString())).toAbsolutePath();
    private static final String CODE_PREFIX = "AI_AWS_BEDROCK_AGENTCORE_";

    // Written out rather than taken from the plugin, so a broken template fails the tests.
    private static final String MISSING_INVOCATIONS_RESOURCE = "AI_AWS_BEDROCK_AGENTCORE_101";
    private static final String MISSING_PING_RESOURCE = "AI_AWS_BEDROCK_AGENTCORE_102";
    private static final String UNSUPPORTED_RESOURCE = "AI_AWS_BEDROCK_AGENTCORE_103";
    private static final String REMOTE_FUNCTION_NOT_ALLOWED = "AI_AWS_BEDROCK_AGENTCORE_104";
    private static final String PING_PARAMETER_NOT_ALLOWED = "AI_AWS_BEDROCK_AGENTCORE_105";
    private static final String INVALID_PING_RETURN_TYPE = "AI_AWS_BEDROCK_AGENTCORE_106";
    private static final String UNSUPPORTED_PARAMETER = "AI_AWS_BEDROCK_AGENTCORE_107";
    private static final String DUPLICATE_PAYLOAD_PARAMETER = "AI_AWS_BEDROCK_AGENTCORE_108";
    private static final String DUPLICATE_CONTEXT_PARAMETER = "AI_AWS_BEDROCK_AGENTCORE_109";
    private static final String INVALID_RETURN_TYPE = "AI_AWS_BEDROCK_AGENTCORE_111";
    private static final String STREAM_RETURN_TYPE = "AI_AWS_BEDROCK_AGENTCORE_112";
    private static final String INVALID_BASE_PATH = "AI_AWS_BEDROCK_AGENTCORE_113";
    private static final String UNBINDABLE_PAYLOAD_TYPE = "AI_AWS_BEDROCK_AGENTCORE_114";

    @Test
    public void testValidService() {
        assertDiagnostics("01_valid_service");
    }

    @Test
    public void testMissingInvocationsResource() {
        assertDiagnostics("02_missing_invocations",
                expect(MISSING_INVOCATIONS_RESOURCE, 19, 9, missingInvocationsResource()));
    }

    @Test
    public void testMissingPingResource() {
        assertDiagnostics("03_missing_ping",
                expect(MISSING_PING_RESOURCE, 19, 9, missingPingResource()));
    }

    @Test
    public void testPingSignature() {
        assertDiagnostics("04_ping_signature",
                expect(PING_PARAMETER_NOT_ALLOWED, 21, 32, pingParameterNotAllowed("ctx")),
                expect(PING_PARAMETER_NOT_ALLOWED, 21, 55, pingParameterNotAllowed("payload")),
                expect(INVALID_PING_RETURN_TYPE, 28, 42, invalidPingReturnType("string")),
                expect(INVALID_PING_RETURN_TYPE, 34, 31, invalidPingReturnType("()")));
    }

    @Test
    public void testUnsupportedResources() {
        assertDiagnostics("05_unsupported_resource",
                expect(UNSUPPORTED_RESOURCE, 24, 23, unsupportedResource("get invocations")),
                expect(UNSUPPORTED_RESOURCE, 26, 23, unsupportedResource("post ping")),
                expect(UNSUPPORTED_RESOURCE, 28, 23, unsupportedResource("get ws")),
                expect(UNSUPPORTED_RESOURCE, 30, 23, unsupportedResource("post invocations/[string id]")),
                expect(UNSUPPORTED_RESOURCE, 32, 23, unsupportedResource("default [string... path]")));
    }

    @Test
    public void testRemoteFunction() {
        assertDiagnostics("06_remote_function",
                expect(REMOTE_FUNCTION_NOT_ALLOWED, 24, 21, remoteFunctionNotAllowed("invoke")));
    }

    @Test
    public void testUnsupportedParameters() {
        assertDiagnostics("07_unsupported_parameter",
                expect(UNSUPPORTED_PARAMETER, 23, 63, unsupportedParameter("extra")),
                expect(UNSUPPORTED_PARAMETER, 23, 77, unsupportedParameter("request")),
                expect(UNSUPPORTED_PARAMETER, 24, 13, unsupportedParameter("headers")),
                expect(UNSUPPORTED_PARAMETER, 24, 35, unsupportedParameter("maybeCtx")),
                expect(UNSUPPORTED_PARAMETER, 24, 64, unsupportedParameter("rest")));
    }

    @Test
    public void testDuplicatePayloadParameter() {
        assertDiagnostics("08_duplicate_payload",
                expect(DUPLICATE_PAYLOAD_PARAMETER, 23, 66, duplicatePayloadParameter()));
    }

    @Test
    public void testDuplicateContextParameter() {
        assertDiagnostics("09_duplicate_context",
                expect(DUPLICATE_CONTEXT_PARAMETER, 24, 65, duplicateContextParameter()));
    }

    @Test
    public void testInvalidReturnType() {
        assertDiagnostics("11_invalid_return_type",
                expect(INVALID_RETURN_TYPE, 26, 50, invalidReturnType("json|Holder")),
                expect(INVALID_RETURN_TYPE, 32, 50, invalidReturnType("http:Request")));
    }

    @Test
    public void testStreamReturnType() {
        assertDiagnostics("12_stream_return_type",
                expect(STREAM_RETURN_TYPE, 22, 50, streamReturnType("stream<string, error?>")),
                expect(STREAM_RETURN_TYPE, 28, 50, streamReturnType("json|stream<json>|error")));
    }

    @Test
    public void testInvalidBasePath() {
        assertDiagnostics("13_invalid_base_path",
                expect(INVALID_BASE_PATH, 19, 37, invalidBasePath("/agent")),
                expect(INVALID_BASE_PATH, 25, 37, invalidBasePath("\"agent\"")));
    }

    @Test
    public void testImportAlias() {
        assertDiagnostics("14_import_alias",
                expect(PING_PARAMETER_NOT_ALLOWED, 20, 32, pingParameterNotAllowed("ctx")),
                expect(UNSUPPORTED_PARAMETER, 22, 56, unsupportedParameter("extra")),
                expect(UNSUPPORTED_RESOURCE, 24, 23, unsupportedResource("get status")));
    }

    @Test
    public void testServiceClassAndObjectConstructor() {
        assertDiagnostics("15_service_class_and_object",
                expect(MISSING_INVOCATIONS_RESOURCE, 19, 15, missingInvocationsResource()),
                expect(MISSING_PING_RESOURCE, 19, 15, missingPingResource()),
                expect(UNSUPPORTED_PARAMETER, 28, 40, unsupportedParameter("extra")),
                expect(UNSUPPORTED_RESOURCE, 30, 23, unsupportedResource("get health")),
                expect(MISSING_INVOCATIONS_RESOURCE, 33, 45, missingInvocationsResource()));
    }

    @Test
    public void testUntypedServiceDeclaration() {
        assertDiagnostics("16_untyped_service_declaration",
                expect(MISSING_INVOCATIONS_RESOURCE, 22, 1, missingInvocationsResource()),
                expect(MISSING_PING_RESOURCE, 22, 1, missingPingResource()),
                expect(UNSUPPORTED_RESOURCE, 23, 23, unsupportedResource("get status")),
                expect(INVALID_BASE_PATH, 26, 9, invalidBasePath("/agents")),
                expect(UNSUPPORTED_PARAMETER, 29, 40, unsupportedParameter("request")),
                expect(STREAM_RETURN_TYPE, 29, 70, streamReturnType("stream<json>")),
                expect(REMOTE_FUNCTION_NOT_ALLOWED, 31, 21, remoteFunctionNotAllowed("call")));
    }

    @Test
    public void testNonAgentCoreServicesIgnored() {
        assertDiagnostics("17_non_agentcore_services_ignored");
    }

    @Test
    public void testRootModuleOnly() {
        assertDiagnostics("18_root_module_only");
    }

    @Test
    public void testCompilationErrors() {
        assertDiagnostics("19_compilation_errors", 2,
                expect(MISSING_PING_RESOURCE, 21, 9, missingPingResource()));
    }

    @Test
    public void testHttpListenerRejected() {
        assertDiagnostics("20_http_listener_rejected", 1);
    }

    @Test
    public void testUnbindablePayloadTypes() {
        assertDiagnostics("21_unbindable_payload_types",
                expect(UNBINDABLE_PAYLOAD_TYPE, 33, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 39, 54, unbindablePayloadType("payload", "table")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 45, 54, unbindablePayloadType("payload", "string:RegExp")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 51, 54, unbindablePayloadType("payload", "xml")));
    }

    @Test
    public void testPayloadTypeEdgeCases() {
        assertDiagnostics("22_payload_type_edge_cases",
                expect(UNBINDABLE_PAYLOAD_TYPE, 37, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 43, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 49, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 55, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 61, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 67, 54, unbindablePayloadType("payload", "table")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 73, 54, unbindablePayloadType("payload", "string:RegExp")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 80, 54, unbindablePayloadType("payload", "xml")),
                expect(UNSUPPORTED_PARAMETER, 105, 40, unsupportedParameter("ctx")));
    }

    @Test
    public void testUnbindablePayloadInClassesAndObjects() {
        assertDiagnostics("23_unbindable_in_classes_and_objects",
                expect(UNBINDABLE_PAYLOAD_TYPE, 29, 54, unbindablePayloadType("payload", "xml")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 35, 54, unbindablePayloadType("payload", "table")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 43, 58, unbindablePayloadType("payload", "string:RegExp")),
                expect(UNBINDABLE_PAYLOAD_TYPE, 52, 77, unbindablePayloadType("payload", "xml")));
    }

    @Test
    public void testUnbindablePayloadWithCompilationErrors() {
        assertDiagnostics("24_unbindable_with_compilation_errors", 1);
    }

    private static void assertDiagnostics(String packageName, ExpectedDiagnostic... expected) {
        assertDiagnostics(packageName, 0, expected);
    }

    private static void assertDiagnostics(String packageName, int otherErrorCount, ExpectedDiagnostic... expected) {
        DiagnosticResult result = compile(packageName);
        List<Diagnostic> otherErrors = result.errors().stream()
                .filter(diagnostic -> !isAgentCoreDiagnostic(diagnostic))
                .collect(Collectors.toList());
        Assert.assertEquals(otherErrors.size(), otherErrorCount, "Compilation errors: " + describe(otherErrors));

        List<Diagnostic> actual = result.diagnostics().stream()
                .filter(AgentCoreServiceValidationTest::isAgentCoreDiagnostic)
                .sorted(Comparator.comparingInt((Diagnostic diagnostic) -> start(diagnostic).line())
                        .thenComparingInt(diagnostic -> start(diagnostic).offset())
                        .thenComparing(diagnostic -> diagnostic.diagnosticInfo().code()))
                .collect(Collectors.toList());
        Assert.assertEquals(actual.size(), expected.length, "AgentCore diagnostics: " + describe(actual));
        for (int i = 0; i < expected.length; i++) {
            Diagnostic diagnostic = actual.get(i);
            ExpectedDiagnostic expectation = expected[i];
            String context = "diagnostic " + i + ": " + describe(List.of(diagnostic));
            Assert.assertEquals(diagnostic.diagnosticInfo().code(), expectation.code, context);
            Assert.assertEquals(diagnostic.diagnosticInfo().severity(), DiagnosticSeverity.ERROR, context);
            Assert.assertEquals(diagnostic.message(), expectation.message, context);
            // The compiler counts lines and columns from zero.
            Assert.assertEquals(start(diagnostic).line() + 1, expectation.line, context);
            Assert.assertEquals(start(diagnostic).offset() + 1, expectation.column, context);
        }
    }

    private static DiagnosticResult compile(String packageName) {
        Environment environment = EnvironmentBuilder.getBuilder().setBallerinaHome(DISTRIBUTION_PATH).build();
        Project project = ProjectLoader.load(RESOURCE_DIRECTORY.resolve(packageName),
                ProjectEnvironmentBuilder.getBuilder(environment)).project();
        // As `bal build` does: code generators and modifiers first, then the compilation with the code analyzers.
        project.currentPackage().runCodeGenAndModifyPlugins();
        return project.currentPackage().getCompilation().diagnosticResult();
    }

    private static boolean isAgentCoreDiagnostic(Diagnostic diagnostic) {
        return diagnostic.diagnosticInfo().code() != null
                && diagnostic.diagnosticInfo().code().startsWith(CODE_PREFIX);
    }

    private static LinePosition start(Diagnostic diagnostic) {
        return diagnostic.location().lineRange().startLine();
    }

    private static String describe(List<Diagnostic> diagnostics) {
        return diagnostics.stream()
                .map(diagnostic -> diagnostic.diagnosticInfo().code() + " " + diagnostic.location().lineRange()
                        + " " + diagnostic.message())
                .collect(Collectors.joining(System.lineSeparator(), System.lineSeparator(), ""));
    }

    private static ExpectedDiagnostic expect(String code, int line, int column, String message) {
        return new ExpectedDiagnostic(code, line, column, message);
    }

    private static String missingInvocationsResource() {
        return "an `agentcore:InvocationService` must declare a `resource function post invocations`, "
                + "which serves `POST /invocations`.";
    }

    private static String missingPingResource() {
        return "an `agentcore:InvocationService` must declare a `resource function get ping`, which serves "
                + "the `GET /ping` health check.";
    }

    private static String unsupportedResource(String resource) {
        return "the resource '" + resource + "' is not supported in an `agentcore:InvocationService`, "
                + "which serves only `get ping` and `post invocations`.";
    }

    private static String remoteFunctionNotAllowed(String function) {
        return "the remote function '" + function + "' is not allowed in an `agentcore:InvocationService`; "
                + "declare resource functions instead.";
    }

    private static String pingParameterNotAllowed(String parameter) {
        return "the parameter '" + parameter + "' of the resource 'get ping' is not supported: the resource must "
                + "declare no parameters.";
    }

    private static String invalidPingReturnType(String type) {
        return "the resource 'get ping' must return a subtype of `agentcore:PingStatus|error`, found '" + type + "'.";
    }

    private static String unsupportedParameter(String parameter) {
        return "the parameter '" + parameter + "' of the resource 'post invocations' is not supported. Declare only "
                + "an `@http:Payload` parameter and an `agentcore:Context` parameter.";
    }

    private static String duplicatePayloadParameter() {
        return "the resource 'post invocations' declares more than one `@http:Payload` parameter.";
    }

    private static String duplicateContextParameter() {
        return "the resource 'post invocations' declares more than one `agentcore:Context` parameter.";
    }

    private static String unbindablePayloadType(String parameter, String type) {
        return "the `@http:Payload` parameter '" + parameter + "' of the resource 'post invocations' accepts '" + type
                + "', which a JSON request body can't hold; use a JSON-compatible type, or `byte[]` for the raw bytes.";
    }

    private static String invalidReturnType(String type) {
        return "the resource 'post invocations' must return a subtype of "
                + "`anydata|http:Response|http:StatusCodeResponse|error`, found '" + type + "'.";
    }

    private static String streamReturnType(String type) {
        return "the resource 'post invocations' returns a stream ('" + type + "'), but streaming is not supported "
                + "yet; return the complete response instead.";
    }

    private static String invalidBasePath(String basePath) {
        return "an `agentcore:InvocationService` must be attached at the root base path, because AgentCore "
                + "calls `/ping` and `/invocations` at the root; remove the base path '" + basePath + "'.";
    }

    /**
     * A diagnostic a test expects: its code, its message and its one-based start position.
     */
    private static final class ExpectedDiagnostic {
        private final String code;
        private final int line;
        private final int column;
        private final String message;

        ExpectedDiagnostic(String code, int line, int column, String message) {
            this.code = code;
            this.line = line;
            this.column = column;
            this.message = message;
        }
    }
}
