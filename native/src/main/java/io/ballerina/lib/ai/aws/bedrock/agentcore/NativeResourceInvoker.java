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

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.Runtime;
import io.ballerina.runtime.api.concurrent.StrandMetadata;
import io.ballerina.runtime.api.creators.ErrorCreator;
import io.ballerina.runtime.api.creators.ValueCreator;
import io.ballerina.runtime.api.types.ObjectType;
import io.ballerina.runtime.api.types.Parameter;
import io.ballerina.runtime.api.types.RecordType;
import io.ballerina.runtime.api.types.ResourceMethodType;
import io.ballerina.runtime.api.types.ServiceType;
import io.ballerina.runtime.api.types.Type;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.utils.TypeUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.observability.ObservabilityConstants;
import io.ballerina.runtime.observability.ObserveUtils;
import io.ballerina.runtime.observability.ObserverContext;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;

/**
 * Finds a resource of the user's {@code agentcore:Service} and calls it on behalf of the internal dispatcher.
 *
 * <p>A resource is found by its accessor and path ({@code get [ping]}, {@code post [invocations]}). Each parameter
 * must be either the {@code @http:Payload} parameter or the {@code agentcore:Context} parameter, each at most once
 * and in any order. A panic in the resource comes back as an error, so the request still gets a response.
 *
 * <p>Adapted from {@code NativeFoundryResourceInvoker} in {@code ballerina-platform/module-ballerinax-ai.azure} at
 * {@code f4abc4e}, without the path parameters and the Foundry span attributes.
 *
 * @since 1.1.0
 */
public final class NativeResourceInvoker {

    // The annotations of a resource parameter are stored on the resource under this prefix plus the parameter name.
    // This key format, the http annotation key below and the private `request` field of `http:Headers` are internals
    // of the runtime and the http module with no public API; `http_internals_test.bal` fails when any of them changes.
    private static final String PARAM_ANNOTATION_PREFIX = "$param$.";
    // An http annotation key is `ballerina/http:<major version>:<annotation name>`.
    private static final String HTTP_ANNOTATION_PREFIX = "ballerina/http:";
    private static final String PAYLOAD_ANNOTATION_SUFFIX = ":Payload";
    private static final String CONTEXT_TYPE = "Context";
    private static final String RESOURCE_SIGNATURE_TYPE = "ResourceSignature";
    private static final String PAYLOAD_TYPE_FIELD = "payloadType";
    private static final String HAS_CONTEXT_FIELD = "hasContext";
    private static final String HTTP_HEADERS_TYPE = "Headers";
    private static final BString HTTP_HEADERS_REQUEST_FIELD = StringUtils.fromString("request");
    private static final String ENTRYPOINT_FUNCTION_MODULE_TAG = "entrypoint.function.module";
    private static final String ENTRYPOINT_SERVICE_NAME_TAG = "entrypoint.service.name";
    private static final String ENTRYPOINT_FUNCTION_NAME_TAG = "entrypoint.function.name";
    private static final String ENTRYPOINT_RESOURCE_ACCESSOR_TAG = "entrypoint.resource.accessor";

    private NativeResourceInvoker() {
    }

    /**
     * Describes the user's resource with the given accessor and path.
     *
     * @param env        the Ballerina environment
     * @param dispatcher the dispatcher
     * @param accessor   the resource accessor
     * @param path       the resource path
     * @return a {@code ResourceSignature}; {@code null} (Ballerina nil) when there is no such resource; or an error
     *         when the resource declares a parameter the dispatcher can't supply or no service is linked
     */
    public static Object getResourceSignature(Environment env, BObject dispatcher, BString accessor, BArray path) {
        Module module = env.getCurrentModule();
        try {
            ResourceMethodType resource = findResource(userService(dispatcher), accessor.getValue(),
                    path.getStringArray());
            if (resource == null) {
                return null;
            }
            ResourceParams params = ResourceParams.of(resource, module);
            Map<String, Object> fields = new HashMap<>();
            fields.put(PAYLOAD_TYPE_FIELD, params.payloadIndex < 0 ? null
                    : ValueCreator.createTypedescValue(params.payloadType));
            fields.put(HAS_CONTEXT_FIELD, params.contextIndex >= 0);
            return ValueCreator.createRecordValue(module, RESOURCE_SIGNATURE_TYPE, fields);
        } catch (BError error) {
            return error;
        }
    }

    /**
     * Calls the user's resource with the given accessor and path. A resource that is not isolated, or belongs to a
     * service that is not isolated, runs under the runtime's global lock, as it would on an {@code http:Listener}.
     *
     * @param env        the Ballerina environment
     * @param dispatcher the dispatcher
     * @param accessor   the resource accessor
     * @param path       the resource path
     * @param payload    the bound payload; ignored when the resource declares no payload parameter
     * @param context    the {@code agentcore:Context}; ignored when the resource declares no context parameter
     * @return the resource's return value, or the error it returns or panics with, or an error when it can't be
     *         called
     */
    public static Object invokeResource(Environment env, BObject dispatcher, BString accessor, BArray path,
                                        Object payload, Object context) {
        Module module = env.getCurrentModule();
        Object[] args;
        BObject userService;
        ResourceMethodType resource;
        try {
            userService = userService(dispatcher);
            resource = findResource(userService, accessor.getValue(), path.getStringArray());
            if (resource == null) {
                return ErrorCreator.createError(StringUtils.fromString("the agentcore:Service declares no '"
                        + describe(accessor.getValue(), path.getStringArray()) + "' resource"));
            }
            args = ResourceParams.of(resource, module).arguments(payload, context);
        } catch (BError error) {
            return error;
        }
        String methodName = resource.getName();
        ObserverContext dispatcherContext = ObserveUtils.isObservabilityEnabled()
                ? ObserveUtils.getObserverContextOfCurrentFrame(env) : null;
        ObserverContext userContext = dispatcherContext == null ? null : newUserContext(env, dispatcherContext);
        ObjectType serviceType = (ObjectType) TypeUtils.getImpliedType(userService.getOriginalType());
        boolean concurrentSafe = serviceType.isIsolated() && resource.isIsolated();
        try {
            return env.yieldAndRun(() -> concurrentSafe
                    ? callOnCurrentStrand(env.getRuntime(), userService, methodName, args)
                    : callOnNonIsolatedStrand(env.getRuntime(), userService, methodName, args, userContext));
        } finally {
            if (userContext != null) {
                restoreDispatcherContext(env, dispatcherContext, userContext);
            }
        }
    }

    // An isolated resource of an isolated service needs no lock, so it runs on the dispatcher's own strand, which
    // http created as concurrent-safe because the dispatcher is isolated.
    private static Object callOnCurrentStrand(Runtime runtime, BObject userService, String methodName,
                                              Object[] args) {
        try {
            return runtime.callMethod(userService, methodName, null, args);
        } catch (BError error) {
            // A panic that escaped the dispatcher would leave the request without a response.
            return error;
        }
    }

    // Any other resource must hold the runtime's global lock while it runs, as it does on an http:Listener. The
    // dispatcher's strand is concurrent-safe and never takes the lock, and the runtime reuses the current thread's
    // strand whatever metadata it is given, so the resource is called from a new virtual thread: the runtime creates
    // a non-concurrent-safe strand there. The user context travels in the strand's properties, as http passes its
    // observer context.
    private static Object callOnNonIsolatedStrand(Runtime runtime, BObject userService, String methodName,
                                                  Object[] args, ObserverContext userContext) {
        Map<String, Object> properties = new HashMap<>();
        if (userContext != null) {
            properties.put(ObservabilityConstants.KEY_OBSERVER_CONTEXT, userContext);
        }
        StrandMetadata metadata = new StrandMetadata(false, properties);
        CompletableFuture<Object> result = new CompletableFuture<>();
        Thread.startVirtualThread(() -> {
            try {
                result.complete(runtime.callMethod(userService, methodName, metadata, args));
            } catch (BError error) {
                result.complete(error);
            } catch (Throwable throwable) {
                // Only the class is named: the message could quote anything.
                result.complete(ErrorCreator.createError(StringUtils.fromString(
                        "calling the agentcore:Service resource failed with " + throwable.getClass().getName())));
            }
        });
        try {
            return result.get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return ErrorCreator.createError(StringUtils.fromString(
                    "interrupted while waiting for the agentcore:Service resource"));
        } catch (ExecutionException e) {
            // Not reached: the future is only ever completed normally.
            return ErrorCreator.createError(StringUtils.fromString(
                    "waiting for the agentcore:Service resource failed"));
        }
    }

    /**
     * Creates the {@code http:Headers} object of a request, as the http module does for a resource parameter.
     *
     * @param request the {@code http:Request}
     * @return the {@code http:Headers} object backed by the request
     */
    public static BObject createHeaders(BObject request) {
        Module httpModule = TypeUtils.getType(request).getPackage();
        BObject headers = ValueCreator.createObjectValue(httpModule, HTTP_HEADERS_TYPE);
        headers.set(HTTP_HEADERS_REQUEST_FIELD, request);
        return headers;
    }

    /**
     * Names the type of an error without reading its message or detail, which may quote the request body.
     *
     * @param error the error
     * @return the name of the error's type
     */
    public static BString errorTypeName(BError error) {
        return StringUtils.fromString(TypeUtils.getType(error).getName());
    }

    private static BObject userService(BObject dispatcher) {
        Object userService = NativeServiceAdaptor.getUserService(dispatcher);
        if (userService instanceof BObject service) {
            return service;
        }
        throw ErrorCreator.createError(StringUtils.fromString("no agentcore:Service is linked with the dispatcher"));
    }

    private static ResourceMethodType findResource(BObject userService, String accessor, String[] path) {
        ServiceType serviceType = (ServiceType) TypeUtils.getReferredType(TypeUtils.getType(userService));
        for (ResourceMethodType method : serviceType.getResourceMethods()) {
            if (accessor.equalsIgnoreCase(method.getAccessor()) && Arrays.equals(path, method.getResourcePath())) {
                return method;
            }
        }
        return null;
    }

    private static String describe(String accessor, String[] path) {
        return accessor.toLowerCase(Locale.ROOT) + " " + String.join("/", path);
    }

    // The roles of a resource's parameters.
    private static final class ResourceParams {
        private final int parameterCount;
        private int payloadIndex = -1;
        private Type payloadType;
        private int contextIndex = -1;

        private ResourceParams(int parameterCount) {
            this.parameterCount = parameterCount;
        }

        static ResourceParams of(ResourceMethodType resource, Module agentCoreModule) {
            String resourceName = describe(resource.getAccessor(), resource.getResourcePath());
            Parameter[] parameters = resource.getParameters();
            ResourceParams params = new ResourceParams(parameters.length);
            for (int i = 0; i < parameters.length; i++) {
                Parameter parameter = parameters[i];
                if (hasPayloadAnnotation(resource, parameter.name)) {
                    if (params.payloadIndex >= 0) {
                        throw unsupported(resourceName, "it declares more than one '@http:Payload' parameter");
                    }
                    if (!parameter.type.isAnydata()) {
                        throw unsupported(resourceName, "the type of its '@http:Payload' parameter '" + parameter.name
                                + "' is not a subtype of 'anydata'");
                    }
                    params.payloadIndex = i;
                    params.payloadType = parameter.type;
                } else if (isContext(parameter.type, agentCoreModule)) {
                    if (params.contextIndex >= 0) {
                        throw unsupported(resourceName, "it declares more than one 'agentcore:Context' parameter");
                    }
                    params.contextIndex = i;
                } else {
                    throw unsupported(resourceName, "its parameter '" + parameter.name + "' is neither the "
                            + "'@http:Payload' parameter nor an 'agentcore:Context' parameter");
                }
            }
            return params;
        }

        Object[] arguments(Object payload, Object context) {
            Object[] args = new Object[parameterCount];
            if (payloadIndex >= 0) {
                args[payloadIndex] = payload;
            }
            if (contextIndex >= 0) {
                args[contextIndex] = context;
            }
            return args;
        }

        private static boolean hasPayloadAnnotation(ResourceMethodType resource, String paramName) {
            Object annotations = resource.getAnnotation(StringUtils.fromString(PARAM_ANNOTATION_PREFIX + paramName));
            if (!(annotations instanceof BMap<?, ?> annotationMap)) {
                return false;
            }
            for (Object key : annotationMap.getKeys()) {
                String name = key.toString();
                if (name.startsWith(HTTP_ANNOTATION_PREFIX) && name.endsWith(PAYLOAD_ANNOTATION_SUFFIX)) {
                    return true;
                }
            }
            return false;
        }

        private static boolean isContext(Type type, Module agentCoreModule) {
            Type referred = TypeUtils.getReferredType(type);
            if (!(referred instanceof RecordType recordType) || !CONTEXT_TYPE.equals(recordType.getName())) {
                return false;
            }
            Module module = recordType.getPackage();
            return module != null && agentCoreModule.getOrg().equals(module.getOrg())
                    && agentCoreModule.getName().equals(module.getName());
        }

        private static BError unsupported(String resourceName, String reason) {
            return ErrorCreator.createError(StringUtils.fromString("the '" + resourceName
                    + "' resource of the agentcore:Service is not supported: " + reason));
        }
    }

    // A trace takes its entrypoint from its first resource, which here is the internal dispatcher. The user's resource
    // is given a fresh, not yet started context so the runtime fills the entrypoint from it, while the parent link
    // keeps its span under the dispatcher's span. Copied from the Foundry invoker, which took it from ballerina/ai's
    // NativeHttpToChatServiceAdaptor.
    private static ObserverContext newUserContext(Environment env, ObserverContext dispatcherContext) {
        ObserverContext userContext = new ObserverContext();
        userContext.setParent(dispatcherContext);
        userContext.setSpan(dispatcherContext.getSpan());
        userContext.setServiceName(dispatcherContext.getServiceName());
        userContext.setEntrypointFunctionModule(dispatcherContext.getEntrypointFunctionModule());
        userContext.setEntrypointServiceName(dispatcherContext.getEntrypointServiceName());
        userContext.setEntrypointFunctionName(dispatcherContext.getEntrypointFunctionName());
        userContext.setEntrypointResourceAccessor(dispatcherContext.getEntrypointResourceAccessor());
        ObserveUtils.setObserverContextToCurrentFrame(env, userContext);
        return userContext;
    }

    // Puts the dispatcher's context back and gives it the entrypoint recorded by the user's resource, so the
    // dispatcher's span reports the user's service as well.
    private static void restoreDispatcherContext(Environment env, ObserverContext dispatcherContext,
                                                 ObserverContext userContext) {
        ObserveUtils.setObserverContextToCurrentFrame(env, dispatcherContext);
        if (!userContext.isStarted()) {
            return;
        }
        dispatcherContext.setEntrypointFunctionModule(userContext.getEntrypointFunctionModule());
        dispatcherContext.setEntrypointServiceName(userContext.getEntrypointServiceName());
        dispatcherContext.setEntrypointFunctionName(userContext.getEntrypointFunctionName());
        dispatcherContext.setEntrypointResourceAccessor(userContext.getEntrypointResourceAccessor());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_FUNCTION_MODULE_TAG, userContext.getEntrypointFunctionModule());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_SERVICE_NAME_TAG, userContext.getEntrypointServiceName());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_FUNCTION_NAME_TAG, userContext.getEntrypointFunctionName());
        addTagIfPresent(dispatcherContext, ENTRYPOINT_RESOURCE_ACCESSOR_TAG,
                userContext.getEntrypointResourceAccessor());
    }

    private static void addTagIfPresent(ObserverContext context, String key, String value) {
        if (value != null) {
            context.addTag(key, value);
        }
    }
}
