package com.railway.train.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.train.dto.RouteCreateRequest;
import com.railway.train.dto.RouteStopRequest;
import com.railway.train.dto.RouteStopTimeRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Business logic for routes and route stops (tables route and route_stop).
 *
 * Creating a route inserts one route row plus several route_stop rows, so that method is
 * @Transactional (all rows are saved together or none). It calls no stored procedure, so
 * rule R12 does not forbid the annotation.
 */
@Service
public class RouteService {

    /** Same column list for "list the stops of a route" and "return one updated stop". */
    private static final String SELECT_STOP =
            "SELECT rs.Route_Stop_ID, rs.Stop_Seq, rs.Station_ID, s.Station_Code, s.Station_Name, "
                    + "rs.Arrival_Time, rs.Departure_Time, rs.Day_Offset, rs.Distance_From_Source_Km "
                    + "FROM route_stop rs JOIN station s ON s.Station_ID = rs.Station_ID ";

    private final SqlHelper sql;

    public RouteService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /routes - all routes. */
    public List<Map<String, Object>> listRoutes() {
        return sql.query("SELECT Route_ID, Route_Name, Source_Station_ID, Dest_Station_ID "
                + "FROM route ORDER BY Route_ID");
    }

    /** GET /routes/{id}/stops - the stops of one route in running order. */
    public List<Map<String, Object>> listStops(Long routeId) {
        if (sql.queryOne("SELECT Route_ID FROM route WHERE Route_ID = ?", routeId) == null) {
            throw ApiException.notFound("Route " + routeId + " not found");
        }
        return sql.query(SELECT_STOP + "WHERE rs.Route_ID = ? ORDER BY rs.Stop_Seq", routeId);
    }

    /**
     * POST /admin/routes - create a route together with all its stops.
     * We validate the stop list first (clear messages), then insert. The database constraints
     * (unique route name, unique stop sequence, foreign keys) remain the final safety net.
     */
    @Transactional
    public Map<String, Object> createRoute(RouteCreateRequest req) {
        List<RouteStopRequest> stops = validateAndSortStops(req);

        long routeId = sql.insert(
                "INSERT INTO route (Route_Name, Source_Station_ID, Dest_Station_ID) VALUES (?, ?, ?)",
                req.routeName().trim(), req.sourceStationId(), req.destStationId());

        for (RouteStopRequest stop : stops) {
            sql.update("INSERT INTO route_stop (Route_ID, Station_ID, Stop_Seq, Arrival_Time, "
                            + "Departure_Time, Day_Offset, Distance_From_Source_Km) "
                            + "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    routeId, stop.stationId(), stop.stopSeq(), stop.arrivalTime(),
                    stop.departureTime(), valueOrZero(stop.dayOffset()),
                    valueOrZero(stop.distanceFromSourceKm()));
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("routeId", routeId);
        return result;
    }

    /**
     * PUT /admin/route-stops/{id} - change arrival/departure time of one stop.
     * The AFTER UPDATE trigger trg_route_stop_audit writes the old and new times to
     * route_stop_audit. The BEFORE INSERT trigger does not run on UPDATE, so the rule
     * "departure must not be before arrival" is checked here.
     */
    public Map<String, Object> updateStopTimes(Long routeStopId, RouteStopTimeRequest req) {
        if (sql.queryOne("SELECT Route_Stop_ID FROM route_stop WHERE Route_Stop_ID = ?",
                routeStopId) == null) {
            throw ApiException.notFound("Route stop " + routeStopId + " not found");
        }
        checkHaltDoesNotCrossMidnight(req.arrivalTime(), req.departureTime());

        sql.update("UPDATE route_stop SET Arrival_Time = ?, Departure_Time = ? WHERE Route_Stop_ID = ?",
                req.arrivalTime(), req.departureTime(), routeStopId);

        return sql.queryOne(SELECT_STOP + "WHERE rs.Route_Stop_ID = ?", routeStopId);
    }

    // ------------------------------------------------------------------ private helpers

    /**
     * Checks the stop list of a new route and returns it sorted by stopSeq.
     * Rules: source differs from destination; stop sequences and stations are unique; the first
     * stop is the source and the last stop is the destination; distance and day offset never
     * decrease along the route; a halt does not cross midnight.
     */
    private List<RouteStopRequest> validateAndSortStops(RouteCreateRequest req) {
        if (req.sourceStationId().equals(req.destStationId())) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "sourceStationId and destStationId must be different");
        }

        List<RouteStopRequest> stops = new ArrayList<>(req.stops());
        stops.sort(Comparator.comparing(RouteStopRequest::stopSeq));

        Set<Integer> usedSeq = new HashSet<>();
        Set<Long> usedStations = new HashSet<>();
        int previousDistance = 0;
        int previousDayOffset = 0;

        for (RouteStopRequest stop : stops) {
            if (!usedSeq.add(stop.stopSeq())) {
                throw ApiException.badRequest("VALIDATION_ERROR",
                        "stopSeq " + stop.stopSeq() + " is used more than once");
            }
            if (!usedStations.add(stop.stationId())) {
                throw ApiException.badRequest("VALIDATION_ERROR",
                        "station " + stop.stationId() + " appears more than once in the route");
            }
            checkHaltDoesNotCrossMidnight(stop.arrivalTime(), stop.departureTime());

            int distance = valueOrZero(stop.distanceFromSourceKm());
            int dayOffset = valueOrZero(stop.dayOffset());
            if (distance < previousDistance) {
                throw ApiException.badRequest("VALIDATION_ERROR",
                        "distanceFromSourceKm must not decrease along the route (stopSeq "
                                + stop.stopSeq() + ")");
            }
            if (dayOffset < previousDayOffset) {
                throw ApiException.badRequest("VALIDATION_ERROR",
                        "dayOffset must not decrease along the route (stopSeq " + stop.stopSeq() + ")");
            }
            previousDistance = distance;
            previousDayOffset = dayOffset;
        }

        Long firstStation = stops.get(0).stationId();
        Long lastStation = stops.get(stops.size() - 1).stationId();
        if (!firstStation.equals(req.sourceStationId())) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "the first stop must be the source station");
        }
        if (!lastStation.equals(req.destStationId())) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "the last stop must be the destination station");
        }
        return stops;
    }

    /** When both times are given, departure must not be earlier than arrival (same rule as trg_route_stop_bi). */
    private static void checkHaltDoesNotCrossMidnight(LocalTime arrival, LocalTime departure) {
        if (arrival != null && departure != null && departure.isBefore(arrival)) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "departureTime must not be earlier than arrivalTime");
        }
    }

    /** Optional numbers fall back to 0, which is the column default in route_stop. */
    private static int valueOrZero(Integer value) {
        return value == null ? 0 : value;
    }
}
