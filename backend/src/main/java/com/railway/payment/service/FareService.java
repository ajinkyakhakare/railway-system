package com.railway.payment.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

/**
 * GET /api/v1/fares/quote.
 *
 * All money maths is done by the database functions so the quote always matches what
 * sp_book_ticket will charge:
 *   distance   = fn_distance_km(runId, from, to)
 *   concession = fn_effective_concession(dateOfBirth, declaredConcession)
 *   base       = fn_base_fare(classCode, distance)
 *   net        = fn_net_fare(base, concession)
 * Java only validates input, checks ownership and adds up the net fares.
 *
 * Read-only, so no transaction is needed.
 */
@Service
public class FareService {

    private static final int MAX_PASSENGERS = 6;

    /**
     * One row per passenger. The inner query computes the concession and base fare, the
     * outer query applies fn_net_fare on them (a column alias cannot be reused in the
     * same SELECT, hence the derived table).
     */
    private static final String PASSENGER_FARE_SQL =
            "SELECT t.Passenger_ID, t.User_ID, t.Full_Name, t.Concession_Type, t.Base_Fare, "
          + "       fn_net_fare(t.Base_Fare, t.Concession_Type) AS Net_Fare "
          + "FROM ( "
          + "  SELECT p.Passenger_ID, p.User_ID, p.Full_Name, "
          + "         fn_effective_concession(p.Date_Of_Birth, p.Concession_Type) AS Concession_Type, "
          + "         fn_base_fare(?, ?) AS Base_Fare "
          + "  FROM passenger p "
          + "  WHERE p.Passenger_ID = ? "
          + ") t";

    private final SqlHelper sql;

    public FareService(SqlHelper sql) {
        this.sql = sql;
    }

    public Map<String, Object> quote(Long userId, Long runId, String classCode,
                                     Long fromStationId, Long toStationId, String passengerIdsCsv) {
        // 1. Input validation.
        if (runId == null || fromStationId == null || toStationId == null
                || classCode == null || classCode.isBlank()) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "runId, classCode, fromStationId, toStationId and passengerIds are required");
        }
        List<Long> passengerIds = parsePassengerIds(passengerIdsCsv);

        // 2. Distance. NULL means the run does not exist or a station is not on its route.
        Integer distanceKm = sql.scalar("SELECT fn_distance_km(?, ?, ?)",
                Integer.class, runId, fromStationId, toStationId);
        if (distanceKm == null || distanceKm <= 0) {
            throw ApiException.badRequest("INVALID_STATIONS",
                    "The stations are not valid for this train run");
        }

        // 3. Fare of every passenger.
        List<Map<String, Object>> passengerFares = new ArrayList<>();
        BigDecimal totalFare = BigDecimal.ZERO;

        for (Long passengerId : passengerIds) {
            Map<String, Object> row = sql.queryOne(PASSENGER_FARE_SQL, classCode, distanceKm, passengerId);

            // A missing passenger gets the same answer as someone else's passenger, so the
            // API does not reveal which passenger ids exist.
            if (row == null || toLong(row.get("userId")) != userId.longValue()) {
                throw new ApiException("PASSENGER_NOT_OWNED",
                        "Passenger " + passengerId + " does not belong to the current user",
                        HttpStatus.FORBIDDEN);
            }

            BigDecimal baseFare = toBigDecimal(row.get("baseFare"));
            BigDecimal netFare = toBigDecimal(row.get("netFare"));
            if (baseFare == null || netFare == null) {
                // fn_base_fare returns NULL when fare_rule has no row for this class.
                throw ApiException.notFound("No fare rule is defined for class " + classCode);
            }

            Map<String, Object> item = new LinkedHashMap<>();
            item.put("passengerId", passengerId);
            item.put("passengerName", row.get("fullName"));
            item.put("concessionType", row.get("concessionType"));
            item.put("baseFare", baseFare);
            item.put("netFare", netFare);
            passengerFares.add(item);

            totalFare = totalFare.add(netFare);
        }

        // 4. Response shape of contract C9.
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("distanceKm", distanceKm);
        result.put("totalFare", totalFare);
        result.put("passengers", passengerFares);
        return result;
    }

    // ---------------------------------------------------------------- helpers

    /** Turns "1,2,3" into [1,2,3]. Rejects empty lists, non numbers, duplicates and more than 6 ids. */
    private List<Long> parsePassengerIds(String csv) {
        if (csv == null || csv.isBlank()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "passengerIds is required, e.g. passengerIds=1,2");
        }
        Set<Long> ids = new LinkedHashSet<>();   // keeps the order the client sent
        for (String part : csv.split(",")) {
            try {
                if (!ids.add(Long.parseLong(part.trim()))) {
                    throw ApiException.badRequest("VALIDATION_ERROR", "passengerIds contains a duplicate id");
                }
            } catch (NumberFormatException e) {
                throw ApiException.badRequest("VALIDATION_ERROR", "passengerIds must be comma separated numbers");
            }
        }
        if (ids.size() > MAX_PASSENGERS) {
            throw ApiException.badRequest("TOO_MANY_PASSENGERS",
                    "At most " + MAX_PASSENGERS + " passengers are allowed per booking");
        }
        return new ArrayList<>(ids);
    }

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
