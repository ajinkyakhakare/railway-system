package com.railway.train.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.train.dto.CoachAddRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Business logic for coach types and the coaches of a train.
 *
 * IMPORTANT (rule R12): addCoaches() CALLs a stored procedure that manages its own
 * transaction, so neither this class nor that method may be @Transactional.
 */
@Service
public class CoachService {

    private final SqlHelper sql;

    public CoachService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /coach-types - the five classes (SL, 3A, 2A, 1A, CC) with seats per coach. */
    public List<Map<String, Object>> listCoachTypes() {
        return sql.query("SELECT Coach_Type_ID, Class_Code, Class_Name, Seats_Per_Coach "
                + "FROM coach_type ORDER BY Coach_Type_ID");
    }

    /** GET /trains/{id}/coaches - every coach of the train with its class and number of seats. */
    public List<Map<String, Object>> listCoaches(Long trainId) {
        if (sql.queryOne("SELECT Train_ID FROM train WHERE Train_ID = ?", trainId) == null) {
            throw ApiException.notFound("Train " + trainId + " not found");
        }
        // LEFT JOIN so that a coach without seats would still be listed (with Seat_Count 0).
        return sql.query(
                "SELECT c.Coach_ID, c.Coach_Number, ct.Class_Code, ct.Class_Name, "
                        + "COUNT(s.Seat_ID) AS Seat_Count "
                        + "FROM train_coach c "
                        + "JOIN coach_type ct ON ct.Coach_Type_ID = c.Coach_Type_ID "
                        + "LEFT JOIN seat s ON s.Coach_ID = c.Coach_ID "
                        + "WHERE c.Train_ID = ? "
                        + "GROUP BY c.Coach_ID, c.Coach_Number, ct.Coach_Type_ID, ct.Class_Code, ct.Class_Name "
                        + "ORDER BY ct.Coach_Type_ID, c.Coach_ID",
                trainId);
    }

    /**
     * POST /admin/trains/{id}/coaches - calls sp_add_coaches_generate_seats.
     * The procedure itself checks that the train and the coach type exist (error NOT_FOUND)
     * and returns one row: Coaches_Added, Seats_Added.
     */
    public Map<String, Object> addCoaches(Long trainId, CoachAddRequest req) {
        Map<String, Object> row = sql.call("CALL sp_add_coaches_generate_seats(?, ?, ?)",
                trainId, req.coachTypeId(), req.coachCount());
        if (row == null) {
            throw new ApiException("INTERNAL_ERROR", "Coach procedure returned no result",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("coachesAdded", row.get("coachesAdded"));
        result.put("seatsAdded", row.get("seatsAdded"));
        return result;
    }
}
