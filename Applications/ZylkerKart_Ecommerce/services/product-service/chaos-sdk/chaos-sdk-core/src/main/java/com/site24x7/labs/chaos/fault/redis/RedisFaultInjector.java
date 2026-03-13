package com.site24x7.labs.chaos.fault.redis;

import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.engine.ChaosEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Map;

/**
 * Evaluates Redis fault rules and injects faults into Redis operations.
 * <p>
 * This class lives in the core module and has NO Spring Data Redis dependency.
 * The Spring Boot modules provide the actual RedisConnectionFactory proxy that calls this injector.
 * <p>
 * Fault types handled:
 * - redis_exception: throw an exception before the Redis operation
 * - redis_latency: inject delay before the Redis operation
 */
public class RedisFaultInjector {

    private static final Logger log = LoggerFactory.getLogger(RedisFaultInjector.class);

    private final ChaosEngine engine;

    public RedisFaultInjector(ChaosEngine engine) {
        this.engine = engine;
    }

    /**
     * Evaluate and apply Redis faults before a Redis operation.
     * Called from the RedisConnectionFactory proxy before executing commands.
     *
     * @throws RuntimeException if a Redis exception fault is triggered
     */
    public void applyFault() {
        if (!engine.isEnabled()) {
            return;
        }

        List<FaultRuleConfig> rules = engine.findMatchingRules("redis_", null);

        for (FaultRuleConfig rule : rules) {
            if (!engine.shouldFire(rule)) {
                continue;
            }

            switch (rule.getFaultType()) {
                case "redis_exception" -> applyRedisException(rule);
                case "redis_latency" -> applyRedisLatency(rule);
                default -> log.warn("Unknown Redis fault type: {}", rule.getFaultType());
            }
        }
    }

    private void applyRedisException(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        String className = getConfigString(config, "exception_class",
                "org.springframework.data.redis.RedisConnectionFailureException");
        String message = getConfigString(config, "message", "Injected Redis fault");

        log.debug("Injecting Redis exception: {} - {}", className, message);

        try {
            Class<?> exClass = Class.forName(className);
            if (RuntimeException.class.isAssignableFrom(exClass)) {
                try {
                    throw (RuntimeException) exClass.getConstructor(String.class).newInstance(message);
                } catch (NoSuchMethodException e) {
                    // Some Redis exceptions take (String, Throwable)
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

    private void applyRedisLatency(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        long delayMs = getConfigLong(config, "delay_ms", 2000);

        log.debug("Injecting Redis latency: {}ms", delayMs);

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
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
}
