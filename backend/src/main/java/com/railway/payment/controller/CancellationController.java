package com.railway.payment.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.payment.dto.CancelRequest;
import com.railway.payment.service.CancellationService;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** Ticket cancellation endpoints (any logged-in user, ownership checked in the service). */
@RestController
@RequestMapping("/api/v1")
public class CancellationController {

    private final CancellationService cancellationService;

    public CancellationController(CancellationService cancellationService) {
        this.cancellationService = cancellationService;
    }

    /** Shows how much would be refunded, without changing anything. */
    @GetMapping("/cancellations/preview")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> preview(@RequestParam(required = false) Long bookingPassengerId) {
        return ApiResponse.ok(cancellationService.preview(SecurityUtil.currentUserId(), bookingPassengerId));
    }

    /** Cancels one passenger's ticket (stored procedure sp_cancel_ticket). */
    @PostMapping("/cancellations")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> cancel(@Valid @RequestBody CancelRequest request) {
        return ApiResponse.ok(cancellationService.cancel(SecurityUtil.currentUserId(), request));
    }
}
