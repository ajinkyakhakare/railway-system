package com.railway.payment.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.payment.service.FareService;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** GET /api/v1/fares/quote (any logged-in user). */
@RestController
@RequestMapping("/api/v1")
public class FareController {

    private final FareService fareService;

    public FareController(FareService fareService) {
        this.fareService = fareService;
    }

    /**
     * Example: /api/v1/fares/quote?runId=1&classCode=3A&fromStationId=2&toStationId=1&passengerIds=1,2
     *
     * Parameters are optional at the Spring level so that a missing one produces our own
     * VALIDATION_ERROR from the service instead of a generic framework error.
     */
    @GetMapping("/fares/quote")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> quote(
            @RequestParam(required = false) Long runId,
            @RequestParam(required = false) String classCode,
            @RequestParam(required = false) Long fromStationId,
            @RequestParam(required = false) Long toStationId,
            @RequestParam(required = false) String passengerIds) {
        Long userId = SecurityUtil.currentUserId();
        return ApiResponse.ok(
                fareService.quote(userId, runId, classCode, fromStationId, toStationId, passengerIds));
    }
}
