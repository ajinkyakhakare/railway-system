package com.railway.payment.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.payment.dto.MockConfirmRequest;
import com.railway.payment.dto.PaymentOrderRequest;
import com.railway.payment.dto.PaymentVerifyRequest;
import com.railway.payment.service.PaymentService;
import jakarta.validation.Valid;
import java.util.List;
import java.util.Map;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Payment endpoints. Every one needs a logged-in user; ownership is checked in the service. */
@RestController
@RequestMapping("/api/v1")
public class PaymentController {

    private final PaymentService paymentService;

    public PaymentController(PaymentService paymentService) {
        this.paymentService = paymentService;
    }

    /** Step 1 of paying: create the payment (and the Razorpay order in RAZORPAY mode). */
    @PostMapping("/payments/orders")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> createOrder(@Valid @RequestBody PaymentOrderRequest request) {
        return ApiResponse.ok(paymentService.createOrder(SecurityUtil.currentUserId(), request));
    }

    /** Step 2 (RAZORPAY mode): verify the signature returned by the Razorpay checkout. */
    @PostMapping("/payments/verify")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> verify(@Valid @RequestBody PaymentVerifyRequest request) {
        return ApiResponse.ok(paymentService.verifyRazorpayPayment(SecurityUtil.currentUserId(), request));
    }

    /** Step 2 (MOCK mode): simulate the gateway result for demos and tests. */
    @PostMapping("/payments/mock-confirm")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> mockConfirm(@Valid @RequestBody MockConfirmRequest request) {
        return ApiResponse.ok(paymentService.mockConfirm(SecurityUtil.currentUserId(), request));
    }

    /** Payment history of the current user (view v_payment_history). */
    @GetMapping("/payments/my")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<List<Map<String, Object>>> myPayments() {
        return ApiResponse.ok(paymentService.myPayments(SecurityUtil.currentUserId()));
    }
}
