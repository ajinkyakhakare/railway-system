package com.railway.booking.service;

import com.railway.booking.dto.BookingCreateRequest;
import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.common.security.SecurityUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.sql.SQLException;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * Booking logic of group G3 (task G3.4): create a booking, list my bookings, show one booking.
 *
 * SQL-first design: all booking rules live in the stored procedure sp_book_ticket.
 * This class only validates the request, calls the procedure and reads the result back.
 *
 * IMPORTANT (rule R12): no method here is @Transactional. sp_book_ticket starts and commits
 * its own transaction, so a Spring transaction around it would be wrong.
 */
@Service
public class BookingService {

    private static final Logger log = LoggerFactory.getLogger(BookingService.class);

    /** A single booking (one PNR) may carry at most 6 passengers. */
    private static final int MAX_PASSENGERS = 6;

    /** Pause before the single retry after a deadlock. */
    private static final long DEADLOCK_RETRY_DELAY_MS = 50;

    /** MySQL error number for "Deadlock found when trying to get lock". */
    private static final int MYSQL_DEADLOCK_ERROR_CODE = 1213;

    /** SQLSTATE used for serialization failures / deadlocks. */
    private static final String SQLSTATE_SERIALIZATION_FAILURE = "40001";

    // ---- SQL used for the booking list and the booking detail (shared parts) ----

    /** Columns of the booking list shape of contract C9. */
    private static final String SUMMARY_COLUMNS =
            "b.Booking_ID, b.PNR, t.Train_No, t.Train_Name, r.Journey_Date, "
            + "fs.Station_Code AS From_Station_Code, ts.Station_Code AS To_Station_Code, "
            + "b.Class_Code, b.Booking_Status, b.Total_Fare, b.Booked_At";

    /** Joins that turn a booking row into readable train and station data. */
    private static final String SUMMARY_FROM =
            " FROM booking b"
            + " JOIN train_run r ON r.Run_ID = b.Run_ID"
            + " JOIN train t ON t.Train_ID = r.Train_ID"
            + " JOIN station fs ON fs.Station_ID = b.From_Station_ID"
            + " JOIN station ts ON ts.Station_ID = b.To_Station_ID";

    /** GET /bookings/my : bookings of one user, newest first. */
    private static final String MY_BOOKINGS_SQL =
            "SELECT " + SUMMARY_COLUMNS + SUMMARY_FROM
            + " WHERE b.User_ID = ?"
            + " ORDER BY b.Booked_At DESC, b.Booking_ID DESC";

    /** GET /bookings/{id} : the list fields plus runId, fromStationId, toStationId. */
    private static final String BOOKING_DETAIL_SQL =
            "SELECT " + SUMMARY_COLUMNS + ", b.Run_ID, b.From_Station_ID, b.To_Station_ID"
            + SUMMARY_FROM
            + " WHERE b.Booking_ID = ?";

    /** Passengers shown right after POST /bookings (no seat information yet). */
    private static final String NEW_BOOKING_PASSENGERS_SQL =
            "SELECT bp.Booking_Passenger_ID, bp.Passenger_ID, p.Full_Name AS Passenger_Name, "
            + "bp.Status, bp.Base_Fare, bp.Concession_Type, bp.Fare_Amount"
            + " FROM booking_passenger bp"
            + " JOIN passenger p ON p.Passenger_ID = bp.Passenger_ID"
            + " WHERE bp.Booking_ID = ?"
            + " ORDER BY bp.Booking_Passenger_ID";

    /**
     * Passengers of GET /bookings/{id}. The seat is optional (only CNF passengers have one),
     * so seat_allocation, seat and train_coach are joined with LEFT JOIN.
     */
    private static final String BOOKING_PASSENGERS_WITH_SEAT_SQL =
            "SELECT bp.Booking_Passenger_ID, bp.Passenger_ID, p.Full_Name AS Passenger_Name, "
            + "bp.Status, c.Coach_Number, s.Seat_No, s.Berth_Type, "
            + "bp.Base_Fare, bp.Concession_Type, bp.Fare_Amount"
            + " FROM booking_passenger bp"
            + " JOIN passenger p ON p.Passenger_ID = bp.Passenger_ID"
            + " LEFT JOIN seat_allocation sa ON sa.Booking_Passenger_ID = bp.Booking_Passenger_ID"
            + " LEFT JOIN seat s ON s.Seat_ID = sa.Seat_ID"
            + " LEFT JOIN train_coach c ON c.Coach_ID = s.Coach_ID"
            + " WHERE bp.Booking_ID = ?"
            + " ORDER BY bp.Booking_Passenger_ID";

    private final SqlHelper sql;

    public BookingService(SqlHelper sql) {
        this.sql = sql;
    }

    // ------------------------------------------------------------------------------------
    // POST /bookings
    // ------------------------------------------------------------------------------------

    /**
     * Books tickets for the logged-in user by calling sp_book_ticket.
     * The procedure decides CNF / RAC / WL for every passenger and computes the fares.
     * Errors raised by the procedure (SEAT_UNAVAILABLE, RUN_DEPARTED, ...) travel up as
     * SQLExceptions and the GlobalExceptionHandler turns them into the C7 error codes.
     */
    public Map<String, Object> createBooking(BookingCreateRequest request) {
        validateRequest(request);

        Long userId = SecurityUtil.currentUserId();
        String passengerJson = toJsonArray(request.passengerIds());

        // The procedure owns the transaction; we only retry once if MySQL reports a deadlock.
        Map<String, Object> created = withDeadlockRetry(() -> sql.call(
                "CALL sp_book_ticket(?,?,?,?,?,?)",
                userId,
                request.runId(),
                request.classCode(),
                request.fromStationId(),
                request.toStationId(),
                passengerJson));

        if (created == null || created.get("bookingId") == null) {
            // Should never happen: the procedure always ends with one SELECT.
            throw new ApiException("INTERNAL_ERROR", "Booking could not be created",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
        Long bookingId = ((Number) created.get("bookingId")).longValue();

        // Build the C9 response: booking header from the procedure + passenger rows from the DB.
        Map<String, Object> response = new LinkedHashMap<>();
        response.put("bookingId", bookingId);
        response.put("pnr", created.get("pnr"));
        response.put("totalFare", created.get("totalFare"));
        response.put("passengers", sql.query(NEW_BOOKING_PASSENGERS_SQL, bookingId));
        return response;
    }

    // ------------------------------------------------------------------------------------
    // GET /bookings/my and GET /bookings/{bookingId}
    // ------------------------------------------------------------------------------------

    /** Bookings of the logged-in user, newest first. */
    public List<Map<String, Object>> getMyBookings() {
        return sql.query(MY_BOOKINGS_SQL, SecurityUtil.currentUserId());
    }

    /**
     * One booking with seat details. Only the owner or an ADMIN may read it (otherwise NOT_OWNER).
     */
    public Map<String, Object> getBookingDetail(Long bookingId) {
        // Step 1: who owns this booking? (cheap query, also tells us if it exists)
        Long ownerId = sql.scalar("SELECT User_ID FROM booking WHERE Booking_ID = ?", Long.class, bookingId);
        if (ownerId == null) {
            throw bookingNotFound(bookingId);
        }

        // Step 2: owner or ADMIN only.
        boolean isOwner = ownerId.equals(SecurityUtil.currentUserId());
        if (!isOwner && !SecurityUtil.hasRole("ADMIN")) {
            throw new ApiException("NOT_OWNER", "This booking belongs to another user", HttpStatus.FORBIDDEN);
        }

        // Step 3: load header and passengers.
        Map<String, Object> header = sql.queryOne(BOOKING_DETAIL_SQL, bookingId);
        if (header == null) {
            throw bookingNotFound(bookingId);
        }
        Map<String, Object> response = new LinkedHashMap<>(header);
        response.put("passengers", sql.query(BOOKING_PASSENGERS_WITH_SEAT_SQL, bookingId));
        return response;
    }

    // ------------------------------------------------------------------------------------
    // POST /admin/bookings/expire-unpaid (also used by BookingExpiryJob)
    // ------------------------------------------------------------------------------------

    /**
     * Expires unpaid bookings older than the given number of minutes.
     * The procedure cancels the passengers, frees the seats, promotes RAC/WL passengers
     * and marks the bookings EXPIRED. Returns how many bookings were expired.
     */
    public int expireUnpaidBookings(int minutes) {
        Map<String, Object> row = sql.call("CALL sp_expire_unpaid_bookings(?)", minutes);
        if (row == null || row.get("expiredCount") == null) {
            return 0;
        }
        return ((Number) row.get("expiredCount")).intValue();
    }

    // ------------------------------------------------------------------------------------
    // Private helpers
    // ------------------------------------------------------------------------------------

    /** Checks the rules that need more than one field. Shape rules are on the DTO. */
    private void validateRequest(BookingCreateRequest request) {
        if (request.fromStationId().equals(request.toStationId())) {
            throw ApiException.badRequest("VALIDATION_ERROR", "fromStationId and toStationId must be different");
        }
        List<Long> ids = request.passengerIds();
        if (ids.size() > MAX_PASSENGERS) {
            throw ApiException.badRequest("TOO_MANY_PASSENGERS",
                    "A booking can have at most " + MAX_PASSENGERS + " passengers");
        }
        if (new HashSet<>(ids).size() != ids.size()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "passengerIds must not contain duplicates");
        }
    }

    /** Turns [3, 4] into the text "[3,4]" which sp_book_ticket reads with JSON_TABLE. */
    private String toJsonArray(List<Long> ids) {
        return ids.stream()
                .map(String::valueOf)
                .collect(Collectors.joining(",", "[", "]"));
    }

    private ApiException bookingNotFound(Long bookingId) {
        return new ApiException("BOOKING_NOT_FOUND", "Booking not found: " + bookingId, HttpStatus.NOT_FOUND);
    }

    /**
     * Runs the action. If MySQL reports a deadlock, waits 50 ms and runs the action exactly once more.
     * A deadlock rolls the whole procedure transaction back, so repeating the call is safe.
     * Any other exception (including business errors) is rethrown unchanged.
     */
    private <T> T withDeadlockRetry(Supplier<T> action) {
        try {
            return action.get();
        } catch (RuntimeException ex) {
            if (!isDeadlock(ex)) {
                throw ex;
            }
            log.warn("Deadlock detected, retrying once after {} ms", DEADLOCK_RETRY_DELAY_MS);
            pause(DEADLOCK_RETRY_DELAY_MS);
            return action.get();
        }
    }

    /** True when somewhere in the cause chain there is a SQLException that means "deadlock". */
    private boolean isDeadlock(Throwable error) {
        Throwable current = error;
        int depth = 0; // safety limit so a broken cause chain can never loop forever
        while (current != null && depth < 20) {
            if (current instanceof SQLException sqlException
                    && (sqlException.getErrorCode() == MYSQL_DEADLOCK_ERROR_CODE
                        || SQLSTATE_SERIALIZATION_FAILURE.equals(sqlException.getSQLState()))) {
                return true;
            }
            current = current.getCause();
            depth++;
        }
        return false;
    }

    private void pause(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt(); // keep the interrupt flag for the caller
            throw new ApiException("INTERNAL_ERROR", "Booking was interrupted", HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }
}
