package com.railway.payment.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.NotNull;
import java.math.BigDecimal;

/**
 * Body of PUT /api/v1/admin/fare-rules/{id}.
 *
 * The limits mirror the column definitions of fare_rule:
 *   Base_Fare_Per_Km DECIMAL(6,2) CHECK (> 0)   -> at most 4 integer digits
 *   Min_Fare         DECIMAL(8,2) CHECK (>= 0)  -> at most 6 integer digits
 */
public record FareRuleUpdateRequest(
        @NotNull(message = "baseFarePerKm is required")
        @DecimalMin(value = "0.00", inclusive = false, message = "baseFarePerKm must be greater than 0")
        @Digits(integer = 4, fraction = 2, message = "baseFarePerKm allows at most 4 digits and 2 decimals")
        BigDecimal baseFarePerKm,

        @NotNull(message = "minFare is required")
        @DecimalMin(value = "0.00", message = "minFare must not be negative")
        @Digits(integer = 6, fraction = 2, message = "minFare allows at most 6 digits and 2 decimals")
        BigDecimal minFare
) {
}
