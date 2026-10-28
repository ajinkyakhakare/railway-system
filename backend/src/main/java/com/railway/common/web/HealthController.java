package com.railway.common.web;

import com.railway.common.api.ApiResponse;
import com.railway.common.db.SqlHelper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Public health check used to verify that the backend and the database are reachable.
 */
@RestController
@RequestMapping("/api/v1")
public class HealthController {

    private static final Logger log = LoggerFactory.getLogger(HealthController.class);

    private final SqlHelper sql;

    /**
     * Creates the controller.
     *
     * @param sql shared database helper
     */
    public HealthController(SqlHelper sql) {
        this.sql = sql;
    }

    /**
     * GET /api/v1/health - no token needed.
     *
     * @return {"status":"UP","db":"UP"} or {"status":"UP","db":"DOWN"} inside the ApiResponse envelope
     */
    @GetMapping("/health")
    public ApiResponse<Map<String, String>> health() {
        String db;
        try {
            Integer one = sql.scalar("SELECT 1", Integer.class);
            db = (one != null && one == 1) ? "UP" : "DOWN";
        } catch (Exception ex) {
            log.warn("Health check: database is not reachable ({})", ex.getClass().getSimpleName());
            db = "DOWN";
        }
        Map<String, String> body = new LinkedHashMap<>();
        body.put("status", "UP");   // if this code runs, the application itself is up
        body.put("db", db);
        return ApiResponse.ok(body);
    }
}
