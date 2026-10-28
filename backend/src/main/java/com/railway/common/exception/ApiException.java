package com.railway.common.exception;

import org.springframework.http.HttpStatus;

import java.util.Objects;

/**
 * Business exception thrown by services. The GlobalExceptionHandler turns it into
 * the JSON error envelope with the given HTTP status.
 */
public class ApiException extends RuntimeException {

    private final String code;
    private final HttpStatus status;

    /**
     * Creates an exception.
     *
     * @param code    error code from contract section C7 (see {@link ErrorCodes})
     * @param message readable text for the user
     * @param status  HTTP status of the response
     */
    public ApiException(String code, String message, HttpStatus status) {
        super(message);
        this.code = Objects.requireNonNull(code, "code");
        this.status = Objects.requireNonNull(status, "status");
    }

    /**
     * @return the C7 error code
     */
    public String getCode() {
        return code;
    }

    /**
     * @return the HTTP status to answer with
     */
    public HttpStatus getStatus() {
        return status;
    }

    /**
     * Shortcut for 404 NOT_FOUND.
     *
     * @param message readable text
     * @return exception ready to throw
     */
    public static ApiException notFound(String message) {
        return new ApiException(ErrorCodes.NOT_FOUND, message, HttpStatus.NOT_FOUND);
    }

    /**
     * Shortcut for a 400 error with the given code (e.g. VALIDATION_ERROR).
     *
     * @param code    C7 code
     * @param message readable text
     * @return exception ready to throw
     */
    public static ApiException badRequest(String code, String message) {
        return new ApiException(code, message, HttpStatus.BAD_REQUEST);
    }

    /**
     * Shortcut for 403 FORBIDDEN.
     *
     * @param message readable text
     * @return exception ready to throw
     */
    public static ApiException forbidden(String message) {
        return new ApiException(ErrorCodes.FORBIDDEN, message, HttpStatus.FORBIDDEN);
    }

    /**
     * Shortcut for a 409 error with the given code (e.g. DUPLICATE, SEAT_UNAVAILABLE).
     *
     * @param code    C7 code
     * @param message readable text
     * @return exception ready to throw
     */
    public static ApiException conflict(String code, String message) {
        return new ApiException(code, message, HttpStatus.CONFLICT);
    }
}
