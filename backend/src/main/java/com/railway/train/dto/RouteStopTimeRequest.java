package com.railway.train.dto;

import java.time.LocalTime;

/**
 * Request body of PUT /api/v1/admin/route-stops/{id}.
 * Only the two times can be changed. Either value may be null (first stop has no arrival,
 * last stop has no departure). The change is recorded by trigger trg_route_stop_audit.
 */
public record RouteStopTimeRequest(
        LocalTime arrivalTime,
        LocalTime departureTime
) {
}
