package com.railway.user.dto;

import jakarta.validation.constraints.NotEmpty;

import java.util.List;

/** Body of PUT /api/v1/admin/users/{id}/roles, e.g. {"roles":["ADMIN"]}. At least one role is required. */
public record RolesRequest(
        @NotEmpty(message = "roles must contain at least one role")
        List<String> roles
) {
}
