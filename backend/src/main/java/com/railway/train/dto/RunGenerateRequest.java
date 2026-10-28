package com.railway.train.dto;

import jakarta.validation.constraints.NotNull;

import java.time.LocalDate;

/**
 * Request body of POST /api/v1/admin/trains/{id}/runs/generate.
 * Dates are yyyy-MM-dd. The stored procedure sp_generate_train_runs checks that toDate is not
 * before fromDate and that the range is at most 60 days.
 */
public record RunGenerateRequest(

        @NotNull(message = "fromDate is required")
        LocalDate fromDate,

        @NotNull(message = "toDate is required")
        LocalDate toDate
) {
}
