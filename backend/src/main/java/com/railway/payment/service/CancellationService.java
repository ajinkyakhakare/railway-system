package com.railway.payment.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.payment.dto.CancelRequest;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * Cancellation and refund endpoints.
 *
 * preview(): read-only SELECT that repeats the refund maths of sp_cancel_ticket.
 * cancel():  CALLs sp_cancel_ticket, which does everything in ONE database transaction
 *            (cancellation row, status change, seat release, refund row, RAC/WL promotion).
 *
 * Rule R12: not @Transactional, because sp_cancel_ticket owns its transaction.
 */
@Service
public class CancellationService {

    private static final Logger log = LoggerFactory.getLogger(CancellationService.class);

    private static final BigDecimal HUNDRED = new BigDecimal("100");

    /**
     * Same hours calculation as the procedure: minutes from now until the train leaves the
     * passenger's boarding station, divided by 60, kept with 2 decimals (the procedure stores
     * it in a DECIMAL(8,2)). The refund percentage then comes from fn_refund_deduction_pct.
     */
    private static final String PREVIEW_SQL =
            "SELECT t.Booking_Passenger_ID, t.Status, t.Fare_Amount, t.User_ID, t.Booking_Status, "
          + "       t.Hours_Before, fn_refund_deduction_pct(t.Hours_Before) AS Deduction_Percent "
          + "FROM ( "
          + "  SELECT bp.Booking_Passenger_ID, bp.Status, bp.Fare_Amount, b.User_ID, b.Booking_Status, "
          + "         ROUND(TIMESTAMPDIFF(MINUTE, NOW(), fn_departure_datetime(b.Run_ID, b.From_Station_ID)) / 60, 2) "
          + "           AS Hours_Before "
          + "  FROM booking_passenger bp "
          + "  JOIN booking b ON b.Booking_ID = bp.Booking_ID "
          + "  WHERE bp.Booking_Passenger_ID = ? "
          + ") t";

    private final SqlHelper sql;

    public CancellationService(SqlHelper sql) {
        this.sql = sql;
    }

    // ------------------------------------------------- GET /cancellations/preview

    public Map<String, Object> preview(Long userId, Long bookingPassengerId) {
        if (bookingPassengerId == null) {
            throw ApiException.badRequest("VALIDATION_ERROR", "bookingPassengerId is required");
        }

        Map<String, Object> row = sql.queryOne(PREVIEW_SQL, bookingPassengerId);

        // Same checks, same order and same error codes as sp_cancel_ticket step (1).
        if (row == null) {
            throw new ApiException("BOOKING_NOT_FOUND", "Booking passenger not found", HttpStatus.NOT_FOUND);
        }
        if (toLong(row.get("userId")) != userId.longValue()) {
            throw new ApiException("NOT_OWNER", "This ticket belongs to another user", HttpStatus.FORBIDDEN);
        }
        if ("CANCELLED".equals(row.get("status"))) {
            throw ApiException.conflict("ALREADY_CANCELLED", "This ticket is already cancelled");
        }
        BigDecimal hours = toBigDecimal(row.get("hoursBefore"));
        if (hours == null || hours.signum() < 0) {
            throw ApiException.conflict("CANCEL_NOT_ALLOWED", "The train has already departed");
        }

        BigDecimal originalFare = toBigDecimal(row.get("fareAmount"));
        BigDecimal deductionPercent = toBigDecimal(row.get("deductionPercent"));

        BigDecimal estimatedRefund;
        if ("CONFIRMED".equals(row.get("bookingStatus"))) {
            // deduction = ROUND(original * pct / 100, 2); refund = original - deduction
            BigDecimal deduction = originalFare.multiply(deductionPercent)
                    .divide(HUNDRED, 2, RoundingMode.HALF_UP);
            estimatedRefund = originalFare.subtract(deduction);
        } else {
            // Booking was never paid: nothing to refund.
            estimatedRefund = BigDecimal.ZERO.setScale(2);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("bookingPassengerId", bookingPassengerId);
        result.put("fareAmount", originalFare);
        result.put("hoursBeforeDeparture", hours);
        result.put("deductionPercent", deductionPercent);
        result.put("estimatedRefund", estimatedRefund);
        return result;
    }

    // ---------------------------------------------------- POST /cancellations

    public Map<String, Object> cancel(Long userId, CancelRequest request) {
        Map<String, Object> row = sql.call("CALL sp_cancel_ticket(?,?)", userId, request.bookingPassengerId());
        if (row == null) {
            throw new ApiException("INTERNAL_ERROR", "sp_cancel_ticket returned no result",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("cancellationId", row.get("cancellationId"));
        result.put("originalFare", row.get("originalFare"));
        result.put("deductionPercent", row.get("deductionPercent"));
        result.put("refundAmount", row.get("refundAmount"));
        result.put("promotedCount", row.get("promotedCount"));

        saveReason(row.get("cancellationId"), request.reason());
        return result;
    }

    /**
     * sp_cancel_ticket has no parameter for the reason, so it is stored afterwards in
     * cancellation.Reason (a G4 table, so G4 may write it). A failure here must not turn a
     * completed cancellation into an error response, so it is only logged.
     */
    private void saveReason(Object cancellationId, String reason) {
        if (reason == null || reason.isBlank() || !(cancellationId instanceof Number id)) {
            return;
        }
        try {
            sql.update("UPDATE cancellation SET Reason = ? WHERE Cancellation_ID = ?",
                    reason.trim(), id.longValue());
        } catch (RuntimeException e) {
            log.warn("Cancellation {} was saved but its reason could not be stored: {}",
                    id, e.getMessage());
        }
    }

    // ------------------------------------------------------- GET /refunds/my

    public List<Map<String, Object>> myRefunds(Long userId) {
        return sql.query("SELECT * FROM v_refund_summary WHERE User_ID = ? "
                + "ORDER BY Cancelled_At DESC, Cancellation_ID DESC", userId);
    }

    // ---------------------------------------------------------------- helpers

    private static long toLong(Object value) {
        return (value instanceof Number n) ? n.longValue() : -1L;
    }

    private static BigDecimal toBigDecimal(Object value) {
        if (value == null) {
            return null;
        }
        return (value instanceof BigDecimal b) ? b : new BigDecimal(value.toString());
    }
}
