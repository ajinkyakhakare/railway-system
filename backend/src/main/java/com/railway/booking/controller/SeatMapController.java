package com.railway.booking.controller;

import com.railway.booking.service.SeatMapService;
import com.railway.common.api.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Public seat map (task G3.4, group G3).
 *
 * GET /api/v1/runs/{runId}/seat-map?classCode=3A
 *   -> [{seatId, coachNumber, seatNo, berthType, occupied}]
 * No login needed (SecurityConfig allows GET /api/v1/runs/**).
 */
@RestController
@RequestMapping("/api/v1/runs")
public class SeatMapController {

    private final SeatMapService seatMapService;

    public SeatMapController(SeatMapService seatMapService) {
        this.seatMapService = seatMapService;
    }

    @GetMapping("/{runId}/seat-map")
    public ApiResponse<List<Map<String, Object>>> getSeatMap(@PathVariable Long runId,
                                                             @RequestParam String classCode) {
        return ApiResponse.ok(seatMapService.getSeatMap(runId, classCode));
    }
}
