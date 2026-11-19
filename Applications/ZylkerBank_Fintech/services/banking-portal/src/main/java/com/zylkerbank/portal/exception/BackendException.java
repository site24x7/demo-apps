package com.zylkerbank.portal.exception;

import org.springframework.http.HttpStatus;

/**
 * Unified exception representing downstream backend failures (Ledger, Gateway, AI, DB).
 * Translates HTTP status codes and backend JSON error bodies into clean user-facing errors.
 */
public class BackendException extends RuntimeException {

    private final HttpStatus httpStatus;
    private final String errorCode;

    public BackendException(HttpStatus httpStatus, String errorCode, String message) {
        super(message);
        this.httpStatus = httpStatus;
        this.errorCode = errorCode != null ? errorCode : "INTERNAL_ERROR";
    }

    public BackendException(HttpStatus httpStatus, String errorCode, String message, Throwable cause) {
        super(message, cause);
        this.httpStatus = httpStatus;
        this.errorCode = errorCode != null ? errorCode : "INTERNAL_ERROR";
    }

    public static BackendException serviceUnavailable(String serviceName, Throwable cause) {
        return new BackendException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "SERVICE_UNAVAILABLE",
                String.format("Unable to communicate with %s. Please try again shortly.", serviceName),
                cause
        );
    }

    public HttpStatus getHttpStatus() {
        return httpStatus;
    }

    public String getErrorCode() {
        return errorCode;
    }
}
