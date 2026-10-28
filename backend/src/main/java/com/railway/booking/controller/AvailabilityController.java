package com.railway.booking.controller;

import com.railway.booking.service.AvailabilityService;
import com.railway.common.api.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Public seat availability (task G3.4, group G3).
 *
 * GET /api/v1/availability?runId=12  -> one row per class (AVL / RAC / WL text, counters)
 * No login needed (SecurityConfig allows GET /api/v1/availability/**).
 */
@RestController
@RequestMapping("/api/v1/availability")
public class AvailabilityController {

    private final AvailabilityService availabilityService;

    public AvailabilityController(AvailabilityService availabilityService) {
        this.availabilityService = availabilityService;
    }

    @GetMapping
    public ApiResponse<List<Map<String, Object>>> getAvailability(@RequestParam Long runId) {
        return ApiResponse.ok(availabilityService.getAvailability(runId));
    }
}
