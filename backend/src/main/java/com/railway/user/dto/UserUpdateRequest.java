package com.railway.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** Body of PUT /api/v1/users/me. E-mail and password cannot be changed here. */
public record UserUpdateRequest(
        @NotBlank(message = "fullName is required")
        @Size(max = 80, message = "fullName must be at most 80 characters")
        String fullName,

        @NotBlank(message = "phone is required")
        @Pattern(regexp = "^[0-9]{10}$", message = "phone must be exactly 10 digits")
        String phone
) {
}
