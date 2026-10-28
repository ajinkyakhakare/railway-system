package com.railway.payment.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.payment.service.CancellationService;
import java.util.List;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * GET /api/v1/refunds/my.
 * Refunds are created by sp_cancel_ticket, so the read side lives in CancellationService.
 */
@RestController
@RequestMapping("/api/v1")
public class RefundController {

    private final CancellationService cancellationService;

    public RefundController(CancellationService cancellationService) {
        this.cancellationService = cancellationService;
    }

    /** Refund history of the current user (view v_refund_summary). */
    @GetMapping("/refunds/my")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<List<Map<String, Object>>> myRefunds() {
        return ApiResponse.ok(cancellationService.myRefunds(SecurityUtil.currentUserId()));
    }
}
