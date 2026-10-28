package com.railway.ops.controller;

import com.railway.common.api.ApiResponse;
import com.railway.ops.dto.RevenueGenerateRequest;
import com.railway.ops.service.ReportService;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/** Admin reports. Every endpoint requires the ADMIN role. */
@RestController
@RequestMapping("/api/v1/admin/reports")
@PreAuthorize("hasRole('ADMIN')")
public class ReportController {

    private final ReportService service;

    public ReportController(ReportService service) {
        this.service = service;
    }

    @GetMapping("/revenue")
    public ApiResponse<List<Map<String, Object>>> revenue(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return ApiResponse.ok(service.revenue(from, to));
    }

    @PostMapping("/revenue/generate")
    public ApiResponse<Map<String, Object>> generate(@Valid @RequestBody RevenueGenerateRequest request) {
        return ApiResponse.ok(service.generateRevenue(request.date()));
    }

    @GetMapping("/popular-routes")
    public ApiResponse<List<Map<String, Object>>> popularRoutes() {
        return ApiResponse.ok(service.popularRoutes());
    }

    @GetMapping("/delay-metrics")
    public ApiResponse<List<Map<String, Object>>> delayMetrics() {
        return ApiResponse.ok(service.delayMetrics());
    }

    @GetMapping("/delayed-trains")
    public ApiResponse<List<Map<String, Object>>> delayedTrains(
            @RequestParam(defaultValue = "15") int thresholdMinutes) {
        return ApiResponse.ok(service.delayedTrains(thresholdMinutes));
    }

    @GetMapping("/top-stations")
    public ApiResponse<List<Map<String, Object>>> topStations() {
        return ApiResponse.ok(service.topStations());
    }
}
