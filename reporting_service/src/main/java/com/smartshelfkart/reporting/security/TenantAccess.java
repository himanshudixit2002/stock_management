package com.smartshelfkart.reporting.security;

import com.google.cloud.firestore.DocumentSnapshot;
import com.google.cloud.firestore.Firestore;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;

/**
 * Re-implements the platform's authorization model for this service.
 *
 * <p>The duplication is deliberate, and it is the same reason the Python
 * assistant carries its own copy. Both services read through the Firebase Admin
 * SDK, which bypasses the security rules completely, so whatever the rules
 * withhold has to be withheld again here or this service becomes a way to read
 * another workspace's revenue.
 *
 * <p>Two checks, in this order, matching the rules:
 *
 * <ol>
 *   <li><strong>Membership.</strong> The uid must have a document at
 *       {@code companies/{companyId}/members/{uid}}. A header naming a company
 *       proves nothing on its own.</li>
 *   <li><strong>Permission.</strong> Membership alone does not entitle someone
 *       to financial reports. Owner and admin short-circuit; otherwise the role
 *       document is resolved and per-user overrides applied on top.</li>
 * </ol>
 *
 * <p>Every failure path denies. If Firestore cannot be reached the grants are
 * unknown, and unknown is treated as none: a storage outage must not open the
 * ledger.
 */
@Component
public class TenantAccess {

    private static final Logger log = LoggerFactory.getLogger(TenantAccess.class);

    /**
     * Membership is cached far longer than grants, matching the Python service.
     * A stale membership delays someone's removal from a workspace, which is
     * bad but bounded. A stale permission keeps granting a capability that was
     * just revoked, which is the thing the revocation was for.
     */
    private static final long MEMBERSHIP_TTL_MILLIS = 300_000L;

    private static final long PERMISSION_TTL_MILLIS = 30_000L;

    private record Cached<T>(T value, long expiresAt) {
        boolean live() {
            return System.currentTimeMillis() < expiresAt;
        }
    }

    private final Map<String, Cached<Boolean>> memberships = new ConcurrentHashMap<>();
    private final Map<String, Cached<Set<String>>> grants = new ConcurrentHashMap<>();

    private final Firestore firestore;
    private final boolean offline;

    public TenantAccess(
            @Nullable Firestore firestore,
            @Value("${reporting.offline-mode:false}") boolean offline) {
        this.firestore = firestore;
        this.offline = offline;
    }

    public boolean isMember(String uid, String companyId) {
        if (offline) {
            return true;
        }
        if (firestore == null || uid == null || companyId == null || companyId.isBlank()) {
            return false;
        }
        String key = uid + " " + companyId;
        Cached<Boolean> hit = memberships.get(key);
        if (hit != null && hit.live()) {
            return hit.value();
        }
        boolean member;
        try {
            DocumentSnapshot doc = firestore
                    .collection("companies").document(companyId)
                    .collection("members").document(uid)
                    .get().get();
            member = doc.exists();
        } catch (Exception e) {
            // Deny, and do not cache the denial: a transient outage should not
            // lock a legitimate user out for the next five minutes.
            log.warn("membership lookup failed for company={}: {}", companyId, e.toString());
            return false;
        }
        memberships.put(
                key, new Cached<>(member, System.currentTimeMillis() + MEMBERSHIP_TTL_MILLIS));
        return member;
    }

    /**
     * The grants a caller holds, or {@code null} when they could not be read.
     *
     * <p>The null is load-bearing. "Holds nothing" and "we cannot tell what they
     * hold" are different states, and collapsing them into an empty set makes a
     * Firestore hiccup indistinguishable from a deliberate denial — which is
     * fine for refusing, and wrong for reporting why.
     */
    @Nullable
    public Set<String> permissionsFor(String uid, String companyId) {
        if (offline) {
            return Set.of("*");
        }
        if (firestore == null) {
            return null;
        }
        String key = uid + " " + companyId;
        Cached<Set<String>> hit = grants.get(key);
        if (hit != null && hit.live()) {
            return hit.value();
        }

        Set<String> resolved = new HashSet<>();
        try {
            DocumentSnapshot member = firestore
                    .collection("companies").document(companyId)
                    .collection("members").document(uid)
                    .get().get();
            if (!member.exists()) {
                return Collections.emptySet();
            }

            String role = asString(member.get("role"));
            if ("owner".equalsIgnoreCase(role) || "admin".equalsIgnoreCase(role)) {
                resolved.add("*");
            } else {
                String roleId = asString(member.get("roleId"));
                if (roleId != null && !roleId.isBlank()) {
                    DocumentSnapshot roleDoc = firestore
                            .collection("companies").document(companyId)
                            .collection("roles").document(roleId)
                            .get().get();
                    if (roleDoc.exists()) {
                        addTrueKeys(resolved, roleDoc.get("permissions"));
                    }
                }
                // Per-user overrides live on the member document and win.
                addTrueKeys(resolved, member.get("permissions"));
            }
        } catch (Exception e) {
            log.warn("permission lookup failed for company={}: {}", companyId, e.toString());
            return null;
        }

        Set<String> frozen = Set.copyOf(resolved);
        grants.put(key, new Cached<>(frozen, System.currentTimeMillis() + PERMISSION_TTL_MILLIS));
        return frozen;
    }

    private static void addTrueKeys(Set<String> into, Object raw) {
        if (raw instanceof Map<?, ?> map) {
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (Boolean.TRUE.equals(entry.getValue())) {
                    into.add(String.valueOf(entry.getKey()));
                }
            }
        }
    }

    private static String asString(Object raw) {
        return raw == null ? null : String.valueOf(raw);
    }
}
