package com.railway.booking.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Seat map of one class of one run (task G3.4, group G3).
 * Shows every physical seat of that class on the run's train and whether it is already taken.
 */
@Service
public class SeatMapService {

    private static final Set<String> CLASS_CODES = Set.of("SL", "3A", "2A", "1A", "CC");

    /**
     * All seats of the requested class on the train of the run.
     * "Occupied" is true when a seat_allocation row exists for this run and seat.
     * Coaches are ordered by Coach_ID (creation order: S1, S2, ... S10) so that S10 does not
     * come before S2 as it would with a text sort of Coach_Number.
     */
    private static final String SEAT_MAP_SQL =
            "SELECT s.Seat_ID, c.Coach_Number, s.Seat_No, s.Berth_Type,"
            + " EXISTS (SELECT 1 FROM seat_allocation sa"
            + "         WHERE sa.Run_ID = r.Run_ID AND sa.Seat_ID = s.Seat_ID) AS Occupied"
            + " FROM train_run r"
            + " JOIN train_coach c ON c.Train_ID = r.Train_ID"
            + " JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID"
            + " JOIN seat s ON s.Coach_ID = c.Coach_ID"
            + " WHERE r.Run_ID = ? AND ct.Class_Code = ?"
            + " ORDER BY c.Coach_ID, s.Seat_No";

    private final SqlHelper sql;

    public SeatMapService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /runs/{runId}/seat-map?classCode= */
    public List<Map<String, Object>> getSeatMap(Long runId, String classCode) {
        if (classCode == null || !CLASS_CODES.contains(classCode)) {
            throw ApiException.badRequest("VALIDATION_ERROR", "classCode must be one of SL, 3A, 2A, 1A, CC");
        }

        Long existingRun = sql.scalar("SELECT Run_ID FROM train_run WHERE Run_ID = ?", Long.class, runId);
        if (existingRun == null) {
            throw new ApiException("RUN_NOT_FOUND", "Run not found: " + runId, HttpStatus.NOT_FOUND);
        }

        // MySQL returns EXISTS as 0 / 1; convert it to a real boolean for the JSON response.
        List<Map<String, Object>> seats = new ArrayList<>();
        for (Map<String, Object> row : sql.query(SEAT_MAP_SQL, runId, classCode)) {
            Map<String, Object> seat = new LinkedHashMap<>();
            seat.put("seatId", row.get("seatId"));
            seat.put("coachNumber", row.get("coachNumber"));
            seat.put("seatNo", row.get("seatNo"));
            seat.put("berthType", row.get("berthType"));
            seat.put("occupied", toBoolean(row.get("occupied")));
            seats.add(seat);
        }
        return seats;
    }

    private boolean toBoolean(Object value) {
        if (value instanceof Boolean flag) {
            return flag;
        }
        return value instanceof Number number && number.intValue() != 0;
    }
}
