package com.railway.booking.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * Request body of POST /api/v1/admin/bookings/expire-unpaid (task G3.4, group G3).
 *
 * JSON example: {"minutes":15}
 * Every booking that is still PENDING_PAYMENT and older than this many minutes is expired.
 * The limit of 1440 minutes is one day.
 */
public record ExpireRequest(

        @NotNull(message = "minutes is required")
        @Min(value = 1, message = "minutes must be at least 1")
        @Max(value = 1440, message = "minutes must be at most 1440")
        Integer minutes
) {
}
