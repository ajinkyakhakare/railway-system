package com.railway.user.controller;

import com.railway.common.api.ApiResponse;
import com.railway.common.security.SecurityUtil;
import com.railway.user.dto.PassengerRequest;
import com.railway.user.service.PassengerService;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/** CRUD for the logged-in user's saved passengers (never anyone else's). */
@RestController
@RequestMapping("/api/v1/passengers")
@PreAuthorize("isAuthenticated()")
public class PassengerController {

    private final PassengerService passengerService;

    public PassengerController(PassengerService passengerService) {
        this.passengerService = passengerService;
    }

    /** GET /api/v1/passengers -> [{passengerId,fullName,dateOfBirth,gender,concessionType,ageCategory}] */
    @GetMapping
    public ApiResponse<List<Map<String, Object>>> list() {
        return ApiResponse.ok(passengerService.list(SecurityUtil.currentUserId()));
    }

    /** POST /api/v1/passengers -> passenger object */
    @PostMapping
    public ApiResponse<Map<String, Object>> create(@Valid @RequestBody PassengerRequest request) {
        return ApiResponse.ok(passengerService.create(SecurityUtil.currentUserId(), request));
    }

    /** PUT /api/v1/passengers/{id} -> passenger object */
    @PutMapping("/{id}")
    public ApiResponse<Map<String, Object>> update(@PathVariable("id") Long id,
                                                   @Valid @RequestBody PassengerRequest request) {
        return ApiResponse.ok(passengerService.update(SecurityUtil.currentUserId(), id, request));
    }

    /** DELETE /api/v1/passengers/{id} -> {deleted:true} */
    @DeleteMapping("/{id}")
    public ApiResponse<Map<String, Object>> delete(@PathVariable("id") Long id) {
        return ApiResponse.ok(passengerService.delete(SecurityUtil.currentUserId(), id));
    }
}
