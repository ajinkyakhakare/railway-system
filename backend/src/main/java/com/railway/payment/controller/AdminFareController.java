package com.railway.payment.controller;

import com.railway.common.api.ApiResponse;
import com.railway.payment.dto.ConcessionUpdateRequest;
import com.railway.payment.dto.FareRuleUpdateRequest;
import com.railway.payment.service.AdminFareService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Admin endpoints for fares and concessions. SecurityConfig already protects /api/v1/admin/**;
 * @PreAuthorize repeats the rule at the method level (defence in depth).
 */
@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminFareController {

    private final AdminFareService adminFareService;

    public AdminFareController(AdminFareService adminFareService) {
        this.adminFareService = adminFareService;
    }

    @GetMapping("/fare-rules")
    public ApiResponse<List<Map<String, Object>>> listFareRules() {
        return ApiResponse.ok(adminFareService.listFareRules());
    }

    /** Changing a fare fires trg_fare_audit, which writes a row to fare_audit_log. */
    @PutMapping("/fare-rules/{id}")
    public ApiResponse<Map<String, Object>> updateFareRule(@PathVariable Long id,
                                                           @Valid @RequestBody FareRuleUpdateRequest request) {
        return ApiResponse.ok(adminFareService.updateFareRule(id, request));
    }

    @GetMapping("/concession-rules")
    public ApiResponse<List<Map<String, Object>>> listConcessionRules() {
        return ApiResponse.ok(adminFareService.listConcessionRules());
    }

    @PutMapping("/concession-rules/{id}")
    public ApiResponse<Map<String, Object>> updateConcessionRule(@PathVariable Long id,
                                                                 @Valid @RequestBody ConcessionUpdateRequest request) {
        return ApiResponse.ok(adminFareService.updateConcessionRule(id, request));
    }

    /** Fare change history, newest first. */
    @GetMapping("/fare-audit")
    public ApiResponse<List<Map<String, Object>>> fareAudit() {
        return ApiResponse.ok(adminFareService.listFareAudit());
    }
}
