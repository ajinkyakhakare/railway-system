package com.railway.ops.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.ops.dto.StatusUpdateRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Live train status (G5). NOT @Transactional: sp_update_train_status
 * manages its own transaction (rule R12).
 */
@Service
public class OpsStatusService {

    /** The five allowed values of train_run_status.Status. */
    private static final Set<String> VALID_STATUSES =
            Set.of("SCHEDULED", "ON_TIME", "DELAYED", "CANCELLED", "ARRIVED");

    private static final String VIEW_COLUMNS =
            "Run_ID, Train_No, Train_Name, Journey_Date, Status, Delay_Minutes, "
          + "Current_Station_ID, Current_Station_Name, Last_Reason, Updated_At";

    private final SqlHelper sql;
    private final OpsEventLogger eventLogger;

    public OpsStatusService(SqlHelper sql, OpsEventLogger eventLogger) {
        this.sql = sql;
        this.eventLogger = eventLogger;
    }

    /** All runs of one journey date (today when date is null), ordered by train number. */
    public List<Map<String, Object>> statusForDate(LocalDate date) {
        LocalDate day = (date != null) ? date : LocalDate.now();
        return sql.query("SELECT " + VIEW_COLUMNS
                + " FROM v_train_live_status WHERE Journey_Date = ? ORDER BY Train_No", day);
    }

    /** Status of a single run; RUN_NOT_FOUND when the run has no status row. */
    public Map<String, Object> statusForRun(Long runId) {
        Map<String, Object> row = sql.queryOne("SELECT " + VIEW_COLUMNS
                + " FROM v_train_live_status WHERE Run_ID = ?", runId);
        if (row == null) {
            throw runNotFound(runId);
        }
        return row;
    }

    /**
     * Updates the status through the stored procedure, then writes an audit
     * event to MongoDB (if enabled). Returns {runId,status,delayMinutes,updatedAt}.
     */
    public Map<String, Object> updateStatus(Long runId, StatusUpdateRequest request) {
        String status = request.status().trim().toUpperCase();
        if (!VALID_STATUSES.contains(status)) {
            throw ApiException.badRequest("INVALID_STATUS",
                    "Status must be one of SCHEDULED, ON_TIME, DELAYED, CANCELLED, ARRIVED");
        }

        Map<String, Object> result = sql.call("CALL sp_update_train_status(?,?,?,?,?)",
                runId, status, request.delayMinutes(), request.currentStationId(), request.reason());
        if (result == null) {
            throw runNotFound(runId);
        }

        // Use the values returned by the procedure: trigger trg_status_flag may have changed the status.
        eventLogger.log(runId,
                String.valueOf(result.get("status")),
                ((Number) result.get("delayMinutes")).intValue(),
                request.reason());
        return result;
    }

    private ApiException runNotFound(Long runId) {
        return new ApiException("RUN_NOT_FOUND", "Run " + runId + " was not found", HttpStatus.NOT_FOUND);
    }
}
