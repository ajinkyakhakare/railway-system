package com.railway.booking.controller;

import com.railway.booking.dto.ExpireRequest;
import com.railway.booking.service.AvailabilityService;
import com.railway.booking.service.BookingService;
import com.railway.common.api.ApiResponse;
import jakarta.validation.Valid;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * ADMIN-only booking endpoints (task G3.4, group G3).
 *
 * GET  /api/v1/admin/occupancy?date=2026-10-27   occupancy and rank of every run on that date
 * POST /api/v1/admin/bookings/expire-unpaid      expire unpaid bookings now, body {"minutes":15}
 */
@RestController
@RequestMapping("/api/v1/admin")
@PreAuthorize("hasRole('ADMIN')")
public class AdminBookingController {

    private final AvailabilityService availabilityService;
    private final BookingService bookingService;

    public AdminBookingController(AvailabilityService availabilityService, BookingService bookingService) {
        this.availabilityService = availabilityService;
        this.bookingService = bookingService;
    }

    @GetMapping("/occupancy")
    public ApiResponse<List<Map<String, Object>>> getOccupancy(
            @RequestParam("date") @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        return ApiResponse.ok(availabilityService.getOccupancy(date));
    }

    @PostMapping("/bookings/expire-unpaid")
    public ApiResponse<Map<String, Object>> expireUnpaid(@Valid @RequestBody ExpireRequest request) {
        int expiredCount = bookingService.expireUnpaidBookings(request.minutes());
        return ApiResponse.ok(Map.of("expiredCount", expiredCount));
    }
}
