package com.railway.booking.controller;

import com.railway.booking.dto.BookingCreateRequest;
import com.railway.booking.service.BookingService;
import com.railway.common.api.ApiResponse;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * Booking endpoints for logged-in users (task G3.4, group G3).
 *
 * POST /api/v1/bookings          create a booking
 * GET  /api/v1/bookings/my       my bookings, newest first
 * GET  /api/v1/bookings/{id}     one booking (owner or ADMIN)
 *
 * The controller stays thin: validation of the body happens here (@Valid),
 * everything else is in BookingService.
 */
@RestController
@RequestMapping("/api/v1/bookings")
@PreAuthorize("isAuthenticated()")
public class BookingController {

    private final BookingService bookingService;

    public BookingController(BookingService bookingService) {
        this.bookingService = bookingService;
    }

    @PostMapping
    public ApiResponse<Map<String, Object>> createBooking(@Valid @RequestBody BookingCreateRequest request) {
        return ApiResponse.ok(bookingService.createBooking(request));
    }

    @GetMapping("/my")
    public ApiResponse<List<Map<String, Object>>> getMyBookings() {
        return ApiResponse.ok(bookingService.getMyBookings());
    }

    @GetMapping("/{bookingId}")
    public ApiResponse<Map<String, Object>> getBooking(@PathVariable Long bookingId) {
        return ApiResponse.ok(bookingService.getBookingDetail(bookingId));
    }
}
