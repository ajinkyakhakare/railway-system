package com.railway.ops.service;

import com.railway.common.db.SqlHelper;
import org.springframework.stereotype.Service;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.Map;

/** Six headline counters for the admin dashboard, each from a plain COUNT / SUM query. */
@Service
public class DashboardService {

    private final SqlHelper sql;

    public DashboardService(SqlHelper sql) {
        this.sql = sql;
    }

    public Map<String, Object> summary() {
        Map<String, Object> summary = new LinkedHashMap<>();

        summary.put("totalBookings",
                count("SELECT COUNT(*) FROM booking"));
        summary.put("confirmedBookings",
                count("SELECT COUNT(*) FROM booking WHERE Booking_Status = 'CONFIRMED'"));

        BigDecimal revenue = sql.scalar(
                "SELECT COALESCE(SUM(Amount), 0) FROM payment WHERE Payment_Status = 'SUCCESS'",
                BigDecimal.class);
        summary.put("totalRevenue", revenue != null ? revenue : BigDecimal.ZERO);

        summary.put("activeTrains",
                count("SELECT COUNT(*) FROM train WHERE Is_Active = 1"));
        summary.put("delayedRunsToday",
                count("SELECT COUNT(*) FROM train_run_status s JOIN train_run r ON r.Run_ID = s.Run_ID "
                    + "WHERE s.Status = 'DELAYED' AND r.Journey_Date = CURDATE()"));
        summary.put("cancellationsToday",
                count("SELECT COUNT(*) FROM cancellation WHERE DATE(Cancelled_At) = CURDATE()"));
        return summary;
    }

    /** Runs a COUNT query and never returns null. */
    private long count(String query) {
        Long value = sql.scalar(query, Long.class);
        return value != null ? value : 0L;
    }
}
