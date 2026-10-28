package com.railway.user.dto;

import jakarta.validation.constraints.NotNull;

/** Body of PUT /api/v1/admin/users/{id}/active, e.g. {"active":false}. */
public record ActiveRequest(
        @NotNull(message = "active is required")
        Boolean active
) {
}
