package com.railway.booking.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Read-only seat availability and occupancy reports (task G3.4, group G3).
 * Both queries simply read the G3 views, so the SQL stays the single source of truth.
 */
@Service
public class AvailabilityService {

    private final SqlHelper sql;

    public AvailabilityService(SqlHelper sql) {
        this.sql = sql;
    }

    /**
     * GET /availability?runId= : one row per class of the run (view v_seat_availability).
     * An empty result means the run does not exist (or has no seat inventory), so RUN_NOT_FOUND.
     */
    public List<Map<String, Object>> getAvailability(Long runId) {
        List<Map<String, Object>> rows = sql.query(
                "SELECT * FROM v_seat_availability WHERE Run_ID = ? ORDER BY Class_Code", runId);
        if (rows.isEmpty()) {
            throw new ApiException("RUN_NOT_FOUND", "Run not found: " + runId, HttpStatus.NOT_FOUND);
        }
        return rows;
    }

    /**
     * GET /admin/occupancy?date= : occupancy of every run on that journey date
     * (view v_run_occupancy, already ranked with RANK()).
     */
    public List<Map<String, Object>> getOccupancy(LocalDate journeyDate) {
        return sql.query(
                "SELECT * FROM v_run_occupancy WHERE Journey_Date = ? ORDER BY Occupancy_Rank, Run_ID",
                java.sql.Date.valueOf(journeyDate));
    }
}
