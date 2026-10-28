package com.railway.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * All error codes of contract section C7 and the HTTP status of each code.
 * The same codes are used as the prefix of SQL error messages ("CODE: text"),
 * so the database and the REST API speak the same language.
 */
public final class ErrorCodes {

    // ---- 400 ----
    public static final String VALIDATION_ERROR = "VALIDATION_ERROR";
    public static final String INVALID_STATIONS = "INVALID_STATIONS";
    public static final String TOO_MANY_PASSENGERS = "TOO_MANY_PASSENGERS";
    public static final String INVALID_STATUS = "INVALID_STATUS";
    // ---- 401 ----
    public static final String INVALID_CREDENTIALS = "INVALID_CREDENTIALS";
    public static final String UNAUTHORIZED = "UNAUTHORIZED";
    public static final String OTP_INVALID = "OTP_INVALID";
    // ---- 403 ----
    public static final String FORBIDDEN = "FORBIDDEN";
    public static final String NOT_OWNER = "NOT_OWNER";
    public static final String PASSENGER_NOT_OWNED = "PASSENGER_NOT_OWNED";
    // ---- 404 ----
    public static final String NOT_FOUND = "NOT_FOUND";
    public static final String RUN_NOT_FOUND = "RUN_NOT_FOUND";
    public static final String BOOKING_NOT_FOUND = "BOOKING_NOT_FOUND";
    // ---- 409 ----
    public static final String EMAIL_EXISTS = "EMAIL_EXISTS";
    public static final String DUPLICATE = "DUPLICATE";
    public static final String CONSTRAINT_VIOLATION = "CONSTRAINT_VIOLATION";
    public static final String PASSENGER_IN_USE = "PASSENGER_IN_USE";
    public static final String SEAT_UNAVAILABLE = "SEAT_UNAVAILABLE";
    public static final String BOOKING_CLOSED_WL_FULL = "BOOKING_CLOSED_WL_FULL";
    public static final String RUN_DEPARTED = "RUN_DEPARTED";
    public static final String ALREADY_CANCELLED = "ALREADY_CANCELLED";
    public static final String CANCEL_NOT_ALLOWED = "CANCEL_NOT_ALLOWED";
    public static final String PAYMENT_NOT_ALLOWED = "PAYMENT_NOT_ALLOWED";
    public static final String REFUND_EXCEEDS_FARE = "REFUND_EXCEEDS_FARE";
    // ---- 423 / 500 ----
    public static final String ACCOUNT_LOCKED = "ACCOUNT_LOCKED";
    public static final String INTERNAL_ERROR = "INTERNAL_ERROR";

    /** code -> HTTP status, exactly as in contract C7. */
    private static final Map<String, HttpStatus> STATUS_BY_CODE;

    static {
        Map<String, HttpStatus> m = new LinkedHashMap<>();
        m.put(VALIDATION_ERROR, HttpStatus.BAD_REQUEST);
        m.put(INVALID_STATIONS, HttpStatus.BAD_REQUEST);
        m.put(TOO_MANY_PASSENGERS, HttpStatus.BAD_REQUEST);
        m.put(INVALID_STATUS, HttpStatus.BAD_REQUEST);
        m.put(INVALID_CREDENTIALS, HttpStatus.UNAUTHORIZED);
        m.put(UNAUTHORIZED, HttpStatus.UNAUTHORIZED);
        m.put(OTP_INVALID, HttpStatus.UNAUTHORIZED);
        m.put(FORBIDDEN, HttpStatus.FORBIDDEN);
        m.put(NOT_OWNER, HttpStatus.FORBIDDEN);
        m.put(PASSENGER_NOT_OWNED, HttpStatus.FORBIDDEN);
        m.put(NOT_FOUND, HttpStatus.NOT_FOUND);
        m.put(RUN_NOT_FOUND, HttpStatus.NOT_FOUND);
        m.put(BOOKING_NOT_FOUND, HttpStatus.NOT_FOUND);
        m.put(EMAIL_EXISTS, HttpStatus.CONFLICT);
        m.put(DUPLICATE, HttpStatus.CONFLICT);
        m.put(CONSTRAINT_VIOLATION, HttpStatus.CONFLICT);
        m.put(PASSENGER_IN_USE, HttpStatus.CONFLICT);
        m.put(SEAT_UNAVAILABLE, HttpStatus.CONFLICT);
        m.put(BOOKING_CLOSED_WL_FULL, HttpStatus.CONFLICT);
        m.put(RUN_DEPARTED, HttpStatus.CONFLICT);
        m.put(ALREADY_CANCELLED, HttpStatus.CONFLICT);
        m.put(CANCEL_NOT_ALLOWED, HttpStatus.CONFLICT);
        m.put(PAYMENT_NOT_ALLOWED, HttpStatus.CONFLICT);
        m.put(REFUND_EXCEEDS_FARE, HttpStatus.CONFLICT);
        m.put(ACCOUNT_LOCKED, HttpStatus.LOCKED);   // 423
        m.put(INTERNAL_ERROR, HttpStatus.INTERNAL_SERVER_ERROR);
        STATUS_BY_CODE = Collections.unmodifiableMap(m);
    }

    private ErrorCodes() {
        // constants only, never instantiated
    }

    /**
     * Tells whether a code is one of the C7 codes.
     *
     * @param code text to test (may be null)
     * @return true when the code is defined in contract section C7
     */
    public static boolean isKnown(String code) {
        return code != null && STATUS_BY_CODE.containsKey(code);
    }

    /**
     * Looks up the HTTP status of a C7 code.
     *
     * @param code a C7 code
     * @return its HTTP status, or 500 when the code is not known
     */
    public static HttpStatus statusOf(String code) {
        return STATUS_BY_CODE.getOrDefault(code, HttpStatus.INTERNAL_SERVER_ERROR);
    }
}
