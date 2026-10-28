package com.railway.user.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * Body of POST /api/v1/auth/login.
 * No format checks on purpose: a malformed e-mail simply fails with INVALID_CREDENTIALS.
 */
public record LoginRequest(
        @NotBlank(message = "email is required")
        String email,

        @NotBlank(message = "password is required")
        String password
) {
}
