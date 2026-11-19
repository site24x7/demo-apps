package com.zylkerbank.portal.exception;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.ControllerAdvice;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.servlet.ModelAndView;
import org.springframework.web.servlet.resource.NoResourceFoundException;

import java.util.Map;

@ControllerAdvice
public class GlobalExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    private boolean isApiRequest(HttpServletRequest request) {
        String uri = request.getRequestURI();
        if (uri != null && uri.startsWith("/api/")) {
            return true;
        }
        String accept = request.getHeader("Accept");
        return accept != null && accept.contains(MediaType.APPLICATION_JSON_VALUE);
    }

    @ExceptionHandler(BackendException.class)
    public Object handleBackendException(BackendException ex, HttpServletRequest request) {
        log.warn("BackendException on {}: [{}] {}", request.getRequestURI(), ex.getErrorCode(), ex.getMessage());

        if (isApiRequest(request)) {
            return ResponseEntity.status(ex.getHttpStatus()).body(Map.of(
                    "error", ex.getErrorCode(),
                    "message", ex.getMessage()
            ));
        }

        ModelAndView mav = new ModelAndView("error");
        mav.setStatus(ex.getHttpStatus());
        mav.addObject("errorCode", ex.getErrorCode());
        mav.addObject("errorMessage", ex.getMessage());
        mav.addObject("httpStatus", ex.getHttpStatus().value());
        return mav;
    }

    @ExceptionHandler(NoResourceFoundException.class)
    public Object handleNotFound(NoResourceFoundException ex, HttpServletRequest request) {
        if (isApiRequest(request)) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).body(Map.of(
                    "error", "NOT_FOUND",
                    "message", "Resource not found: " + request.getRequestURI()
            ));
        }
        ModelAndView mav = new ModelAndView("error-404");
        mav.setStatus(HttpStatus.NOT_FOUND);
        return mav;
    }

    @ExceptionHandler(Exception.class)
    public Object handleGenericException(Exception ex, HttpServletRequest request) {
        log.error("Unhandled exception on {}", request.getRequestURI(), ex);

        if (isApiRequest(request)) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(Map.of(
                    "error", "INTERNAL_SERVER_ERROR",
                    "message", "An unexpected error occurred. Please try again."
            ));
        }

        ModelAndView mav = new ModelAndView("error");
        mav.setStatus(HttpStatus.INTERNAL_SERVER_ERROR);
        mav.addObject("errorCode", "SERVER_ERROR");
        mav.addObject("errorMessage", "An unexpected system error occurred. Please try again.");
        mav.addObject("httpStatus", 500);
        return mav;
    }
}
