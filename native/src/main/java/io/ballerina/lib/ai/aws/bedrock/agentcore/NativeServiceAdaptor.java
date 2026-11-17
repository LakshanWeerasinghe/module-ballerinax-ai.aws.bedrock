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
import io.ballerina.runtime.api.values.BObject;

import java.util.IdentityHashMap;
import java.util.Map;

/**
 * Links an {@code agentcore:InvocationService} with the internal dispatcher services that {@code agentcore:Listener}
 * attaches to the {@code http:Listener} in its place.
 *
 * <p>Each dispatcher holds the user's service as native data, so the dispatcher stays {@code isolated}. The user's
 * service keeps one dispatcher per listener, so {@code detach} on one listener never touches another listener's
 * dispatcher. Adapted from {@code NativeFoundryServiceAdaptor} in {@code ballerina-platform/module-ballerinax-ai.azure}
 * at {@code f4abc4e}.
 *
 * @since 1.1.0
 */
public final class NativeServiceAdaptor {

    private static final String USER_SERVICE = "AI_AWS_BEDROCK_AGENTCORE_USER_SERVICE";
    private static final String DISPATCHERS = "AI_AWS_BEDROCK_AGENTCORE_DISPATCHERS";
    // Guards every dispatcher map. Attach and detach are rare, so one lock is enough.
    private static final Object DISPATCHERS_LOCK = new Object();

    private NativeServiceAdaptor() {
    }

    public static void setUserService(Environment env, BObject dispatcher, BObject userService) {
        NativeResourceInvoker.resolveResources(env.getCurrentModule(), dispatcher, userService);
        dispatcher.addNativeData(USER_SERVICE, userService);
    }

    /**
     * Returns the user's service linked with a dispatcher.
     *
     * @param dispatcher the dispatcher
     * @return the user's service, or {@code null} (Ballerina nil) when none is linked
     */
    public static Object getUserService(BObject dispatcher) {
        return dispatcher.getNativeData(USER_SERVICE);
    }

    public static void unlinkUserService(BObject dispatcher) {
        dispatcher.addNativeData(USER_SERVICE, null);
        NativeResourceInvoker.dropResolvedResources(dispatcher);
    }

    /**
     * Records the dispatcher a listener attached for the user's service, unless that listener already has one.
     *
     * @param userService the user's service
     * @param listener    the {@code agentcore:Listener}
     * @param dispatcher  the dispatcher
     * @return {@code true} when recorded, {@code false} when the listener already has a dispatcher for the service
     */
    public static boolean registerDispatcher(BObject userService, BObject listener, BObject dispatcher) {
        synchronized (DISPATCHERS_LOCK) {
            return dispatchersOf(userService, true).byListener.putIfAbsent(listener, dispatcher) == null;
        }
    }

    public static Object removeDispatcher(BObject userService, BObject listener) {
        synchronized (DISPATCHERS_LOCK) {
            Dispatchers dispatchers = dispatchersOf(userService, false);
            return dispatchers == null ? null : dispatchers.byListener.remove(listener);
        }
    }

    // Must be called while holding DISPATCHERS_LOCK.
    private static Dispatchers dispatchersOf(BObject userService, boolean create) {
        Object existing = userService.getNativeData(DISPATCHERS);
        if (existing instanceof Dispatchers dispatchers) {
            return dispatchers;
        }
        if (!create) {
            return null;
        }
        Dispatchers dispatchers = new Dispatchers();
        userService.addNativeData(DISPATCHERS, dispatchers);
        return dispatchers;
    }

    // Keyed by listener identity.
    private static final class Dispatchers {
        private final Map<BObject, BObject> byListener = new IdentityHashMap<>();
    }
}
