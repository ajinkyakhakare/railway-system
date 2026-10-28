package com.railway.train.controller;

import com.railway.common.api.ApiResponse;
import com.railway.train.dto.RunGenerateRequest;
import com.railway.train.service.RunService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Train run endpoints (contract C9, group G1). A "run" is one train on one journey date.
 *   GET  /api/v1/trains/{id}/runs?from=&to=       public
 *   GET  /api/v1/runs/{runId}                      public
 *   POST /api/v1/admin/trains/{id}/runs/generate   ADMIN (calls a stored procedure)
 */
@RestController
@RequestMapping("/api/v1")
public class RunController {

    private final RunService runService;

    public RunController(RunService runService) {
        this.runService = runService;
    }

    @GetMapping("/trains/{id}/runs")
    public ApiResponse<List<Map<String, Object>>> listRuns(
            @PathVariable("id") Long id,
            @RequestParam(name = "from", required = false) String from,
            @RequestParam(name = "to", required = false) String to) {
        return ApiResponse.ok(runService.listRuns(id, from, to));
    }

    @GetMapping("/runs/{runId}")
    public ApiResponse<Map<String, Object>> getRun(@PathVariable("runId") Long runId) {
        return ApiResponse.ok(runService.getRun(runId));
    }

    @PostMapping("/admin/trains/{id}/runs/generate")
    @PreAuthorize("hasRole('ADMIN')")
    public ApiResponse<Map<String, Object>> generateRuns(@PathVariable("id") Long id,
                                                         @Valid @RequestBody RunGenerateRequest request) {
        return ApiResponse.ok(runService.generateRuns(id, request));
    }
}
