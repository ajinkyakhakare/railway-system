package com.railway.user.service;

import com.railway.common.db.SqlHelper;
import com.railway.common.exception.ApiException;
import com.railway.user.dto.PassengerRequest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Saved passengers of the logged-in user. A user only ever sees and changes their own rows.
 * Not @Transactional: every method is one statement (plus read-backs) and calls no procedure.
 */
@Service
public class PassengerService {

    /** ageCategory (CHILD / ADULT / SENIOR) is computed by the SQL function fn_age_category. */
    private static final String SELECT_PASSENGER =
            "SELECT Passenger_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type, "
                    + "fn_age_category(Date_Of_Birth) AS Age_Category FROM passenger ";

    private final SqlHelper sql;

    public PassengerService(SqlHelper sql) {
        this.sql = sql;
    }

    /** GET /passengers */
    public List<Map<String, Object>> list(Long userId) {
        return sql.query(SELECT_PASSENGER + "WHERE User_ID = ? ORDER BY Passenger_ID", userId);
    }

    /** POST /passengers. The BEFORE INSERT trigger rejects a future date of birth. */
    public Map<String, Object> create(Long userId, PassengerRequest request) {
        long passengerId = sql.insert(
                "INSERT INTO passenger (User_ID, Full_Name, Date_Of_Birth, Gender, Concession_Type) "
                        + "VALUES (?, ?, ?, ?, ?)",
                userId, request.fullName().trim(), request.dateOfBirth(),
                request.gender(), request.concessionType());
        return findOne(passengerId);
    }

    /** PUT /passengers/{id} (own passengers only). */
    public Map<String, Object> update(Long userId, Long passengerId, PassengerRequest request) {
        requireOwned(userId, passengerId);
        sql.update("UPDATE passenger SET Full_Name = ?, Date_Of_Birth = ?, Gender = ?, Concession_Type = ? "
                        + "WHERE Passenger_ID = ? AND User_ID = ?",
                request.fullName().trim(), request.dateOfBirth(), request.gender(),
                request.concessionType(), passengerId, userId);
        return findOne(passengerId);
    }

    /** DELETE /passengers/{id} -> {deleted:true}; PASSENGER_IN_USE when a booking references it. */
    public Map<String, Object> delete(Long userId, Long passengerId) {
        requireOwned(userId, passengerId);
        try {
            sql.update("DELETE FROM passenger WHERE Passenger_ID = ? AND User_ID = ?", passengerId, userId);
        } catch (DataIntegrityViolationException e) {
            // Foreign key from booking_passenger blocks the delete.
            throw ApiException.conflict("PASSENGER_IN_USE",
                    "This passenger is used in bookings and cannot be deleted");
        }
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("deleted", true);
        return result;
    }

    // ------------------------------------------------------------------ helpers

    private Map<String, Object> findOne(Long passengerId) {
        Map<String, Object> row = sql.queryOne(SELECT_PASSENGER + "WHERE Passenger_ID = ?", passengerId);
        if (row == null) {
            throw ApiException.notFound("Passenger not found");
        }
        return row;
    }

    /** NOT_FOUND when the passenger does not exist, NOT_OWNER (403) when it belongs to someone else. */
    private void requireOwned(Long userId, Long passengerId) {
        Long ownerId = sql.scalar("SELECT User_ID FROM passenger WHERE Passenger_ID = ?",
                Long.class, passengerId);
        if (ownerId == null) {
            throw ApiException.notFound("Passenger not found");
        }
        if (!ownerId.equals(userId)) {
            throw new ApiException("NOT_OWNER", "This passenger belongs to another user", HttpStatus.FORBIDDEN);
        }
    }
}
