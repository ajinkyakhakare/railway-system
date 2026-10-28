package com.railway.payment.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Body of POST /api/v1/cancellations.
 *
 * reason is optional free text (column cancellation.Reason is VARCHAR(100)).
 */
public record CancelRequest(
        @NotNull(message = "bookingPassengerId is required")
        Long bookingPassengerId,

        @Size(max = 100, message = "reason must be at most 100 characters")
        String reason
) {
}
