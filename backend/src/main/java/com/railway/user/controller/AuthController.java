package com.railway.user.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.user.dto.LoginRequest;
import com.railway.user.dto.RegisterRequest;
import com.railway.user.dto.VerifyOtpRequest;
import com.railway.user.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Authentication endpoints. register, login and verify-otp are public (SecurityConfig);
 * payment-otp needs a logged-in user.
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    /** POST /api/v1/auth/register -> {userId} */
    @PostMapping("/register")
    public ApiResponse<Map<String, Object>> register(@Valid @RequestBody RegisterRequest request) {
        return ApiResponse.ok(authService.register(request));
    }

    /** POST /api/v1/auth/login -> {token|null, otpRequired, challengeId|null, devOtp|null, user|null} */
    @PostMapping("/login")
    public ApiResponse<Map<String, Object>> login(@Valid @RequestBody LoginRequest request,
                                                  HttpServletRequest httpRequest) {
        // The caller's IP address is stored in login_audit by sp_record_login_attempt.
        return ApiResponse.ok(authService.login(request, httpRequest.getRemoteAddr()));
    }

    /** POST /api/v1/auth/verify-otp -> {token, user} */
    @PostMapping("/verify-otp")
    public ApiResponse<Map<String, Object>> verifyOtp(@Valid @RequestBody VerifyOtpRequest request) {
        return ApiResponse.ok(authService.verifyLoginOtp(request));
    }

    /** POST /api/v1/auth/payment-otp -> {challengeId, expiresAt, devOtp|null}. Body is empty ({}). */
    @PostMapping("/payment-otp")
    @PreAuthorize("isAuthenticated()")
    public ApiResponse<Map<String, Object>> paymentOtp() {
        return ApiResponse.ok(authService.createPaymentOtp(SecurityUtil.currentUserId()));
    }
}
