package com.railway.train.controller;

import com.railway.common.api.ApiResponse;
import com.railway.train.dto.StationRequest;
import com.railway.train.service.StationService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
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
 * Station endpoints (contract C9, group G1).
 *   GET    /api/v1/stations              public
 *   POST   /api/v1/admin/stations        ADMIN
 *   PUT    /api/v1/admin/stations/{id}   ADMIN
 *   DELETE /api/v1/admin/stations/{id}   ADMIN
 * The controller only receives the request and calls the service; SQL lives in StationService.
 */
@RestController
@RequestMapping("/api/v1")
public class StationController {

    private final StationService stationService;

    public StationController(StationService stationService) {
        this.stationService = stationService;
    }

    @GetMapping("/stations")
    public ApiResponse<List<Map<String, Object>>> listStations() {
        return ApiResponse.ok(stationService.listStations());
    }

    @PostMapping("/admin/stations")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> createStation(@Valid @RequestBody StationRequest request) {
        return ApiResponse.ok(stationService.createStation(request));
    }

    @PutMapping("/admin/stations/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> updateStation(@PathVariable("id") Long id,
                                                          @Valid @RequestBody StationRequest request) {
        return ApiResponse.ok(stationService.updateStation(id, request));
    }

    @DeleteMapping("/admin/stations/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> deleteStation(@PathVariable("id") Long id) {
        return ApiResponse.ok(stationService.deleteStation(id));
    }
}
