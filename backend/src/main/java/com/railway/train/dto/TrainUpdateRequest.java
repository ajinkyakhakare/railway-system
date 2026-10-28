package com.railway.train.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * Request body of PUT /api/v1/admin/trains/{id}.
 * The train number cannot be changed. runDays REPLACES all existing train_schedule rows.
 */
public record TrainUpdateRequest(

        @NotBlank(message = "trainName is required")
        @Size(max = 80, message = "trainName must be at most 80 characters")
        String trainName,

        @NotBlank(message = "trainType is required")
        @Pattern(regexp = "^(EXPRESS|SUPERFAST|RAJDHANI|SHATABDI|LOCAL)$",
                message = "trainType must be EXPRESS, SUPERFAST, RAJDHANI, SHATABDI or LOCAL")
        String trainType,

        @NotNull(message = "routeId is required")
        Long routeId,

        @NotNull(message = "isActive is required")
        Boolean isActive,

        @NotEmpty(message = "runDays must contain at least one weekday")
        List<@NotNull(message = "runDays must not contain null")
             @Min(value = 1, message = "runDays values must be between 1 and 7")
             @Max(value = 7, message = "runDays values must be between 1 and 7") Integer> runDays
) {
}
