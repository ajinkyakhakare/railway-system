package com.railway.train.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.train.dto.StationRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Business logic for stations (table station). Plain SQL through SqlHelper, no JPA.
 *
 * A duplicate Station_Code makes MySQL raise a duplicate-key error; the shared
 * GlobalExceptionHandler turns it into the DUPLICATE error code, so we do not check it by hand.
 */
@Service
public class StationService {

    /** Column names are Pascal_Snake; SqlHelper converts them to camelCase JSON keys. */
    private static final String SELECT_STATION =
            "SELECT Station_ID, Station_Code, Station_Name, City, State FROM station";

    private final SqlHelper sql;

    public StationService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /stations - all stations ordered by name. */
    public List<Map<String, Object>> listStations() {
        return sql.query(SELECT_STATION + " ORDER BY Station_Name");
    }

    /** POST /admin/stations - insert a station and return the stored row. */
    public Map<String, Object> createStation(StationRequest req) {
        long stationId = sql.insert(
                "INSERT INTO station (Station_Code, Station_Name, City, State) VALUES (?, ?, ?, ?)",
                cleanCode(req), req.stationName().trim(), req.city().trim(), req.state().trim());
        return getStation(stationId);
    }

    /** PUT /admin/stations/{id} - overwrite all four fields and return the stored row. */
    public Map<String, Object> updateStation(Long stationId, StationRequest req) {
        getStation(stationId); // throws NOT_FOUND when the station does not exist
        sql.update(
                "UPDATE station SET Station_Code = ?, Station_Name = ?, City = ?, State = ? "
                        + "WHERE Station_ID = ?",
                cleanCode(req), req.stationName().trim(), req.city().trim(), req.state().trim(),
                stationId);
        return getStation(stationId);
    }

    /**
     * DELETE /admin/stations/{id}. A station that is used by a route, a route stop or a booking
     * is protected by foreign keys; in that case we answer CONSTRAINT_VIOLATION with a clear text.
     */
    public Map<String, Object> deleteStation(Long stationId) {
        getStation(stationId); // throws NOT_FOUND when the station does not exist
        try {
            sql.update("DELETE FROM station WHERE Station_ID = ?", stationId);
        } catch (DataIntegrityViolationException e) {
            throw ApiException.conflict("CONSTRAINT_VIOLATION",
                    "Station is used by a route, route stop or booking and cannot be deleted");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("deleted", true);
        return result;
    }

    /** Loads one station or throws NOT_FOUND (HTTP 404). */
    private Map<String, Object> getStation(Long stationId) {
        Map<String, Object> station = sql.queryOne(SELECT_STATION + " WHERE Station_ID = ?", stationId);
        if (station == null) {
            throw ApiException.notFound("Station " + stationId + " not found");
        }
        return station;
    }

    /** Station codes are stored in upper case without surrounding spaces (e.g. "pune " -> "PUNE"). */
    private static String cleanCode(StationRequest req) {
        return req.stationCode().trim().toUpperCase();
    }
}
