package com.railway.booking.controller;

import com.railway.booking.service.TicketService;
import com.railway.common.api.ApiResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Public PNR status (task G3.4, group G3).
 *
 * GET /api/v1/tickets/{pnr}  -> ticket status and seats, but NO passenger names.
 * No login needed (SecurityConfig allows GET /api/v1/tickets/**).
 */
@RestController
@RequestMapping("/api/v1/tickets")
public class TicketController {

    private final TicketService ticketService;

    public TicketController(TicketService ticketService) {
        this.ticketService = ticketService;
    }

    @GetMapping("/{pnr}")
    public ApiResponse<Map<String, Object>> getTicket(@PathVariable String pnr) {
        return ApiResponse.ok(ticketService.getTicket(pnr));
    }
}
