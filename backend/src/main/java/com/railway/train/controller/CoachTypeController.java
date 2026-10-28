package com.railway.train.controller;

import com.railway.common.api.ApiResponse;
import com.railway.train.service.CoachService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Coach type endpoint (contract C9, group G1).
 *   GET /api/v1/coach-types   public - the classes SL, 3A, 2A, 1A, CC with seats per coach
 */
@RestController
@RequestMapping("/api/v1")
public class CoachTypeController {

    private final CoachService coachService;

    public CoachTypeController(CoachService coachService) {
        this.coachService = coachService;
    }

    @GetMapping("/coach-types")
    public ApiResponse<List<Map<String, Object>>> listCoachTypes() {
        return ApiResponse.ok(coachService.listCoachTypes());
    }
}
