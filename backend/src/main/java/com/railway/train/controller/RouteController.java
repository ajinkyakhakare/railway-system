package com.railway.train.controller;

import com.railway.common.api.ApiResponse;
import com.railway.train.dto.RouteCreateRequest;
import com.railway.train.dto.RouteStopTimeRequest;
import com.railway.train.service.RouteService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Route endpoints (contract C9, group G1).
 *   GET /api/v1/routes                    public
 *   GET /api/v1/routes/{id}/stops         public
 *   POST /api/v1/admin/routes             ADMIN  (route + all its stops in one request)
 *   PUT /api/v1/admin/route-stops/{id}    ADMIN  (change arrival/departure time of one stop)
 */
@RestController
@RequestMapping("/api/v1")
public class RouteController {

    private final RouteService routeService;

    public RouteController(RouteService routeService) {
        this.routeService = routeService;
    }

    @GetMapping("/routes")
    public ApiResponse<List<Map<String, Object>>> listRoutes() {
        return ApiResponse.ok(routeService.listRoutes());
    }

    @GetMapping("/routes/{id}/stops")
    public ApiResponse<List<Map<String, Object>>> listStops(@PathVariable("id") Long id) {
        return ApiResponse.ok(routeService.listStops(id));
    }

    @PostMapping("/admin/routes")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> createRoute(@Valid @RequestBody RouteCreateRequest request) {
        return ApiResponse.ok(routeService.createRoute(request));
    }

    @PutMapping("/admin/route-stops/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> updateStopTimes(@PathVariable("id") Long id,
                                                            @Valid @RequestBody RouteStopTimeRequest request) {
        return ApiResponse.ok(routeService.updateStopTimes(id, request));
    }
}
