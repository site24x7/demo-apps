package com.site24x7.labs.chaos.fault.httpclient;

import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.engine.ChaosEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

/**
 * Evaluates outbound HTTP fault rules for RestTemplate/WebClient calls.
 * <p>
 * This class lives in the core module and has NO Spring dependency.
 * The Spring Boot modules provide the actual interceptor/wrapper that calls this injector.
 * <p>
 * Fault types handled:
 * - http_client_exception: throw an exception before the outbound call
 * - http_client_latency: inject delay before the outbound call
 * - http_client_error_response: return a fake error response (handled by interceptor)
 * - http_client_partial_response: return a truncated response body (simulates TCP reset mid-transfer)
 */
public class HttpClientFaultInjector {

    private static final Logger log = LoggerFactory.getLogger(HttpClientFaultInjector.class);

    private final ChaosEngine engine;

    public HttpClientFaultInjector(ChaosEngine engine) {
        this.engine = engine;
    }

    /**
     * Result of evaluating fault rules for an outbound HTTP request.
     */
    public static class FaultResult {
        private final boolean faultApplied;
        private final String faultType;
        private final int statusCode;
        private final String body;
        private final int truncatePercentage;

        private FaultResult(boolean faultApplied, String faultType, int statusCode, String body, int truncatePercentage) {
            this.faultApplied = faultApplied;
            this.faultType = faultType;
            this.statusCode = statusCode;
            this.body = body;
            this.truncatePercentage = truncatePercentage;
        }

        public static FaultResult none() {
            return new FaultResult(false, null, 0, null, 0);
        }

        public static FaultResult errorResponse(int statusCode, String body) {
            return new FaultResult(true, "http_client_error_response", statusCode, body, 0);
        }

        public static FaultResult partialResponse(int statusCode, String body, int truncatePercentage) {
            return new FaultResult(true, "http_client_partial_response", statusCode, body, truncatePercentage);
        }

        public boolean isFaultApplied() { return faultApplied; }
        public String getFaultType() { return faultType; }
        public int getStatusCode() { return statusCode; }
        public String getBody() { return body; }
        public int getTruncatePercentage() { return truncatePercentage; }
    }

    /**
     * Evaluate outbound HTTP fault rules for the given request URL.
     * Applies exception and latency faults directly, returns error response info
     * so the caller (interceptor) can construct the fake response.
     *
     * @param requestUrl the outbound request URL (for pattern matching)
     * @return FaultResult indicating what happened
     */
    public FaultResult applyFault(String requestUrl) {
        if (!engine.isEnabled()) {
            return FaultResult.none();
        }

        List<FaultRuleConfig> rules = engine.findMatchingRules("http_client_", requestUrl);

        for (FaultRuleConfig rule : rules) {
            if (!engine.shouldFire(rule)) {
                continue;
            }

            try {
                switch (rule.getFaultType()) {
                    case "http_client_exception" -> {
                        applyHttpClientException(rule);
                        // The throw above means we never reach here
                        return FaultResult.none();
                    }
                    case "http_client_latency" -> {
                        applyHttpClientLatency(rule);
                        // Latency is additive — don't stop, continue to real call
                        return FaultResult.none();
                    }
                    case "http_client_error_response" -> {
                        return applyHttpClientErrorResponse(rule);
                    }
                    case "http_client_partial_response" -> {
                        return applyHttpClientPartialResponse(rule);
                    }
                    default -> log.warn("Unknown HTTP client fault type: {}", rule.getFaultType());
                }
            } catch (RuntimeException e) {
                throw e;
            } catch (Exception e) {
                log.error("Failed to apply HTTP client fault {}: {}", rule.getId(), e.getMessage());
            }
        }

        return FaultResult.none();
    }

    private void applyHttpClientException(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        String className = getConfigString(config, "exception_class",
                "org.springframework.web.client.ResourceAccessException");
        String message = getConfigString(config, "message", "Injected outbound fault");

        log.debug("Injecting HTTP client exception: {} - {}", className, message);

        try {
            Class<?> exClass = Class.forName(className);
            if (RuntimeException.class.isAssignableFrom(exClass)) {
                // Try (String) constructor first, then (String, Throwable)
                try {
                    throw (RuntimeException) exClass.getConstructor(String.class).newInstance(message);
                } catch (NoSuchMethodException e) {
                    throw (RuntimeException) exClass.getConstructor(String.class, Throwable.class)
                            .newInstance(message, null);
                }
            } else if (Exception.class.isAssignableFrom(exClass)) {
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

    private void applyHttpClientLatency(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        long delayMs = getConfigLong(config, "delay_ms", 3000);

        log.debug("Injecting HTTP client latency: {}ms", delayMs);

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private FaultResult applyHttpClientErrorResponse(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int statusCode = getConfigInt(config, "status_code", 503);
        String body = getConfigString(config, "body", "Service Unavailable");

        log.debug("Injecting HTTP client error response: {} - {}", statusCode, body);

        return FaultResult.errorResponse(statusCode, body);
    }

    private FaultResult applyHttpClientPartialResponse(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        int statusCode = getConfigInt(config, "status_code", 200);
        String body = getConfigString(config, "body", "{\"data\":[{\"id\":1,\"name\":\"item\"");
        int truncatePct = Math.min(90, Math.max(10, getConfigInt(config, "truncate_percentage", 50)));

        int truncLen = body.length() * truncatePct / 100;
        if (truncLen < 1) {
            truncLen = 1;
        }
        String truncatedBody = body.substring(0, truncLen);

        log.debug("Injecting HTTP client partial response: {}% of body on request", truncatePct);

        return FaultResult.partialResponse(statusCode, truncatedBody, truncatePct);
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
