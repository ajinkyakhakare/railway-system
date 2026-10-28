package com.railway.payment.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Body of POST /api/v1/payments/orders.
 *
 * otpChallengeId and otp are only mandatory when app.auth.require-payment-otp=true.
 * That rule depends on configuration, so it is checked in PaymentService and not
 * with annotations here.
 */
public record PaymentOrderRequest(
        @NotNull(message = "bookingId is required")
        Long bookingId,

        Long otpChallengeId,

        @Size(max = 10, message = "otp must be at most 10 characters")
        String otp
) {
}
