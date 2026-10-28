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
 * Request body of POST /api/v1/admin/trains.
 * runDays holds ISO weekday numbers (1 = Monday to 7 = Sunday) on which the train runs;
 * one train_schedule row is created for each of them.
 */
public record TrainCreateRequest(

        @NotBlank(message = "trainNo is required")
        @Pattern(regexp = "^[0-9]{5}$", message = "trainNo must be exactly 5 digits")
        String trainNo,

        @NotBlank(message = "trainName is required")
        @Size(max = 80, message = "trainName must be at most 80 characters")
        String trainName,

        @NotBlank(message = "trainType is required")
        @Pattern(regexp = "^(EXPRESS|SUPERFAST|RAJDHANI|SHATABDI|LOCAL)$",
                message = "trainType must be EXPRESS, SUPERFAST, RAJDHANI, SHATABDI or LOCAL")
        String trainType,

        @NotNull(message = "routeId is required")
        Long routeId,

        @NotEmpty(message = "runDays must contain at least one weekday")
        List<@NotNull(message = "runDays must not contain null")
             @Min(value = 1, message = "runDays values must be between 1 and 7")
             @Max(value = 7, message = "runDays values must be between 1 and 7") Integer> runDays
) {
}
