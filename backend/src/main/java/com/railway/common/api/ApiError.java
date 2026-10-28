package com.railway.common.api;

/**
 * Error part of the failure envelope.
 *
 * @param code    machine readable code from contract section C7 (e.g. SEAT_UNAVAILABLE)
 * @param message human readable explanation
 */
public record ApiError(String code, String message) {
}
