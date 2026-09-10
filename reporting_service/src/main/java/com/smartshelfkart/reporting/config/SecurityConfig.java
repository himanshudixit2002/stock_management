package com.smartshelfkart.reporting.config;

import com.smartshelfkart.reporting.security.FirebaseTokenFilter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpStatus;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Stateless bearer-token security.
 *
 * <p>No sessions, so no CSRF surface and nothing to fix with a token: every
 * request carries its own proof or is refused. {@code anyRequest().authenticated()}
 * is the default rather than a list of protected paths, because a route added
 * later should be closed until someone opens it deliberately — the opposite
 * default is how endpoints end up public by accident.
 */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    @Bean
    SecurityFilterChain filterChain(HttpSecurity http, FirebaseTokenFilter firebaseFilter)
            throws Exception {
        return http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        // Liveness and readiness only. The Prometheus endpoint is
                        // exposed separately and is not opened here.
                        .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                        .anyRequest().authenticated())
                .exceptionHandling(e -> e
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
                // Form login and basic auth are switched off rather than left
                // at their defaults; the only credential this service accepts
                // is a Firebase ID token.
                .httpBasic(basic -> basic.disable())
                .formLogin(form -> form.disable())
                .addFilterBefore(firebaseFilter, UsernamePasswordAuthenticationFilter.class)
                .build();
    }
}
