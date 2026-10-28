package com.railway.train.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.train.dto.TrainCreateRequest;
import com.railway.train.dto.TrainUpdateRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

/**
 * Business logic for trains: listing, timetable, search between two stations, and admin
 * create/update (tables train and train_schedule; views v_train_timetable, v_train_stop_pairs).
 *
 * createTrain() and updateTrain() write several rows and call NO stored procedure, so they are
 * @Transactional. Coach and run generation (which CALL procedures) live in CoachService and
 * RunService and are deliberately not transactional (rule R12).
 */
@Service
public class TrainService {

    /** One train row exactly as the API returns it (trainId, trainNo, trainName, trainType, routeId, routeName, isActive). */
    private static final String SELECT_TRAIN =
            "SELECT t.Train_ID, t.Train_No, t.Train_Name, t.Train_Type, t.Route_ID, r.Route_Name, "
                    + "t.Is_Active FROM train t JOIN route r ON r.Route_ID = t.Route_ID";

    private final SqlHelper sql;

    public TrainService(SqlHelper sql) {
        this.sql = sql;
    }

    // ------------------------------------------------------------------ read operations

    /** GET /trains - all trains; optional ?q= matches part of the name or the number. */
    public List<Map<String, Object>> listTrains(String q) {
        if (q == null || q.isBlank()) {
            return sql.query(SELECT_TRAIN + " ORDER BY t.Train_No");
        }
        String pattern = "%" + q.trim() + "%";
        return sql.query(SELECT_TRAIN + " WHERE t.Train_Name LIKE ? OR t.Train_No LIKE ? "
                + "ORDER BY t.Train_No", pattern, pattern);
    }

    /** GET /trains/{id} - one train or NOT_FOUND (404). */
    public Map<String, Object> getTrain(Long trainId) {
        Map<String, Object> train = sql.queryOne(SELECT_TRAIN + " WHERE t.Train_ID = ?", trainId);
        if (train == null) {
            throw ApiException.notFound("Train " + trainId + " not found");
        }
        return train;
    }

    /** GET /trains/{id}/timetable - the rows of view v_train_timetable for this train. */
    public List<Map<String, Object>> getTimetable(Long trainId) {
        getTrain(trainId); // throws NOT_FOUND for an unknown train
        return sql.query(
                "SELECT Train_ID, Train_No, Train_Name, Route_ID, Stop_Seq, Station_ID, Station_Code, "
                        + "Station_Name, Arrival_Time, Departure_Time, Day_Offset, Distance_From_Source_Km "
                        + "FROM v_train_timetable WHERE Train_ID = ? ORDER BY Stop_Seq",
                trainId);
    }

    /**
     * GET /trains/search?fromStationId=&toStationId=&date= - trains that run from one station
     * to another on a journey date.
     *
     * v_train_stop_pairs already holds every (from stop, to stop) pair of every active train
     * with from-sequence < to-sequence. We join it to train_run to keep only trains that have
     * a run on the requested date, and ask fn_journey_duration_min for the travel time.
     *
     * The three query parameters arrive as plain values so that a missing or badly formatted
     * value gives a clean VALIDATION_ERROR (HTTP 400) from this method.
     */
    public List<Map<String, Object>> searchTrains(Long fromStationId, Long toStationId, String dateText) {
        if (fromStationId == null || toStationId == null) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "fromStationId and toStationId are required");
        }
        if (fromStationId.equals(toStationId)) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "fromStationId and toStationId must be different");
        }
        LocalDate date = parseRequiredDate(dateText, "date");

        return sql.query(
                "SELECT r.Run_ID, p.Train_ID, p.Train_No, p.Train_Name, p.Train_Type, "
                        + "p.From_Station_ID, p.To_Station_ID, r.Journey_Date, "
                        + "p.Departure_Time, p.Arrival_Time, "
                        + "fn_journey_duration_min(r.Run_ID, p.From_Station_ID, p.To_Station_ID) AS Duration_Min, "
                        + "p.Distance_Km "
                        + "FROM v_train_stop_pairs p "
                        + "JOIN train_run r ON r.Train_ID = p.Train_ID AND r.Journey_Date = ? "
                        + "WHERE p.From_Station_ID = ? AND p.To_Station_ID = ? "
                        + "ORDER BY p.Departure_Time",
                date, fromStationId, toStationId);
    }

    // ------------------------------------------------------------------ admin operations

    /** POST /admin/trains - insert the train and one train_schedule row per run day. */
    @Transactional
    public Map<String, Object> createTrain(TrainCreateRequest req) {
        requireRoute(req.routeId());

        // Duplicate Train_No -> MySQL duplicate-key error -> DUPLICATE (handled globally).
        long trainId = sql.insert(
                "INSERT INTO train (Train_No, Train_Name, Train_Type, Route_ID, Is_Active) "
                        + "VALUES (?, ?, ?, ?, 1)",
                req.trainNo(), req.trainName().trim(), req.trainType(), req.routeId());
        insertSchedule(trainId, req.runDays());

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("trainId", trainId);
        return result;
    }

    /** PUT /admin/trains/{id} - update the train and REPLACE its train_schedule rows. */
    @Transactional
    public Map<String, Object> updateTrain(Long trainId, TrainUpdateRequest req) {
        getTrain(trainId); // throws NOT_FOUND for an unknown train
        requireRoute(req.routeId());

        sql.update("UPDATE train SET Train_Name = ?, Train_Type = ?, Route_ID = ?, Is_Active = ? "
                        + "WHERE Train_ID = ?",
                req.trainName().trim(), req.trainType(), req.routeId(), req.isActive(), trainId);

        sql.update("DELETE FROM train_schedule WHERE Train_ID = ?", trainId);
        insertSchedule(trainId, req.runDays());

        return getTrain(trainId);
    }

    // ------------------------------------------------------------------ private helpers

    /** Inserts one train_schedule row per distinct weekday (1 = Monday to 7 = Sunday). */
    private void insertSchedule(long trainId, List<Integer> runDays) {
        for (Integer day : new LinkedHashSet<>(runDays)) { // the set removes repeated days
            sql.update("INSERT INTO train_schedule (Train_ID, Day_Of_Week) VALUES (?, ?)", trainId, day);
        }
    }

    /** A train must point to an existing route; otherwise answer VALIDATION_ERROR (400). */
    private void requireRoute(Long routeId) {
        if (sql.queryOne("SELECT Route_ID FROM route WHERE Route_ID = ?", routeId) == null) {
            throw ApiException.badRequest("VALIDATION_ERROR", "routeId " + routeId + " does not exist");
        }
    }

    /** Converts "2026-10-27" to a LocalDate; missing or malformed text -> VALIDATION_ERROR. */
    private static LocalDate parseRequiredDate(String text, String parameterName) {
        if (text == null || text.isBlank()) {
            throw ApiException.badRequest("VALIDATION_ERROR", "'" + parameterName + "' is required");
        }
        try {
            return LocalDate.parse(text.trim());
        } catch (DateTimeParseException e) {
            throw ApiException.badRequest("VALIDATION_ERROR",
                    "'" + parameterName + "' must be a date in the format yyyy-MM-dd");
        }
    }
}
