package com.railway.common.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;

/**
 * Creates and checks JSON Web Tokens (HS256).
 * Claims: sub = userId, email, roles (role names WITHOUT the ROLE_ prefix).
 * The token lifetime comes from app.jwt.expiry-minutes, the signing secret from app.jwt.secret.
 */
@Component
public class JwtService {

    private final SecretKey key;
    private final long expiryMinutes;

    /**
     * Creates the service from configuration.
     *
     * @param secret        app.jwt.secret, at least 32 characters (256 bits) for HS256
     * @param expiryMinutes app.jwt.expiry-minutes
     */
    public JwtService(@Value("${app.jwt.secret}") String secret,
                      @Value("${app.jwt.expiry-minutes}") long expiryMinutes) {
        byte[] keyBytes = secret.getBytes(StandardCharsets.UTF_8);
        if (keyBytes.length < 32) {
            // Fail at start-up instead of issuing weak tokens.
            throw new IllegalStateException("app.jwt.secret must be at least 32 characters long");
        }
        this.key = Keys.hmacShaKeyFor(keyBytes);
        this.expiryMinutes = expiryMinutes;
    }

    /**
     * Issues a signed token.
     *
     * @param userId id of the logged-in user
     * @param email  e-mail of the user
     * @param roles  role names such as "PASSENGER" or "ADMIN" (no ROLE_ prefix)
     * @return the compact JWT string
     */
    public String generateToken(Long userId, String email, List<String> roles) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("email", email)
                .claim("roles", roles == null ? List.of() : roles)
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plus(expiryMinutes, ChronoUnit.MINUTES)))
                .signWith(key, Jwts.SIG.HS256)
                .compact();
    }

    /**
     * Verifies the signature and the expiry of a token and reads the user from it.
     *
     * @param token compact JWT string (without the "Bearer " prefix)
     * @return the user stored in the token
     * @throws JwtException             when the token is malformed, expired or has a bad signature
     * @throws IllegalArgumentException when the token text is null or empty
     */
    public AuthUser parse(String token) {
        Claims claims = Jwts.parser().verifyWith(key).build().parseSignedClaims(token).getPayload();

        Long userId;
        try {
            userId = Long.valueOf(claims.getSubject());
        } catch (NumberFormatException ex) {
            throw new JwtException("Token subject is not a numeric user id", ex);
        }

        List<String> roles = new ArrayList<>();
        Object rawRoles = claims.get("roles");
        if (rawRoles instanceof List<?> list) {
            for (Object role : list) {
                roles.add(String.valueOf(role));
            }
        }
        return new AuthUser(userId, claims.get("email", String.class), List.copyOf(roles));
    }
}
