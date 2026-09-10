package com.smartshelfkart.reporting.security;

import java.util.Set;

/**
 * Who is calling, and which workspace they proved access to.
 *
 * @param permissions the grant keys held, or {@code {"*"}} for an owner or
 *                    admin. An empty set is a member holding nothing; a
 *                    {@code null} set means the grants could not be read at
 *                    all, which is a third state and must fail closed.
 */
public record CallerPrincipal(String uid, String companyId, Set<String> permissions) {

    public boolean has(String permission) {
        if (permissions == null) {
            return false;
        }
        return permissions.contains("*") || permissions.contains(permission);
    }
}
