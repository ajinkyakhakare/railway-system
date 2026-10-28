package com.railway.common.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.railway.common.api.ApiResponse;
import com.railway.common.exception.ErrorCodes;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.List;

/**
 * Central security rules: stateless JWT authentication, role based access, CORS and JSON error answers.
 * Role checks on single endpoints are done with @PreAuthorize (enabled by @EnableMethodSecurity),
 * e.g. @PreAuthorize("hasAnyRole('OPERATOR','ADMIN')").
 */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final String allowedOrigin;

    /**
     * Creates the configuration.
     *
     * @param allowedOrigin app.cors.allowed-origin (the React dev server)
     */
    public SecurityConfig(@Value("${app.cors.allowed-origin}") String allowedOrigin) {
        this.allowedOrigin = allowedOrigin;
    }

    /**
     * Password hashing used by the user module (BCrypt, hash length 60).
     *
     * @return BCrypt encoder
     */
    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * CORS: the browser app on app.cors.allowed-origin may call /api/** with the Authorization header.
     * The bean name must stay "corsConfigurationSource" - Spring Security looks it up by that name.
     *
     * @return CORS rules for the API
     */
    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(List.of(allowedOrigin));
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("Authorization", "Content-Type", "Accept"));
        config.setMaxAge(3600L);
        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/api/**", config);
        return source;
    }

    /**
     * The security filter chain with the URL rules of contract C8.
     *
     * @param http         Spring Security builder
     * @param jwtService   used by the JWT filter
     * @param objectMapper writes the JSON error envelope for 401 / 403
     * @return the configured chain
     * @throws Exception when the configuration is invalid
     */
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http,
                                                   JwtService jwtService,
                                                   ObjectMapper objectMapper) throws Exception {
        http
                // A stateless API with bearer tokens (no cookies) does not need CSRF protection.
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers(HttpMethod.POST,
                                "/api/v1/auth/register",
                                "/api/v1/auth/login",
                                "/api/v1/auth/verify-otp").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/health").permitAll()
                        .requestMatchers(HttpMethod.GET,
                                "/api/v1/stations/**",
                                "/api/v1/routes/**",
                                "/api/v1/coach-types/**",
                                "/api/v1/trains/**",
                                "/api/v1/runs/**",
                                "/api/v1/availability/**",
                                "/api/v1/tickets/**",
                                "/api/v1/ops/**").permitAll()
                        .requestMatchers("/api/v1/admin/**").hasRole("ADMIN")
                        .anyRequest().authenticated())
                .exceptionHandling(handling -> handling
                        // not logged in (or bad token) -> 401
                        .authenticationEntryPoint((request, response, ex) -> writeError(objectMapper, response,
                                HttpStatus.UNAUTHORIZED, ErrorCodes.UNAUTHORIZED,
                                "Authentication is required. Please log in."))
                        // logged in but wrong role -> 403
                        .accessDeniedHandler((request, response, ex) -> writeError(objectMapper, response,
                                HttpStatus.FORBIDDEN, ErrorCodes.FORBIDDEN,
                                "You do not have permission to perform this action.")))
                .addFilterBefore(new JwtAuthFilter(jwtService), UsernamePasswordAuthenticationFilter.class);
        return http.build();
    }

    /** Writes the failure envelope as JSON directly to the response (used by the 401 / 403 handlers). */
    private static void writeError(ObjectMapper objectMapper, HttpServletResponse response,
                                   HttpStatus status, String code, String message) throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        objectMapper.writeValue(response.getWriter(), ApiResponse.fail(code, message));
    }
}
