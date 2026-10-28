package com.railway.ops.controller;

import com.railway.common.api.ApiResponse;
import com.railway.ops.service.OpsEventLogger;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** Reads the MongoDB ops_event_log (empty list when MongoDB is disabled). */
@RestController
@RequestMapping("/api/v1/admin/ops-events")
@PreAuthorize("hasRole('ADMIN')")
public class OpsEventController {

    private final OpsEventLogger eventLogger;

    public OpsEventController(OpsEventLogger eventLogger) {
        this.eventLogger = eventLogger;
    }

    @GetMapping
    public ApiResponse<List<Map<String, Object>>> events(@RequestParam(defaultValue = "50") int limit) {
        return ApiResponse.ok(eventLogger.latest(limit));
    }
}
