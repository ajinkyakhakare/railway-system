package com.railway.train.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.train.dto.RunGenerateRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Business logic for train runs (table train_run: one row per train per journey date).
 *
 * IMPORTANT (rule R12): generateRuns() CALLs a stored procedure that manages its own
 * transaction, so neither this class nor that method may be @Transactional.
 */
@Service
public class RunService {

    private final SqlHelper sql;

    public RunService(SqlHelper sql) {
        this.sql = sql;
    }

    /**
     * GET /trains/{id}/runs - runs of a train, optionally limited by ?from=&to= (yyyy-MM-dd).
     * The SQL text is built from fixed pieces only; the dates travel as "?" parameters.
     */
    public List<Map<String, Object>> listRuns(Long trainId, String fromText, String toText) {
        if (sql.queryOne("SELECT Train_ID FROM train WHERE Train_ID = ?", trainId) == null) {
            throw ApiException.notFound("Train " + trainId + " not found");
        }
        LocalDate from = parseOptionalDate(fromText, "from");
        LocalDate to = parseOptionalDate(toText, "to");
        if (from != null && to != null && to.isBefore(from)) {
            throw ApiException.badRequest("VALIDATION_ERROR", "'to' must not be before 'from'");
        }

        StringBuilder query = new StringBuilder(
                "SELECT Run_ID, Journey_Date FROM train_run WHERE Train_ID = ?");
        List<Object> args = new ArrayList<>();
        args.add(trainId);
        if (from != null) {
            query.append(" AND Journey_Date >= ?");
            args.add(from);
        }
        if (to != null) {
            query.append(" AND Journey_Date <= ?");
            args.add(to);
        }
        query.append(" ORDER BY Journey_Date");
        return sql.query(query.toString(), args.toArray());
    }

    /** GET /runs/{runId} - one run with the train details. Throws RUN_NOT_FOUND (404). */
    public Map<String, Object> getRun(Long runId) {
        Map<String, Object> run = sql.queryOne(
                "SELECT r.Run_ID, r.Train_ID, t.Train_No, t.Train_Name, r.Journey_Date, t.Route_ID "
                        + "FROM train_run r JOIN train t ON t.Train_ID = r.Train_ID "
                        + "WHERE r.Run_ID = ?",
                runId);
        if (run == null) {
            throw new ApiException("RUN_NOT_FOUND", "Run " + runId + " not found", HttpStatus.NOT_FOUND);
        }
        return run;
    }

    /**
     * POST /admin/trains/{id}/runs/generate - calls sp_generate_train_runs.
     * The procedure checks the train (NOT_FOUND) and the date range (VALIDATION_ERROR) and
     * returns one row: Runs_Created. Existing runs are skipped, so the call can be repeated.
     */
    public Map<String, Object> generateRuns(Long trainId, RunGenerateRequest req) {
        Map<String, Object> row = sql.call("CALL sp_generate_train_runs(?, ?, ?)",
                trainId, req.fromDate(), req.toDate());
        if (row == null) {
            throw new ApiException("INTERNAL_ERROR", "Run procedure returned no result",
                    HttpStatus.INTERNAL_SERVER_ERROR);
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("runsCreated", row.get("runsCreated"));
        return result;
    }

    /** Converts "2026-10-27" to a LocalDate; null/blank means "not given"; bad text -> VALIDATION_ERROR. */
    private static LocalDate parseOptionalDate(String text, String parameterName) {
        if (text == null || text.isBlank()) {
            return null;
        }
        try {
            return LocalDate.parse(text.trim());
        } catch (DateTimeParseException e) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "'" + parameterName + "' must be a date in the format yyyy-MM-dd");
        }
    }
}
