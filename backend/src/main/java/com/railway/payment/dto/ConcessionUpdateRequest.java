package com.railway.payment.dto;

import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/**
 * Body of PUT /api/v1/admin/concession-rules/{id}.
 *
 * concession_rule.Discount_Percent is DECIMAL(5,2) with CHECK (0..100).
 */
public record ConcessionUpdateRequest(
        @NotNull(message = "discountPercent is required")
        @DecimalMin(value = "0.00", message = "discountPercent must be between 0 and 100")
        @DecimalMax(value = "100.00", message = "discountPercent must be between 0 and 100")
        @Digits(integer = 3, fraction = 2, message = "discountPercent allows at most 2 decimals")
        BigDecimal discountPercent
) {
}
