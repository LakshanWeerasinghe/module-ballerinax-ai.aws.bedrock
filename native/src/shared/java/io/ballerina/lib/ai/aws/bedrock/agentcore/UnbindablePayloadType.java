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

import java.util.Optional;
import java.util.Set;

/**
 * The {@code @http:Payload} types the {@code post invocations} binder can never produce. It parses the body as JSON, or
 * hands a {@code byte[]} payload the raw bytes, and JSON has no value of these types.
 *
 * <p>This file is compiled into both the compiler plugin and the native library, so the plugin rejects exactly what the
 * runtime can't bind. Each side checks the declared type and its direct union members only: {@code anydata} and
 * {@code any} are not expanded, so an open record, whose rest field is {@code anydata}, stays valid. A record with an
 * explicit {@code xml} field still compiles and fails at runtime, as it does with {@code ballerina/http}.
 *
 * @since 1.1.0
 */
public enum UnbindablePayloadType {

    // The compiler's `TypeDescKind` names and the runtime's `TypeTags` values for each type. The plugin can't depend on
    // the runtime, so the tags are written out: `XML_TAG` 16, `XML_ELEMENT_TAG` 18, `XML_PI_TAG` 19,
    // `XML_COMMENT_TAG` 20, `XML_TEXT_TAG` 21, `TABLE_TAG` 17, `REG_EXP_TYPE_TAG` 54.
    XML("xml", Set.of("XML", "XML_ELEMENT", "XML_PROCESSING_INSTRUCTION", "XML_COMMENT", "XML_TEXT"),
            Set.of(16, 18, 19, 20, 21)),
    TABLE("table", Set.of("TABLE"), Set.of(17)),
    REGEXP("string:RegExp", Set.of("REGEXP"), Set.of(54));

    private final String typeName;
    private final Set<String> compilerKinds;
    private final Set<Integer> runtimeTags;

    UnbindablePayloadType(String typeName, Set<String> compilerKinds, Set<Integer> runtimeTags) {
        this.typeName = typeName;
        this.compilerKinds = compilerKinds;
        this.runtimeTags = runtimeTags;
    }

    /**
     * Returns the Ballerina name of the type, as diagnostics and errors show it.
     *
     * @return the type name
     */
    public String typeName() {
        return typeName;
    }

    /**
     * Finds the unbindable type for a compiler {@code TypeDescKind}.
     *
     * @param kindName the name of the {@code TypeDescKind}
     * @return the unbindable type, or empty when the kind can be bound
     */
    public static Optional<UnbindablePayloadType> ofCompilerKind(String kindName) {
        for (UnbindablePayloadType type : values()) {
            if (type.compilerKinds.contains(kindName)) {
                return Optional.of(type);
            }
        }
        return Optional.empty();
    }

    /**
     * Finds the unbindable type for a runtime type tag.
     *
     * @param tag the runtime type tag
     * @return the unbindable type, or empty when the tag can be bound
     */
    public static Optional<UnbindablePayloadType> ofRuntimeTag(int tag) {
        for (UnbindablePayloadType type : values()) {
            if (type.runtimeTags.contains(tag)) {
                return Optional.of(type);
            }
        }
        return Optional.empty();
    }
}
