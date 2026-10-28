package com.railway.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Past;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;

/**
 * Body of POST /api/v1/passengers and PUT /api/v1/passengers/{id}.
 * SENIOR and CHILD concessions are NOT accepted here: they are derived from the
 * date of birth by fn_effective_concession.
 */
public record PassengerRequest(
        @NotBlank(message = "fullName is required")
        @Size(max = 80, message = "fullName must be at most 80 characters")
        String fullName,

        @NotNull(message = "dateOfBirth is required")
        @Past(message = "dateOfBirth must be in the past")
        LocalDate dateOfBirth,

        @NotBlank(message = "gender is required")
        @Pattern(regexp = "^[MFO]$", message = "gender must be M, F or O")
        String gender,

        @NotBlank(message = "concessionType is required")
        @Pattern(regexp = "^(NONE|GOVT|SOLDIER)$", message = "concessionType must be NONE, GOVT or SOLDIER")
        String concessionType
) {
}
