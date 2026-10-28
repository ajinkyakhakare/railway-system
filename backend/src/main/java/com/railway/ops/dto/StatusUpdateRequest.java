package com.railway.ops.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/**
 * Body of PUT /api/v1/ops/status/{runId}.
 * The status value itself is checked in OpsStatusService so that a wrong value
 * produces the contract error code INVALID_STATUS.
 */
public record StatusUpdateRequest(
        @NotBlank(message = "status is required")
        String status,

        @NotNull(message = "delayMinutes is required")
        @Min(value = 0, message = "delayMinutes must be 0 or more")
        Integer delayMinutes,

        // Optional: station where the train currently is (may be null)
        Long currentStationId,

        @Size(max = 100, message = "reason must be at most 100 characters")
        String reason) {
}
