package com.smartshelfkart.reporting.security;

import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseToken;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Establishes who is calling, from the same Firebase ID token the rest of the
 * platform issues.
 *
 * <p>The token proves identity. It does not prove workspace access, so the
 * {@code x-company-id} header is checked against a membership document before
 * anything is authenticated. That ordering matters: an earlier version of the
 * Python service trusted the header alone, which meant any signed-in user could
 * read any workspace by changing a string.
 *
 * <p>A request that fails any step is left unauthenticated rather than being
 * rejected here, and Spring Security's entry point turns that into a 401. The
 * filter's job is to establish a principal or decline to; refusing is the
 * chain's job.
 */
@Component
public class FirebaseTokenFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(FirebaseTokenFilter.class);

    public static final String COMPANY_HEADER = "x-company-id";

    private final TenantAccess tenantAccess;
    private final boolean offline;

    public FirebaseTokenFilter(
            TenantAccess tenantAccess,
            @Value("${reporting.offline-mode:false}") boolean offline) {
        this.tenantAccess = tenantAccess;
        this.offline = offline;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        // Health and metrics are handled by the security chain itself; running
        // token verification over a probe would make liveness depend on
        // Firebase being reachable.
        return path.startsWith("/actuator");
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        String companyId = request.getHeader(COMPANY_HEADER);
        String uid = resolveUid(request);

        if (uid != null && companyId != null && !companyId.isBlank()
                && tenantAccess.isMember(uid, companyId)) {

            Set<String> permissions = tenantAccess.permissionsFor(uid, companyId);
            CallerPrincipal principal = new CallerPrincipal(uid, companyId, permissions);

            // Grants are carried as authorities so a controller can require one
            // declaratively. A null permission set contributes none, which is
            // the fail-closed behaviour rather than an absence of opinion.
            List<SimpleGrantedAuthority> authorities = permissions == null
                    ? List.of()
                    : permissions.stream().map(SimpleGrantedAuthority::new).toList();

            UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(principal, null, authorities);
            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        try {
            chain.doFilter(request, response);
        } finally {
            SecurityContextHolder.clearContext();
        }
    }

    private String resolveUid(HttpServletRequest request) {
        if (offline) {
            // Local development and the test suite. Never reachable in a
            // deployed configuration, where offline-mode is false.
            return "offline-user";
        }
        String header = request.getHeader("Authorization");
        if (header == null || !header.regionMatches(true, 0, "Bearer ", 0, 7)) {
            return null;
        }
        String token = header.substring(7).trim();
        if (token.isEmpty()) {
            return null;
        }
        try {
            FirebaseToken decoded = FirebaseAuth.getInstance().verifyIdToken(token);
            return decoded.getUid();
        } catch (Exception e) {
            log.debug("token verification failed: {}", e.toString());
            return null;
        }
    }
}
