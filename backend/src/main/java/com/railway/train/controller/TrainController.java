package com.railway.train.controller;

import com.railway.common.api.ApiResponse;
import com.railway.train.dto.CoachAddRequest;
import com.railway.train.dto.TrainCreateRequest;
import com.railway.train.dto.TrainUpdateRequest;
import com.railway.train.service.CoachService;
import com.railway.train.service.TrainService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Train endpoints (contract C9, group G1).
 *   GET  /api/v1/trains?q=                       public
 *   GET  /api/v1/trains/search                       public (from station, to station and date)
 *   GET  /api/v1/trains/{id}                     public
 *   GET  /api/v1/trains/{id}/timetable           public
 *   GET  /api/v1/trains/{id}/coaches             public
 *   POST /api/v1/admin/trains                    ADMIN
 *   PUT  /api/v1/admin/trains/{id}               ADMIN
 *   POST /api/v1/admin/trains/{id}/coaches       ADMIN (calls a stored procedure)
 *
 * "/trains/search" is a fixed text, so Spring picks it before "/trains/{id}".
 * Query parameters of the search are read as plain values and validated in TrainService,
 * so a missing or malformed value returns our VALIDATION_ERROR JSON (HTTP 400).
 */
@RestController
@RequestMapping("/api/v1")
public class TrainController {

    private final TrainService trainService;
    private final CoachService coachService;

    public TrainController(TrainService trainService, CoachService coachService) {
        this.trainService = trainService;
        this.coachService = coachService;
    }

    @GetMapping("/trains")
    public ApiResponse<List<Map<String, Object>>> listTrains(
            @RequestParam(name = "q", required = false) String q) {
        return ApiResponse.ok(trainService.listTrains(q));
    }

    @GetMapping("/trains/search")
    public ApiResponse<List<Map<String, Object>>> searchTrains(
            @RequestParam(name = "fromStationId", required = false) Long fromStationId,
            @RequestParam(name = "toStationId", required = false) Long toStationId,
            @RequestParam(name = "date", required = false) String date) {
        return ApiResponse.ok(trainService.searchTrains(fromStationId, toStationId, date));
    }

    @GetMapping("/trains/{id}")
    public ApiResponse<Map<String, Object>> getTrain(@PathVariable("id") Long id) {
        return ApiResponse.ok(trainService.getTrain(id));
    }

    @GetMapping("/trains/{id}/timetable")
    public ApiResponse<List<Map<String, Object>>> getTimetable(@PathVariable("id") Long id) {
        return ApiResponse.ok(trainService.getTimetable(id));
    }

    @GetMapping("/trains/{id}/coaches")
    public ApiResponse<List<Map<String, Object>>> listCoaches(@PathVariable("id") Long id) {
        return ApiResponse.ok(coachService.listCoaches(id));
    }

    @PostMapping("/admin/trains")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> createTrain(@Valid @RequestBody TrainCreateRequest request) {
        return ApiResponse.ok(trainService.createTrain(request));
    }

    @PutMapping("/admin/trains/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> updateTrain(@PathVariable("id") Long id,
                                                        @Valid @RequestBody TrainUpdateRequest request) {
        return ApiResponse.ok(trainService.updateTrain(id, request));
    }

    @PostMapping("/admin/trains/{id}/coaches")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> addCoaches(@PathVariable("id") Long id,
                                                       @Valid @RequestBody CoachAddRequest request) {
        return ApiResponse.ok(coachService.addCoaches(id, request));
    }
}
