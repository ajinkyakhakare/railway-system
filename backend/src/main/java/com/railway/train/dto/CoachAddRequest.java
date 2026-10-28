package com.railway.train.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/**
 * Request body of POST /api/v1/admin/trains/{id}/coaches.
 * Asks stored procedure sp_add_coaches_generate_seats to add coachCount coaches of the given
 * coach type to the train (and to generate their seats).
 */
public record CoachAddRequest(

        @NotNull(message = "coachTypeId is required")
        Long coachTypeId,

        @NotNull(message = "coachCount is required")
        @Min(value = 1, message = "coachCount must be between 1 and 10")
        @Max(value = 10, message = "coachCount must be between 1 and 10")
        Integer coachCount
) {
}
