package com.railway.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

/** Body of POST /api/v1/auth/verify-otp (second step of a LOGIN OTP sign-in). */
public record VerifyOtpRequest(
        @NotNull(message = "challengeId is required")
        Long challengeId,

        @NotBlank(message = "otp is required")
        String otp
) {
}
