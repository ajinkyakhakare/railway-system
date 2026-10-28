package com.railway.user.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.user.dto.UserUpdateRequest;
import com.railway.user.service.UserService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Profile of the logged-in user. */
@RestController
@RequestMapping("/api/v1/users")
@PreAuthorize("isAuthenticated()")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    /** GET /api/v1/users/me -> {userId,email,fullName,phone,roles[]} */
    @GetMapping("/me")
    public ApiResponse<Map<String, Object>> me() {
        return ApiResponse.ok(userService.getProfile(SecurityUtil.currentUserId()));
    }

    /** PUT /api/v1/users/me {fullName,phone} -> same shape as GET */
    @PutMapping("/me")
    public ApiResponse<Map<String, Object>> updateMe(@Valid @RequestBody UserUpdateRequest request) {
        return ApiResponse.ok(userService.updateProfile(
                SecurityUtil.currentUserId(), request.fullName(), request.phone()));
    }
}
