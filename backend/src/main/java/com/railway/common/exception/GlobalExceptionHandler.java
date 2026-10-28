package com.railway.common.exception;

import com.railway.common.api.ApiResponse;
import jakarta.validation.ConstraintViolationException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.MessageSourceResolvable;
import org.springframework.dao.DataAccessException;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.HandlerMethodValidationException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Converts every exception thrown by a controller or service into the JSON error envelope
 * {"success":false,"error":{"code":...,"message":...}}.
 *
 * Most important rule: a stored procedure or trigger signals a business error with
 * SIGNAL SQLSTATE '45000' and a message "ERROR_CODE: text". This class finds that
 * SQLException inside the cause chain and answers with the HTTP status of ERROR_CODE (contract C7).
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    /** Matches "SEAT_UNAVAILABLE: no seats left" -> group 1 = code, group 2 = text. */
    private static final Pattern BUSINESS_MESSAGE = Pattern.compile("^([A-Z][A-Z0-9_]*):\\s*(.*)$", Pattern.DOTALL);

    private static final String INTERNAL_MESSAGE = "An unexpected error occurred. Please try again later.";

    /**
     * Handles exceptions thrown on purpose by our own services.
     *
     * @param ex the business exception
     * @return envelope with the exception's code and status
     */
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiResponse<Void>> handleApiException(ApiException ex) {
        return build(ex.getStatus(), ex.getCode(), ex.getMessage());
    }

    /**
     * Handles failed jakarta.validation checks on a request body (@Valid on a DTO record).
     *
     * @param ex validation failure
     * @return 400 VALIDATION_ERROR with all field messages joined by "; "
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiResponse<Void>> handleBodyValidation(MethodArgumentNotValidException ex) {
        List<String> messages = new ArrayList<>();
        ex.getBindingResult().getFieldErrors()
                .forEach(fe -> messages.add(fe.getField() + ": " + fe.getDefaultMessage()));
        ex.getBindingResult().getGlobalErrors()
                .forEach(ge -> messages.add(String.valueOf(ge.getDefaultMessage())));
        return validationError(messages);
    }

    /**
     * Handles failed validation of single parameters (e.g. @RequestParam @Min(1)) in Spring 6.1 style.
     *
     * @param ex validation failure
     * @return 400 VALIDATION_ERROR
     */
    @ExceptionHandler(HandlerMethodValidationException.class)
    public ResponseEntity<ApiResponse<Void>> handleParameterValidation(HandlerMethodValidationException ex) {
        List<String> messages = ex.getAllValidationResults().stream()
                .flatMap(result -> result.getResolvableErrors().stream())
                .map(MessageSourceResolvable::getDefaultMessage)
                .filter(Objects::nonNull)
                .toList();
        return validationError(messages);
    }

    /**
     * Handles failed validation on classes annotated with @Validated.
     *
     * @param ex validation failure
     * @return 400 VALIDATION_ERROR
     */
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<ApiResponse<Void>> handleConstraintViolation(ConstraintViolationException ex) {
        List<String> messages = ex.getConstraintViolations().stream()
                .map(v -> v.getPropertyPath() + ": " + v.getMessage())
                .toList();
        return validationError(messages);
    }

    /**
     * Handles a request body that is missing or is not valid JSON.
     *
     * @param ex the parsing failure (its text is not shown to the client)
     * @return 400 VALIDATION_ERROR
     */
    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ApiResponse<Void>> handleUnreadableBody(HttpMessageNotReadableException ex) {
        return build(HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION_ERROR,
                "Request body is missing or is not valid JSON.");
    }

    /**
     * Handles a path or query value of the wrong type (e.g. /trains/abc where a number is expected).
     *
     * @param ex the conversion failure
     * @return 400 VALIDATION_ERROR naming the bad parameter
     */
    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    public ResponseEntity<ApiResponse<Void>> handleTypeMismatch(MethodArgumentTypeMismatchException ex) {
        return build(HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION_ERROR,
                "Invalid value for parameter '" + ex.getName() + "'.");
    }

    /**
     * Handles @PreAuthorize / method security refusals (logged in, but wrong role).
     *
     * @param ex the refusal
     * @return 403 FORBIDDEN
     */
    @ExceptionHandler(AccessDeniedException.class)
    public ResponseEntity<ApiResponse<Void>> handleAccessDenied(AccessDeniedException ex) {
        return build(HttpStatus.FORBIDDEN, ErrorCodes.FORBIDDEN,
                "You do not have permission to perform this action.");
    }

    /**
     * Handles every database exception: first looks for a business error raised by SIGNAL 45000,
     * then for duplicate-key and constraint errors, otherwise answers INTERNAL_ERROR.
     *
     * @param ex Spring's translated database exception
     * @return envelope with the matching code and status
     */
    @ExceptionHandler(DataAccessException.class)
    public ResponseEntity<ApiResponse<Void>> handleDataAccess(DataAccessException ex) {
        ResponseEntity<ApiResponse<Void>> business = businessErrorFrom(ex);
        if (business != null) {
            return business;
        }
        // DuplicateKeyException is a subclass of DataIntegrityViolationException, so test it first.
        if (ex instanceof DuplicateKeyException) {
            return build(HttpStatus.CONFLICT, ErrorCodes.DUPLICATE,
                    "A record with the same unique value already exists.");
        }
        if (ex instanceof DataIntegrityViolationException) {
            return build(HttpStatus.CONFLICT, ErrorCodes.CONSTRAINT_VIOLATION,
                    "The request violates a data constraint.");
        }
        return internalError(ex);
    }

    /**
     * Last safety net for everything else. Spring's own 4xx exceptions (unknown URL,
     * wrong HTTP method, ...) keep a 4xx answer; anything unknown becomes INTERNAL_ERROR.
     *
     * @param ex any exception not handled above
     * @return envelope
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiResponse<Void>> handleAnyException(Exception ex) {
        if (ex instanceof ErrorResponse errorResponse && errorResponse.getStatusCode().is4xxClientError()) {
            HttpStatus status = HttpStatus.resolve(errorResponse.getStatusCode().value());
            if (status == null) {
                status = HttpStatus.BAD_REQUEST;
            }
            if (status == HttpStatus.NOT_FOUND) {
                return build(status, ErrorCodes.NOT_FOUND, "Resource not found.");
            }
            return build(status, ErrorCodes.VALIDATION_ERROR,
                    "Request cannot be processed: " + status.getReasonPhrase() + ".");
        }
        ResponseEntity<ApiResponse<Void>> business = businessErrorFrom(ex);
        if (business != null) {
            return business;
        }
        return internalError(ex);
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Walks the cause chain looking for a SQLException with SQLSTATE 45000 (our SIGNAL).
     *
     * @param ex the top level exception
     * @return the answer for that business error, or null when the chain contains no SIGNAL 45000
     */
    private ResponseEntity<ApiResponse<Void>> businessErrorFrom(Throwable ex) {
        Throwable current = ex;
        for (int depth = 0; current != null && depth < 20; depth++) {   // depth limit protects against cyclic causes
            if (current instanceof SQLException sql && "45000".equals(sql.getSQLState())) {
                String text = sql.getMessage() == null ? "" : sql.getMessage().trim();
                Matcher matcher = BUSINESS_MESSAGE.matcher(text);
                if (matcher.matches() && ErrorCodes.isKnown(matcher.group(1))) {
                    String code = matcher.group(1);
                    return build(ErrorCodes.statusOf(code), code, matcher.group(2).trim());
                }
                // A SIGNAL without a known C7 code is a bug in the SQL file: do not leak its text.
                log.error("Database raised SQLSTATE 45000 without a valid C7 code: {}", text);
                return build(HttpStatus.INTERNAL_SERVER_ERROR, ErrorCodes.INTERNAL_ERROR, INTERNAL_MESSAGE);
            }
            current = current.getCause();
        }
        return null;
    }

    private ResponseEntity<ApiResponse<Void>> validationError(List<String> messages) {
        String text = messages.isEmpty() ? "Validation failed." : String.join("; ", messages);
        return build(HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION_ERROR, text);
    }

    private ResponseEntity<ApiResponse<Void>> internalError(Throwable ex) {
        log.error("Unhandled exception", ex);   // full stack trace goes to the log only
        return build(HttpStatus.INTERNAL_SERVER_ERROR, ErrorCodes.INTERNAL_ERROR, INTERNAL_MESSAGE);
    }

    private static ResponseEntity<ApiResponse<Void>> build(HttpStatus status, String code, String message) {
        return ResponseEntity.status(status).body(ApiResponse.fail(code, message));
    }
}
