package com.railway.train.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

import java.time.LocalTime;

/**
 * One stop inside the "stops" array of POST /api/v1/admin/routes.
 * Maps to one row of table route_stop.
 *
 * Times are HH:mm:ss. The first stop of a route has no arrival time and the last stop has
 * no departure time, so both times are optional. dayOffset and distanceFromSourceKm are
 * optional too: when missing, the service uses 0 (the column default).
 */
public record RouteStopRequest(

        @NotNull(message = "stops[].stationId is required")
        Long stationId,

        @NotNull(message = "stops[].stopSeq is required")
        @Min(value = 1, message = "stops[].stopSeq must be at least 1")
        @Max(value = 32767, message = "stops[].stopSeq is too large")
        Integer stopSeq,

        LocalTime arrivalTime,

        LocalTime departureTime,

        @Min(value = 0, message = "stops[].dayOffset must be between 0 and 3")
        @Max(value = 3, message = "stops[].dayOffset must be between 0 and 3")
        Integer dayOffset,

        @Min(value = 0, message = "stops[].distanceFromSourceKm must not be negative")
        @Max(value = 32767, message = "stops[].distanceFromSourceKm is too large")
        Integer distanceFromSourceKm
) {
}
