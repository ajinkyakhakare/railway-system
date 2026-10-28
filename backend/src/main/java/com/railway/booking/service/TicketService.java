package com.railway.booking.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/**
 * Public PNR lookup (task G3.4, group G3).
 *
 * This endpoint needs no login, so it must never reveal personal data:
 * passenger names are NOT returned, passengers are only numbered 1..n.
 */
@Service
public class TicketService {

    /** A PNR is exactly 10 digits (fn_generate_pnr). Anything else cannot exist. */
    private static final Pattern PNR_PATTERN = Pattern.compile("^[0-9]{10}$");

    private static final String TICKET_HEADER_SQL =
            "SELECT b.Booking_ID, b.PNR, t.Train_No, t.Train_Name, r.Journey_Date, "
            + "fs.Station_Code AS From_Station_Code, ts.Station_Code AS To_Station_Code, "
            + "b.Class_Code, b.Booking_Status"
            + " FROM booking b"
            + " JOIN train_run r ON r.Run_ID = b.Run_ID"
            + " JOIN train t ON t.Train_ID = r.Train_ID"
            + " JOIN station fs ON fs.Station_ID = b.From_Station_ID"
            + " JOIN station ts ON ts.Station_ID = b.To_Station_ID"
            + " WHERE b.PNR = ?";

    /** Seat details per passenger. LEFT JOINs because RAC / WL passengers have no seat yet. */
    private static final String TICKET_PASSENGERS_SQL =
            "SELECT bp.Status, c.Coach_Number, s.Seat_No, s.Berth_Type"
            + " FROM booking_passenger bp"
            + " LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID"
            + " LEFT JOIN seat s ON s.Seat_ID = sa.Seat_ID"
            + " LEFT JOIN train_coach c ON c.Coach_ID = s.Coach_ID"
            + " WHERE bp.Booking_ID = ?"
            + " ORDER BY bp.Booking_Passenger_ID";

    private final SqlHelper sql;

    public TicketService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /tickets/{pnr} : ticket status without any passenger name. */
    public Map<String, Object> getTicket(String pnr) {
        if (pnr == null || !PNR_PATTERN.matcher(pnr).matches()) {
            throw pnrNotFound(pnr);
        }

        Map<String, Object> header = sql.queryOne(TICKET_HEADER_SQL, pnr);
        if (header == null) {
            throw pnrNotFound(pnr);
        }
        Long bookingId = ((Number) header.get("bookingId")).longValue();

        // Number the passengers 1..n in booking order (no names, no ids).
        List<Map<String, Object>> passengers = new ArrayList<>();
        int index = 1;
        for (Map<String, Object> row : sql.query(TICKET_PASSENGERS_SQL, bookingId)) {
            Map<String, Object> passenger = new LinkedHashMap<>();
            passenger.put("index", index++);
            passenger.put("status", row.get("status"));
            passenger.put("coachNumber", row.get("coachNumber"));
            passenger.put("seatNo", row.get("seatNo"));
            passenger.put("berthType", row.get("berthType"));
            passengers.add(passenger);
        }

        // Copy only the fields of contract C9 (the internal bookingId is not exposed).
        Map<String, Object> ticket = new LinkedHashMap<>();
        ticket.put("pnr", header.get("pnr"));
        ticket.put("trainNo", header.get("trainNo"));
        ticket.put("trainName", header.get("trainName"));
        ticket.put("journeyDate", header.get("journeyDate"));
        ticket.put("fromStationCode", header.get("fromStationCode"));
        ticket.put("toStationCode", header.get("toStationCode"));
        ticket.put("classCode", header.get("classCode"));
        ticket.put("bookingStatus", header.get("bookingStatus"));
        ticket.put("passengers", passengers);
        return ticket;
    }

    private ApiException pnrNotFound(String pnr) {
        return new ApiException("BOOKING_NOT_FOUND", "No booking found for PNR " + pnr, HttpStatus.NOT_FOUND);
    }
}
