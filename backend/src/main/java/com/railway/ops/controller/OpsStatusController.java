package com.railway.ops.controller;

import com.railway.common.api.ApiResponse;
import com.railway.ops.dto.StatusUpdateRequest;
import com.railway.ops.service.OpsStatusService;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/** Live train status. GET endpoints are public; PUT needs OPERATOR or ADMIN. */
@RestController
@RequestMapping("/api/v1/ops/status")
public class OpsStatusController {

    private final OpsStatusService service;

    public OpsStatusController(OpsStatusService service) {
        this.service = service;
    }

    @GetMapping
    public ApiResponse<List<Map<String, Object>>> list(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return ApiResponse.ok(service.statusForDate(date));
    }

    @GetMapping("/{runId}")
    public ApiResponse<Map<String, Object>> one(@PathVariable Long runId) {
        return ApiResponse.ok(service.statusForRun(runId));
    }

    @PutMapping("/{runId}")
    @PreAuthorize("hasAnyRole('OPERATOR','ADMIN')")
    public ApiResponse<Map<String, Object>> update(@PathVariable Long runId,
                                                   @Valid @RequestBody StatusUpdateRequest request) {
        return ApiResponse.ok(service.updateStatus(runId, request));
    }
}
