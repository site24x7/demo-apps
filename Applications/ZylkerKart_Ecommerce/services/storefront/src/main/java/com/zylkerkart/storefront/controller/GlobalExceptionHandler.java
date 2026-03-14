package com.zylkerkart.storefront.controller;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;

/**
 * Global exception handler that catches unhandled exceptions from controllers and
 * Thymeleaf template rendering. Logs the actual root cause (which otherwise gets
 * swallowed by Spring's "response committed already" secondary error) and returns
 * a standalone error page that doesn't use the layout decorator.
 */
@ControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(Exception.class)
    public String handleException(Exception ex, HttpServletRequest request,
                                  HttpServletResponse response) {
        log.error("Unhandled exception on {} {}: {}", request.getMethod(),
                request.getRequestURI(), ex.getMessage(), ex);

        // If the response is already committed (Thymeleaf started streaming HTML),
        // we can't write a new response — just log and return null.
        if (response.isCommitted()) {
            log.warn("Response already committed for {} {} — cannot render error page",
                    request.getMethod(), request.getRequestURI());
            return null;
        }

        response.setStatus(500);
        // Return the standalone error.html (no layout decorator) to avoid cascade crashes
        return "error";
    }
}
