package com.railway.payment.dto;

import jakarta.validation.constraints.NotNull;

/**
 * Body of POST /api/v1/payments/mock-confirm (MOCK mode only).
 *
 * success = true  simulates a successful payment,
 * success = false simulates a failed payment.
 * Boolean (object type) is used so that a missing field is detected by @NotNull.
 */
public record MockConfirmRequest(
        @NotNull(message = "paymentId is required")
        Long paymentId,

        @NotNull(message = "success is required")
        Boolean success
) {
}
