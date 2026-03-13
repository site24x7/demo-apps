package com.site24x7.labs.chaos.fault.http;

import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.engine.ChaosEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.OutputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Map;

/**
 * Evaluates HTTP fault rules and injects faults into servlet requests.
 * Uses reflection to work with both javax.servlet and jakarta.servlet.
 */
public class HttpFaultInjector {

    private static final Logger log = LoggerFactory.getLogger(HttpFaultInjector.class);

    private final ChaosEngine engine;

    public HttpFaultInjector(ChaosEngine engine) {
        this.engine = engine;
    }

    /**
     * Evaluate and apply HTTP faults for the current request.
     * 
     * @param request  the servlet request (javax or jakarta)
     * @param response the servlet response (javax or jakarta)
     * @return true if a fault was injected (caller should stop the filter chain), false otherwise
     */
    public boolean applyFault(Object request, Object response) {
        if (!engine.isEnabled()) {
            return false;
        }

        String requestUri = getRequestUri(request);
        List<FaultRuleConfig> rules = engine.findMatchingRules("http_", requestUri);

        for (FaultRuleConfig rule : rules) {
            if (!engine.shouldFire(rule)) {
                continue;
            }

            try {
                switch (rule.getFaultType()) {
                    case "http_exception" -> {
                        applyHttpException(rule);
                        return true;
                    }
                    case "http_latency" -> {
                        applyHttpLatency(rule);
                        // Latency is additive — don't stop the chain
                        return false;
                    }
                    case "http_error_response" -> {
                        applyHttpErrorResponse(rule, response);
                        return true;
                    }
                    case "http_connection_reset" -> {
                        applyHttpConnectionReset(response);
                        return true;
                    }
                    case "http_slow_body" -> {
                        applyHttpSlowBody(rule, response);
                        return true;
                    }
                    default -> log.warn("Unknown HTTP fault type: {}", rule.getFaultType());
                }
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                log.error("Failed to apply fault {}: {}", rule.getId(), e.getMessage());
            }
        }

        return false;
    }

    private void applyHttpException(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        String className = getConfigString(config, "exception_class", "java.lang.RuntimeException");
        String message = getConfigString(config, "message", "Injected fault");

        log.debug("Injecting HTTP exception: {} - {}", className, message);

        try {
            Class<?> exClass = Class.forName(className);
            if (RuntimeException.class.isAssignableFrom(exClass)) {
                throw (RuntimeException) exClass.getConstructor(String.class).newInstance(message);
            } else if (Exception.class.isAssignableFrom(exClass)) {
                // Wrap checked exceptions in RuntimeException
                Exception checked = (Exception) exClass.getConstructor(String.class).newInstance(message);
                throw new RuntimeException(checked);
            } else {
                throw new RuntimeException(message);
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new RuntimeException(message, e);
        }
    }

    private void applyHttpLatency(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        long delayMs = getConfigLong(config, "delay_ms", 1000);

        log.debug("Injecting HTTP latency: {}ms", delayMs);

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private void applyHttpErrorResponse(FaultRuleConfig rule, Object response) throws Exception {
        Map<String, Object> config = rule.getConfig();
        int statusCode = getConfigInt(config, "status_code", 500);
        String body = getConfigString(config, "body", "Internal Server Error");

        log.debug("Injecting HTTP error response: {} - {}", statusCode, body);

        // Use reflection: response.setStatus(statusCode)
        Method setStatus = response.getClass().getMethod("setStatus", int.class);
        setStatus.invoke(response, statusCode);

        // response.setContentType("text/plain")
        Method setContentType = response.getClass().getMethod("setContentType", String.class);
        setContentType.invoke(response, "text/plain");

        // response.getOutputStream().write(body.getBytes())
        Method getOutputStream = response.getClass().getMethod("getOutputStream");
        Object outputStream = getOutputStream.invoke(response);
        Method write = outputStream.getClass().getMethod("write", byte[].class);
        write.invoke(outputStream, body.getBytes(StandardCharsets.UTF_8));

        // Flush
        try {
            Method flush = outputStream.getClass().getMethod("flush");
            flush.invoke(outputStream);
        } catch (NoSuchMethodException ignored) {
            // Some implementations may not have flush
        }
    }

    private void applyHttpConnectionReset(Object response) throws Exception {
        log.debug("Injecting HTTP connection reset (closing output stream abruptly)");

        // Get the raw output stream and close it immediately to simulate a connection reset
        Method getOutputStream = response.getClass().getMethod("getOutputStream");
        Object outputStream = getOutputStream.invoke(response);

        // Close the output stream abruptly — the client will see a connection reset
        Method close = outputStream.getClass().getMethod("close");
        close.invoke(outputStream);
    }

    private void applyHttpSlowBody(FaultRuleConfig rule, Object response) throws Exception {
        Map<String, Object> config = rule.getConfig();
        long delayMs = getConfigLong(config, "delay_ms", 200);
        int chunkSize = getConfigInt(config, "chunk_size_bytes", 64);

        log.debug("Injecting HTTP slow body: {}ms delay, {} byte chunks", delayMs, chunkSize);

        // Set response headers so the client knows content is coming
        Method setStatus = response.getClass().getMethod("setStatus", int.class);
        setStatus.invoke(response, 200);

        Method setContentType = response.getClass().getMethod("setContentType", String.class);
        setContentType.invoke(response, "text/plain");

        // Get the output stream
        Method getOutputStream = response.getClass().getMethod("getOutputStream");
        Object outputStream = getOutputStream.invoke(response);
        Method write = outputStream.getClass().getMethod("write", byte[].class);
        Method flush = null;
        try {
            flush = outputStream.getClass().getMethod("flush");
        } catch (NoSuchMethodException ignored) {
            // Proceed without flush
        }

        // Build a chunk of dots
        byte[] chunk = new byte[chunkSize];
        java.util.Arrays.fill(chunk, (byte) '.');

        // Write chunks slowly — enough chunks to keep going for a while
        // Total body ≈ 32 chunks, each delayed
        int totalChunks = 32;
        for (int i = 0; i < totalChunks; i++) {
            try {
                write.invoke(outputStream, chunk);
                if (flush != null) {
                    flush.invoke(outputStream);
                }
                Thread.sleep(delayMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            } catch (Exception e) {
                // Client may have disconnected
                log.debug("Slow body write failed (client disconnect?): {}", e.getMessage());
                break;
            }
        }
    }

    private String getRequestUri(Object request) {
        try {
            Method getRequestURI = request.getClass().getMethod("getRequestURI");
            return (String) getRequestURI.invoke(request);
        } catch (Exception e) {
            return "";
        }
    }

    private String getConfigString(Map<String, Object> config, String key, String defaultValue) {
        if (config == null) return defaultValue;
        Object val = config.get(key);
        return val != null ? val.toString() : defaultValue;
    }

    private long getConfigLong(Map<String, Object> config, String key, long defaultValue) {
        if (config == null) return defaultValue;
        Object val = config.get(key);
        if (val instanceof Number) return ((Number) val).longValue();
        if (val instanceof String) {
            try { return Long.parseLong((String) val); } catch (NumberFormatException e) { return defaultValue; }
        }
        return defaultValue;
    }

    private int getConfigInt(Map<String, Object> config, String key, int defaultValue) {
        if (config == null) return defaultValue;
        Object val = config.get(key);
        if (val instanceof Number) return ((Number) val).intValue();
        if (val instanceof String) {
            try { return Integer.parseInt((String) val); } catch (NumberFormatException e) { return defaultValue; }
        }
        return defaultValue;
    }
}
