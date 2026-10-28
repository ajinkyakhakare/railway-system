package com.railway.user.controller;

import com.railway.common.api.ApiResponse;
import com.railway.user.dto.ActiveRequest;
import com.railway.user.dto.RolesRequest;
import com.railway.user.service.AdminUserService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** Admin-only user management (SecurityConfig also protects /api/v1/admin/**). */
@RestController
@RequestMapping("/api/v1/admin/users")
@PreAuthorize("hasRole('ADMIN')")
public class AdminUserController {

    private final AdminUserService adminUserService;

    public AdminUserController(AdminUserService adminUserService) {
        this.adminUserService = adminUserService;
    }

    /** GET /api/v1/admin/users = rows of view v_user_account */
    @GetMapping
    public ApiResponse<List<Map<String, Object>>> list() {
        return ApiResponse.ok(adminUserService.listUsers());
    }

    /** PUT /api/v1/admin/users/{id}/roles {roles:[..]} -> {userId, roles[]} */
    @PutMapping("/{id}/roles")
    public ApiResponse<Map<String, Object>> replaceRoles(@PathVariable("id") Long id,
                                                         @Valid @RequestBody RolesRequest request) {
        return ApiResponse.ok(adminUserService.replaceRoles(id, request.roles()));
    }

    /** PUT /api/v1/admin/users/{id}/active {active:boolean} -> {userId, active} */
    @PutMapping("/{id}/active")
    public ApiResponse<Map<String, Object>> setActive(@PathVariable("id") Long id,
                                                      @Valid @RequestBody ActiveRequest request) {
        return ApiResponse.ok(adminUserService.setActive(id, request.active()));
    }
}
