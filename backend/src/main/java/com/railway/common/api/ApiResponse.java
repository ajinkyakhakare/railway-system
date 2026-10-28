package com.railway.common.api;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * The JSON envelope used by every REST endpoint.
 * <pre>
 * success: {"success":true,"data":...}
 * failure: {"success":false,"error":{"code":"...","message":"..."}}
 * </pre>
 * NON_NULL means a failure response has no "data" key and a success response has no "error" key.
 * (Side effect: ok(null) produces just {"success":true}.)
 *
 * @param success true when the request worked
 * @param data    payload of a successful response
 * @param error   error details of a failed response
 * @param <T>     type of the payload
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiResponse<T>(boolean success, T data, ApiError error) {

    /**
     * Builds a success envelope.
     *
     * @param data the payload (may be null)
     * @param <T>  payload type
     * @return envelope with success=true
     */
    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(true, data, null);
    }

    /**
     * Builds a failure envelope.
     *
     * @param code    error code from contract section C7
     * @param message readable text for the user
     * @param <T>     payload type (always empty for failures)
     * @return envelope with success=false
     */
    public static <T> ApiResponse<T> fail(String code, String message) {
        return new ApiResponse<>(false, null, new ApiError(code, message));
    }
}
