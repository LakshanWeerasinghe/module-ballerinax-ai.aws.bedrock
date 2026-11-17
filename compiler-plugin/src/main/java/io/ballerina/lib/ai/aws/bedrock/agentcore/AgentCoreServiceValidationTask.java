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

import io.ballerina.compiler.api.SemanticModel;
import io.ballerina.compiler.api.symbols.AnnotationSymbol;
import io.ballerina.compiler.api.symbols.IntersectionTypeSymbol;
import io.ballerina.compiler.api.symbols.ModuleSymbol;
import io.ballerina.compiler.api.symbols.ParameterSymbol;
import io.ballerina.compiler.api.symbols.ResourceMethodSymbol;
import io.ballerina.compiler.api.symbols.ServiceDeclarationSymbol;
import io.ballerina.compiler.api.symbols.Symbol;
import io.ballerina.compiler.api.symbols.TypeDefinitionSymbol;
import io.ballerina.compiler.api.symbols.TypeDescKind;
import io.ballerina.compiler.api.symbols.TypeReferenceTypeSymbol;
import io.ballerina.compiler.api.symbols.TypeSymbol;
import io.ballerina.compiler.api.symbols.UnionTypeSymbol;
import io.ballerina.compiler.syntax.tree.BasicLiteralNode;
import io.ballerina.compiler.syntax.tree.ClassDefinitionNode;
import io.ballerina.compiler.syntax.tree.DefaultableParameterNode;
import io.ballerina.compiler.syntax.tree.FunctionDefinitionNode;
import io.ballerina.compiler.syntax.tree.IncludedRecordParameterNode;
import io.ballerina.compiler.syntax.tree.Node;
import io.ballerina.compiler.syntax.tree.NodeList;
import io.ballerina.compiler.syntax.tree.ObjectConstructorExpressionNode;
import io.ballerina.compiler.syntax.tree.ParameterNode;
import io.ballerina.compiler.syntax.tree.RequiredParameterNode;
import io.ballerina.compiler.syntax.tree.RestParameterNode;
import io.ballerina.compiler.syntax.tree.ReturnTypeDescriptorNode;
import io.ballerina.compiler.syntax.tree.ServiceDeclarationNode;
import io.ballerina.compiler.syntax.tree.SyntaxKind;
import io.ballerina.compiler.syntax.tree.Token;
import io.ballerina.projects.plugins.AnalysisTask;
import io.ballerina.projects.plugins.SyntaxNodeAnalysisContext;
import io.ballerina.tools.diagnostics.Diagnostic;
import io.ballerina.tools.diagnostics.DiagnosticSeverity;
import io.ballerina.tools.diagnostics.Location;
import io.ballerina.tools.text.LineRange;
import io.ballerina.tools.text.TextRange;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;

import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.DUPLICATE_CONTEXT_PARAMETER;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.DUPLICATE_PAYLOAD_PARAMETER;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.INVALID_BASE_PATH;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.INVALID_PAYLOAD_TYPE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.INVALID_PING_RETURN_TYPE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.INVALID_RETURN_TYPE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.MISSING_INVOCATIONS_RESOURCE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.MISSING_PING_RESOURCE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.PING_PARAMETER_NOT_ALLOWED;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.REMOTE_FUNCTION_NOT_ALLOWED;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.STREAM_RETURN_TYPE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.UNBINDABLE_PAYLOAD_TYPE;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.UNSUPPORTED_PARAMETER;
import static io.ballerina.lib.ai.aws.bedrock.agentcore.AgentCoreDiagnostic.UNSUPPORTED_RESOURCE;

/**
 * Validates an {@code agentcore:InvocationService} against what the listener's dispatcher can call.
 *
 * <ul>
 * <li>the service declares {@code get ping} and {@code post invocations}, and no other resource or remote
 * function;</li>
 * <li>{@code get ping} declares no parameters and returns a subtype of {@code agentcore:PingStatus|error};</li>
 * <li>{@code post invocations} declares at most one {@code @http:Payload} parameter (an {@code anydata} subtype that
 * is not, and has no direct union member that is, one of the {@link UnbindablePayloadType}s) and
 * at most one {@code agentcore:Context} parameter, in any order, and returns a subtype of
 * {@code anydata|http:Response|http:StatusCodeResponse|error}, never a stream;</li>
 * <li>a service declaration is attached at the root base path.</li>
 * </ul>
 * Only services whose type is a subtype of {@code agentcore:InvocationService} are validated, so users of the root
 * {@code ai.aws.bedrock} module are never affected. A service declaration without a type descriptor is validated
 * when it is attached to an {@code agentcore:Listener}. Adapted from {@code FoundryServiceValidationTask} in
 * {@code ballerina-platform/module-ballerinax-ai.azure} at {@code f4abc4e}.
 *
 * @since 1.1.0
 */
public class AgentCoreServiceValidationTask implements AnalysisTask<SyntaxNodeAnalysisContext> {

    private static final String BALLERINA_ORG = "ballerina";
    private static final String BALLERINAX_ORG = "ballerinax";
    private static final String AGENTCORE_MODULE = "ai.aws.bedrock.agentcore";
    private static final String HTTP_MODULE = "http";
    private static final String EMPTY_VERSION = "";
    private static final String SERVICE_TYPE = "InvocationService";
    private static final String CONTEXT_TYPE = "Context";
    private static final String LISTENER_TYPE = "Listener";
    private static final String PING_STATUS_TYPE = "PingStatus";
    private static final String HTTP_RESPONSE_TYPE = "Response";
    private static final String HTTP_STATUS_CODE_RESPONSE_TYPE = "StatusCodeResponse";
    private static final String PAYLOAD_ANNOTATION = "Payload";

    private static final String POST = "post";
    private static final String GET = "get";
    private static final String INVOCATIONS = "invocations";
    private static final String PING = "ping";

    @Override
    public void perform(SyntaxNodeAnalysisContext context) {
        SemanticModel semanticModel = context.semanticModel();
        Optional<TypeSymbol> serviceType = resolveType(semanticModel, BALLERINAX_ORG, AGENTCORE_MODULE, SERVICE_TYPE);
        if (serviceType.isEmpty()) {
            return;
        }
        Node node = context.node();
        switch (node.kind()) {
            case SERVICE_DECLARATION -> validateServiceDeclaration(context, semanticModel, serviceType.get(),
                    (ServiceDeclarationNode) node);
            case CLASS_DEFINITION -> validateServiceClass(context, semanticModel, serviceType.get(),
                    (ClassDefinitionNode) node);
            case OBJECT_CONSTRUCTOR -> validateObjectConstructor(context, semanticModel, serviceType.get(),
                    (ObjectConstructorExpressionNode) node);
            default -> {
            }
        }
    }

    private static void validateServiceDeclaration(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                                   TypeSymbol serviceType, ServiceDeclarationNode service) {
        if (!isAgentCoreServiceDeclaration(semanticModel, serviceType, service)
                || hasCompilationErrors(semanticModel, service)) {
            return;
        }
        validateBasePath(context, service.absoluteResourcePath());
        Location serviceLocation = service.typeDescriptor().map(Node::location)
                .orElseGet(() -> service.serviceKeyword().location());
        new ServiceValidator(context, semanticModel).validate(service.members(), serviceLocation);
    }

    // A declaration without a type descriptor takes its type from the listener's `attach`, so it is an AgentCore
    // service when it is attached to an `agentcore:Listener`.
    private static boolean isAgentCoreServiceDeclaration(SemanticModel semanticModel, TypeSymbol serviceType,
                                                         ServiceDeclarationNode service) {
        Optional<Symbol> symbol = semanticModel.symbol(service);
        ServiceDeclarationSymbol serviceSymbol = symbol.isPresent()
                && symbol.get() instanceof ServiceDeclarationSymbol declaration ? declaration : null;
        if (service.typeDescriptor().isPresent()) {
            Optional<TypeSymbol> declaredType = serviceSymbol != null ? serviceSymbol.typeDescriptor()
                    : semanticModel.typeOf(service.typeDescriptor().get());
            return declaredType.isPresent() && declaredType.get().subtypeOf(serviceType);
        }
        if (serviceSymbol != null && serviceSymbol.typeDescriptor().isPresent()
                && serviceSymbol.typeDescriptor().get().subtypeOf(serviceType)) {
            return true;
        }
        Optional<TypeSymbol> listenerType = resolveType(semanticModel, BALLERINAX_ORG, AGENTCORE_MODULE,
                LISTENER_TYPE);
        if (listenerType.isEmpty()) {
            return false;
        }
        List<TypeSymbol> listenerTypes = new ArrayList<>();
        for (Node expression : service.expressions()) {
            semanticModel.typeOf(expression).ifPresent(listenerTypes::add);
        }
        if (serviceSymbol != null) {
            listenerTypes.addAll(serviceSymbol.listenerTypes());
        }
        for (TypeSymbol type : listenerTypes) {
            // `new agentcore:Listener(...)` can be typed `agentcore:Listener|error`, so each member is checked.
            List<TypeSymbol> members = new ArrayList<>();
            collectMembers(type, members);
            for (TypeSymbol member : members) {
                if (member.subtypeOf(listenerType.get())) {
                    return true;
                }
            }
        }
        return false;
    }

    private static void validateServiceClass(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                             TypeSymbol serviceType, ClassDefinitionNode serviceClass) {
        if (!hasQualifier(serviceClass.classTypeQualifiers(), SyntaxKind.SERVICE_KEYWORD)) {
            return;
        }
        Optional<Symbol> symbol = semanticModel.symbol(serviceClass);
        if (symbol.isEmpty() || !(symbol.get() instanceof TypeSymbol classType)
                || !classType.subtypeOf(serviceType) || hasCompilationErrors(semanticModel, serviceClass)) {
            return;
        }
        new ServiceValidator(context, semanticModel).validate(serviceClass.members(),
                serviceClass.className().location());
    }

    private static void validateObjectConstructor(SyntaxNodeAnalysisContext context, SemanticModel semanticModel,
                                                  TypeSymbol serviceType,
                                                  ObjectConstructorExpressionNode constructor) {
        if (!hasQualifier(constructor.objectTypeQualifiers(), SyntaxKind.SERVICE_KEYWORD)) {
            return;
        }
        Optional<TypeSymbol> type = semanticModel.typeOf(constructor);
        if (type.isEmpty() || !type.get().subtypeOf(serviceType) || hasCompilationErrors(semanticModel, constructor)) {
            return;
        }
        Node first = constructor.objectTypeQualifiers().isEmpty() ? constructor.objectKeyword()
                : constructor.objectTypeQualifiers().get(0);
        Node last = constructor.typeReference().map(Node.class::cast).orElse(constructor.objectKeyword());
        new ServiceValidator(context, semanticModel).validate(constructor.members(), span(first, last));
    }

    // Matches `Listener.isRootBasePath`: none, `/`, or a string literal made only of `/`.
    private static void validateBasePath(SyntaxNodeAnalysisContext context, NodeList<Node> basePath) {
        if (basePath.isEmpty()) {
            return;
        }
        boolean isRoot;
        if (basePath.size() == 1 && basePath.get(0).kind() == SyntaxKind.STRING_LITERAL) {
            String text = ((BasicLiteralNode) basePath.get(0)).literalToken().text();
            String value = text.length() >= 2 ? text.substring(1, text.length() - 1) : text;
            isRoot = value.trim().matches("/*");
        } else {
            isRoot = true;
            for (Node segment : basePath) {
                if (segment.kind() != SyntaxKind.SLASH_TOKEN) {
                    isRoot = false;
                    break;
                }
            }
        }
        if (!isRoot) {
            Location location = span(basePath.get(0), basePath.get(basePath.size() - 1));
            context.reportDiagnostic(AgentCoreDiagnostic.createDiagnostic(INVALID_BASE_PATH, location,
                    sourceText(basePath)));
        }
    }

    /**
     * Validates the members of one AgentCore service.
     */
    private static final class ServiceValidator {
        private final SyntaxNodeAnalysisContext context;
        private final SemanticModel semanticModel;
        private final TypeSymbol anydataType;
        private final TypeSymbol errorType;
        private final Optional<TypeSymbol> httpResponseType;
        private final Optional<TypeSymbol> statusCodeResponseType;
        // `anydata|error|http:Response|http:StatusCodeResponse`.
        private final Optional<TypeSymbol> invocationsReturnType;
        // `agentcore:PingStatus|error`.
        private final Optional<TypeSymbol> pingReturnType;
        // An error elsewhere in the module can leave a type used here unresolved, so the rules that depend on types
        // are skipped until the module is clean. The structural rules still run.
        private final boolean checkTypes;

        ServiceValidator(SyntaxNodeAnalysisContext context, SemanticModel semanticModel) {
            this.context = context;
            this.semanticModel = semanticModel;
            this.checkTypes = !containsError(semanticModel.diagnostics());
            this.anydataType = semanticModel.types().ANYDATA;
            this.errorType = semanticModel.types().ERROR;
            this.httpResponseType = resolveType(semanticModel, BALLERINA_ORG, HTTP_MODULE, HTTP_RESPONSE_TYPE);
            this.statusCodeResponseType = resolveType(semanticModel, BALLERINA_ORG, HTTP_MODULE,
                    HTTP_STATUS_CODE_RESPONSE_TYPE);
            this.invocationsReturnType = httpResponseType.isPresent() && statusCodeResponseType.isPresent()
                    ? Optional.of(semanticModel.types().builder().UNION_TYPE.withMemberTypes(anydataType, errorType,
                    httpResponseType.get(), statusCodeResponseType.get()).build())
                    : Optional.empty();
            this.pingReturnType = resolveType(semanticModel, BALLERINAX_ORG, AGENTCORE_MODULE, PING_STATUS_TYPE)
                    .map(pingStatus -> semanticModel.types().builder().UNION_TYPE.withMemberTypes(pingStatus,
                            errorType).build());
        }

        void validate(NodeList<Node> members, Location serviceLocation) {
            boolean hasInvocations = false;
            boolean hasPing = false;
            for (Node member : members) {
                if (member.kind() == SyntaxKind.RESOURCE_ACCESSOR_DEFINITION) {
                    FunctionDefinitionNode resource = (FunctionDefinitionNode) member;
                    String accessor = resource.functionName().text().trim().toLowerCase(Locale.ROOT);
                    List<String> path = pathShape(resource.relativeResourcePath());
                    if (POST.equals(accessor) && path.equals(List.of(INVOCATIONS))) {
                        hasInvocations = true;
                        validateInvocations(resource);
                    } else if (GET.equals(accessor) && path.equals(List.of(PING))) {
                        hasPing = true;
                        validatePing(resource);
                    } else {
                        report(UNSUPPORTED_RESOURCE, resourceLocation(resource), resourceLabel(resource));
                    }
                } else if (member.kind() == SyntaxKind.OBJECT_METHOD_DEFINITION) {
                    FunctionDefinitionNode method = (FunctionDefinitionNode) member;
                    if (hasQualifier(method.qualifierList(), SyntaxKind.REMOTE_KEYWORD)) {
                        report(REMOTE_FUNCTION_NOT_ALLOWED, method.functionName().location(),
                                method.functionName().text().trim());
                    }
                }
            }
            if (!hasInvocations) {
                report(MISSING_INVOCATIONS_RESOURCE, serviceLocation);
            }
            if (!hasPing) {
                report(MISSING_PING_RESOURCE, serviceLocation);
            }
        }

        private void validatePing(FunctionDefinitionNode resource) {
            for (ParameterNode parameter : resource.functionSignature().parameters()) {
                report(PING_PARAMETER_NOT_ALLOWED, parameter.location(), parameterName(parameter));
            }
            Optional<ReturnTypeDescriptorNode> returnTypeNode = resource.functionSignature().returnTypeDesc();
            if (returnTypeNode.isEmpty()) {
                // No return type is `()`, which is not a status.
                report(INVALID_PING_RETURN_TYPE, resource.functionSignature().location(), "()");
                return;
            }
            Optional<TypeSymbol> returnType = resourceReturnType(resource);
            if (!checkTypes || returnType.isEmpty() || pingReturnType.isEmpty()) {
                return;
            }
            if (!returnType.get().subtypeOf(pingReturnType.get())) {
                Node typeNode = returnTypeNode.get().type();
                report(INVALID_PING_RETURN_TYPE, typeNode.location(), typeNode.toSourceCode().trim());
            }
        }

        private void validateInvocations(FunctionDefinitionNode resource) {
            boolean hasPayload = false;
            boolean hasContext = false;
            for (ParameterNode parameter : resource.functionSignature().parameters()) {
                String name = parameterName(parameter);
                if (parameter.kind() == SyntaxKind.REST_PARAM || parameter.kind() == SyntaxKind.INCLUDED_RECORD_PARAM) {
                    report(UNSUPPORTED_PARAMETER, parameter.location(), name);
                    continue;
                }
                Optional<Symbol> symbol = semanticModel.symbol(parameter);
                if (symbol.isEmpty() || !(symbol.get() instanceof ParameterSymbol parameterSymbol)) {
                    continue;
                }
                TypeSymbol type = parameterSymbol.typeDescriptor();
                if (hasPayloadAnnotation(parameterSymbol)) {
                    if (hasPayload) {
                        report(DUPLICATE_PAYLOAD_PARAMETER, parameter.location());
                    } else if (checkTypes) {
                        validatePayloadType(parameter, name, type);
                    }
                    hasPayload = true;
                } else if (isContext(type)) {
                    if (hasContext) {
                        report(DUPLICATE_CONTEXT_PARAMETER, parameter.location());
                    }
                    hasContext = true;
                } else {
                    report(UNSUPPORTED_PARAMETER, parameter.location(), name);
                }
            }
            validateInvocationsReturnType(resource);
        }

        private void validatePayloadType(ParameterNode parameter, String name, TypeSymbol type) {
            Node typeNode = parameterTypeNode(parameter);
            Location location = typeNode != null ? typeNode.location() : parameter.location();
            if (!type.subtypeOf(anydataType)) {
                String typeText = typeNode != null ? typeNode.toSourceCode().trim() : type.signature();
                report(INVALID_PAYLOAD_TYPE, location, name, typeText);
                return;
            }
            unbindable(type).ifPresent(unbindable -> report(UNBINDABLE_PAYLOAD_TYPE, location, name,
                    unbindable.typeName()));
        }

        private void validateInvocationsReturnType(FunctionDefinitionNode resource) {
            Optional<ReturnTypeDescriptorNode> returnTypeNode = resource.functionSignature().returnTypeDesc();
            Optional<TypeSymbol> returnType = resourceReturnType(resource);
            if (!checkTypes || returnTypeNode.isEmpty() || returnType.isEmpty()) {
                return;
            }
            List<TypeSymbol> members = new ArrayList<>();
            collectMembers(returnType.get(), members);
            boolean returnsStream = false;
            boolean allMembersSupported = true;
            for (TypeSymbol member : members) {
                if (resolve(member).typeKind() == TypeDescKind.STREAM) {
                    returnsStream = true;
                } else if (!isSupportedReturnMember(member)) {
                    allMembersSupported = false;
                }
            }
            // The whole type is checked first, so a type such as `readonly & (json|error)` is accepted.
            boolean supported = (invocationsReturnType.isPresent()
                    && returnType.get().subtypeOf(invocationsReturnType.get())) || allMembersSupported;
            Node typeNode = returnTypeNode.get().type();
            String signature = typeNode.toSourceCode().trim();
            if (returnsStream) {
                report(STREAM_RETURN_TYPE, typeNode.location(), resourceLabel(resource), signature);
            } else if (!supported) {
                report(INVALID_RETURN_TYPE, typeNode.location(), signature);
            }
        }

        private Optional<TypeSymbol> resourceReturnType(FunctionDefinitionNode resource) {
            Optional<Symbol> symbol = semanticModel.symbol(resource);
            if (symbol.isEmpty() || !(symbol.get() instanceof ResourceMethodSymbol method)) {
                return Optional.empty();
            }
            return method.typeDescriptor().returnTypeDescriptor();
        }

        private boolean isSupportedReturnMember(TypeSymbol member) {
            if (member.subtypeOf(anydataType) || member.subtypeOf(errorType)) {
                return true;
            }
            if (httpResponseType.isPresent() && member.subtypeOf(httpResponseType.get())) {
                return true;
            }
            return statusCodeResponseType.isPresent() && member.subtypeOf(statusCodeResponseType.get());
        }

        private void report(AgentCoreDiagnostic diagnostic, Location location, Object... args) {
            context.reportDiagnostic(AgentCoreDiagnostic.createDiagnostic(diagnostic, location, args));
        }
    }

    // The path shape as the runtime reports it: literal segments by name, `^` for a path parameter, `^^` for a rest
    // parameter. The root path `.` has no segments.
    private static List<String> pathShape(NodeList<Node> relativePath) {
        List<String> shape = new ArrayList<>();
        for (Node segment : relativePath) {
            switch (segment.kind()) {
                case IDENTIFIER_TOKEN -> {
                    String text = ((Token) segment).text().trim();
                    shape.add(text.startsWith("'") ? text.substring(1) : text);
                }
                case RESOURCE_PATH_SEGMENT_PARAM -> shape.add("^");
                case RESOURCE_PATH_REST_PARAM -> shape.add("^^");
                default -> {
                }
            }
        }
        return shape;
    }

    private static String resourceLabel(FunctionDefinitionNode resource) {
        String path = sourceText(resource.relativeResourcePath());
        return resource.functionName().text().trim() + (path.isEmpty() ? "" : " " + path);
    }

    private static Location resourceLocation(FunctionDefinitionNode resource) {
        NodeList<Node> path = resource.relativeResourcePath();
        return path.isEmpty() ? resource.functionName().location()
                : span(resource.functionName(), path.get(path.size() - 1));
    }

    private static String parameterName(ParameterNode parameter) {
        Optional<Token> name = switch (parameter.kind()) {
            case REQUIRED_PARAM -> ((RequiredParameterNode) parameter).paramName();
            case DEFAULTABLE_PARAM -> ((DefaultableParameterNode) parameter).paramName();
            case REST_PARAM -> ((RestParameterNode) parameter).paramName();
            case INCLUDED_RECORD_PARAM -> ((IncludedRecordParameterNode) parameter).paramName();
            default -> Optional.empty();
        };
        return name.map(token -> token.text().trim()).orElse(parameter.toSourceCode().trim());
    }

    private static Node parameterTypeNode(ParameterNode parameter) {
        return switch (parameter.kind()) {
            case REQUIRED_PARAM -> ((RequiredParameterNode) parameter).typeName();
            case DEFAULTABLE_PARAM -> ((DefaultableParameterNode) parameter).typeName();
            default -> null;
        };
    }

    private static boolean hasPayloadAnnotation(ParameterSymbol parameter) {
        for (AnnotationSymbol annotation : parameter.annotations()) {
            Optional<ModuleSymbol> module = annotation.getModule();
            if (module.isPresent() && BALLERINA_ORG.equals(module.get().id().orgName())
                    && HTTP_MODULE.equals(module.get().id().moduleName())
                    && annotation.getName().map(PAYLOAD_ANNOTATION::equals).orElse(false)) {
                return true;
            }
        }
        return false;
    }

    // `agentcore:Context` directly or through an alias. The runtime matches the record by name and module, so a
    // structurally equal record elsewhere, or a union such as `agentcore:Context?`, doesn't qualify.
    private static boolean isContext(TypeSymbol type) {
        TypeSymbol current = type;
        while (current instanceof TypeReferenceTypeSymbol reference) {
            Optional<ModuleSymbol> module = reference.getModule();
            if (module.isPresent() && BALLERINAX_ORG.equals(module.get().id().orgName())
                    && AGENTCORE_MODULE.equals(module.get().id().moduleName())
                    && CONTEXT_TYPE.equals(reference.definition().getName().orElse(null))) {
                return true;
            }
            current = reference.typeDescriptor();
        }
        return false;
    }

    private static TypeSymbol resolve(TypeSymbol type) {
        TypeSymbol current = type;
        while (current instanceof TypeReferenceTypeSymbol reference) {
            current = reference.typeDescriptor();
        }
        return current;
    }

    // The declared type and its direct union members, as the runtime checks them. `anydata` and `any` are not
    // expanded, so an open record stays valid.
    private static Optional<UnbindablePayloadType> unbindable(TypeSymbol type) {
        TypeSymbol effective = effective(type);
        if (effective instanceof UnionTypeSymbol union) {
            for (TypeSymbol member : union.memberTypeDescriptors()) {
                Optional<UnbindablePayloadType> found =
                        UnbindablePayloadType.ofCompilerKind(effective(member).typeKind().name());
                if (found.isPresent()) {
                    return found;
                }
            }
            return Optional.empty();
        }
        return UnbindablePayloadType.ofCompilerKind(effective.typeKind().name());
    }

    // The type behind aliases and intersections such as `readonly & xml`, as the runtime's implied type.
    private static TypeSymbol effective(TypeSymbol type) {
        TypeSymbol resolved = resolve(type);
        return resolved instanceof IntersectionTypeSymbol intersection
                ? resolve(intersection.effectiveTypeDescriptor()) : resolved;
    }

    private static void collectMembers(TypeSymbol type, List<TypeSymbol> members) {
        if (resolve(type) instanceof UnionTypeSymbol union) {
            for (TypeSymbol member : union.memberTypeDescriptors()) {
                collectMembers(member, members);
            }
            return;
        }
        members.add(type);
    }

    private static boolean hasQualifier(NodeList<Token> qualifiers, SyntaxKind kind) {
        for (Token qualifier : qualifiers) {
            if (qualifier.kind() == kind) {
                return true;
            }
        }
        return false;
    }

    // An error inside the service may leave its own symbols unresolved, and the compiler already reports it.
    private static boolean hasCompilationErrors(SemanticModel semanticModel, Node node) {
        return containsError(semanticModel.diagnostics(node.lineRange()));
    }

    private static boolean containsError(List<Diagnostic> diagnostics) {
        return diagnostics.stream()
                .anyMatch(diagnostic -> diagnostic.diagnosticInfo().severity() == DiagnosticSeverity.ERROR);
    }

    private static Optional<TypeSymbol> resolveType(SemanticModel semanticModel, String org, String module,
                                                    String name) {
        Optional<Symbol> symbol = semanticModel.types().getTypeByName(org, module, EMPTY_VERSION, name);
        if (symbol.isEmpty()) {
            return Optional.empty();
        }
        if (symbol.get() instanceof TypeDefinitionSymbol typeDefinition) {
            return Optional.of(typeDefinition.typeDescriptor());
        }
        if (symbol.get() instanceof TypeSymbol typeSymbol) {
            return Optional.of(typeSymbol);
        }
        return Optional.empty();
    }

    private static String sourceText(NodeList<Node> nodes) {
        StringBuilder text = new StringBuilder();
        for (Node node : nodes) {
            text.append(node.toSourceCode());
        }
        return text.toString().trim();
    }

    private static Location span(Node first, Node last) {
        LineRange firstRange = first.location().lineRange();
        LineRange lastRange = last.location().lineRange();
        int start = first.textRange().startOffset();
        int end = last.textRange().endOffset();
        return new SpanLocation(LineRange.from(firstRange.fileName(), firstRange.startLine(), lastRange.endLine()),
                TextRange.from(start, end - start));
    }

    private record SpanLocation(LineRange lineRange, TextRange textRange) implements Location {
    }
}
