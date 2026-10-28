package com.railway.booking.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;

import java.util.List;

/**
 * Request body of POST /api/v1/bookings (task G3.4, group G3).
 *
 * JSON example:
 * {"runId":12,"classCode":"3A","fromStationId":2,"toStationId":1,"passengerIds":[3,4]}
 *
 * Bean validation only checks the SHAPE of the request here. The rules that need
 * several fields together (from <> to, at most 6 passengers, no duplicates) are
 * checked in BookingService so that they can return the exact contract error codes.
 * The business rules (stations on the route, seats, ownership of passengers) are
 * enforced by the stored procedure sp_book_ticket.
 */
public record BookingCreateRequest(

        @NotNull(message = "runId is required")
        @Positive(message = "runId must be a positive number")
        Long runId,

        @NotBlank(message = "classCode is required")
        @Pattern(regexp = "SL|3A|2A|1A|CC", message = "classCode must be one of SL, 3A, 2A, 1A, CC")
        String classCode,

        @NotNull(message = "fromStationId is required")
        @Positive(message = "fromStationId must be a positive number")
        Long fromStationId,

        @NotNull(message = "toStationId is required")
        @Positive(message = "toStationId must be a positive number")
        Long toStationId,

        @NotEmpty(message = "passengerIds must contain at least one passenger id")
        List<@NotNull(message = "passengerIds must not contain null")
             @Positive(message = "passenger ids must be positive numbers") Long> passengerIds
) {
}
