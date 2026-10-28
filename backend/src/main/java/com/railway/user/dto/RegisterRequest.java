package com.railway.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Body of POST /api/v1/auth/register.
 *
 * The e-mail pattern deliberately tolerates leading/trailing spaces because the
 * service trims and lower-cases the address before it is used (task rule).
 */
public record RegisterRequest(
        @NotBlank(message = "email is required")
        @Size(max = 120, message = "email must be at most 120 characters")
        @Pattern(regexp = "^\\s*[^@\\s]+@[^@\\s]+\\.[^@\\s]+\\s*$", message = "email format is invalid")
        String email,

        // BCrypt only uses the first 72 bytes, so longer passwords are rejected up front.
        @NotBlank(message = "password is required")
        @Size(min = 8, max = 72, message = "password must be 8 to 72 characters")
        String password,

        @NotBlank(message = "fullName is required")
        @Size(max = 80, message = "fullName must be at most 80 characters")
        String fullName,

        @NotBlank(message = "phone is required")
        @Pattern(regexp = "^[0-9]{10}$", message = "phone must be exactly 10 digits")
        String phone
) {
}
