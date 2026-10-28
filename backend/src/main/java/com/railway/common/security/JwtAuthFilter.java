package com.railway.common.security;

import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Reads "Authorization: Bearer &lt;token&gt;" and, when the token is valid, puts the user into the
 * SecurityContext with authorities ROLE_&lt;role&gt;. An invalid, expired or missing token simply leaves
 * the request unauthenticated; the security rules in SecurityConfig then decide (401 or public access).
 *
 * This class is deliberately NOT a Spring bean: SecurityConfig creates it with "new", which prevents
 * Spring Boot from registering it a second time as an ordinary servlet filter.
 */
public class JwtAuthFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(JwtAuthFilter.class);
    private static final String BEARER_PREFIX = "Bearer ";

    private final JwtService jwtService;

    /**
     * Creates the filter.
     *
     * @param jwtService used to verify tokens
     */
    public JwtAuthFilter(JwtService jwtService) {
        this.jwtService = jwtService;
    }

    /**
     * Authenticates the request from its bearer token (if any) and continues the filter chain.
     *
     * @param request  current request
     * @param response current response
     * @param chain    rest of the filter chain
     * @throws ServletException if a later filter fails
     * @throws IOException      if a later filter fails
     */
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith(BEARER_PREFIX)) {
            String token = header.substring(BEARER_PREFIX.length()).trim();
            try {
                AuthUser user = jwtService.parse(token);
                List<SimpleGrantedAuthority> authorities = user.roles().stream()
                        .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                        .toList();
                UsernamePasswordAuthenticationToken authentication =
                        new UsernamePasswordAuthenticationToken(user, null, authorities);
                authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } catch (JwtException | IllegalArgumentException ex) {
                // Bad token: stay unauthenticated. Only a short debug line, never the token itself.
                log.debug("Ignoring invalid JWT: {}", ex.getClass().getSimpleName());
            }
        }
        chain.doFilter(request, response);
    }
}
