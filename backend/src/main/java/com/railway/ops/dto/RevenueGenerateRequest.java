package com.railway.ops.dto;

import jakarta.validation.constraints.NotNull;
import java.time.LocalDate;

/** Body of POST /api/v1/admin/reports/revenue/generate. Date format: yyyy-MM-dd. */
public record RevenueGenerateRequest(
        @NotNull(message = "date is required")
        LocalDate date) {
}
