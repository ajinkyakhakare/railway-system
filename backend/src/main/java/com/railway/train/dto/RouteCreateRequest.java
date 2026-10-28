package com.railway.train.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * Request body of POST /api/v1/admin/routes.
 * A route needs a name, a source station, a destination station and at least two stops
 * (the source stop and the destination stop). @Valid makes Spring validate every stop too.
 */
public record RouteCreateRequest(

        @NotBlank(message = "routeName is required")
        @Size(max = 100, message = "routeName must be at most 100 characters")
        String routeName,

        @NotNull(message = "sourceStationId is required")
        Long sourceStationId,

        @NotNull(message = "destStationId is required")
        Long destStationId,

        @NotNull(message = "stops is required")
        @Size(min = 2, message = "a route needs at least 2 stops")
        @Valid
        List<@NotNull(message = "stops must not contain null") @Valid RouteStopRequest> stops
) {
}
