package com.railway.train.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * Request body of POST /api/v1/admin/stations and PUT /api/v1/admin/stations/{id}.
 * Maps to the columns of table station (Station_Code, Station_Name, City, State).
 */
public record StationRequest(

        @NotBlank(message = "stationCode is required")
        @Size(min = 1, max = 5, message = "stationCode must be 1 to 5 characters")
        String stationCode,

        @NotBlank(message = "stationName is required")
        @Size(max = 80, message = "stationName must be at most 80 characters")
        String stationName,

        @NotBlank(message = "city is required")
        @Size(max = 60, message = "city must be at most 60 characters")
        String city,

        @NotBlank(message = "state is required")
        @Size(max = 60, message = "state must be at most 60 characters")
        String state
) {
}
