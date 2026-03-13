package com.site24x7.labs.chaos.fault.jdbc;

import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.engine.ChaosEngine;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

import javax.sql.DataSource;

/**
 * Evaluates JDBC fault rules and injects faults into database operations.
 * <p>
 * Fault types handled:
 * - jdbc_exception: throw a SQLException before the database operation
 * - jdbc_latency: inject delay before the database operation
 * - jdbc_connection_pool_drain: hold open connections to exhaust the pool
 */
public class JdbcFaultInjector {

    private static final Logger log = LoggerFactory.getLogger(JdbcFaultInjector.class);

    private final ChaosEngine engine;
    private final AtomicBoolean drainActive = new AtomicBoolean(false);
    private volatile DataSource realDataSource;

    public JdbcFaultInjector(ChaosEngine engine) {
        this.engine = engine;
    }

    /**
     * Set the real (unwrapped) DataSource for connection pool drain.
     * Called by ChaosDataSourceProxy during construction.
     */
    public void setRealDataSource(DataSource realDataSource) {
        this.realDataSource = realDataSource;
    }

    /**
     * Evaluate and apply JDBC faults before a database operation.
     * Called from the ChaosStatement proxy before executing SQL.
     * 
     * @throws SQLException if a JDBC exception fault is triggered
     */
    public void applyFault() throws SQLException {
        if (!engine.isEnabled()) {
            return;
        }

        List<FaultRuleConfig> rules = engine.findMatchingRules("jdbc_", null);

        for (FaultRuleConfig rule : rules) {
            if (!engine.shouldFire(rule)) {
                continue;
            }

            switch (rule.getFaultType()) {
                case "jdbc_exception" -> applyJdbcException(rule);
                case "jdbc_latency" -> applyJdbcLatency(rule);
                case "jdbc_connection_pool_drain" -> applyConnectionPoolDrain(rule);
                default -> log.warn("Unknown JDBC fault type: {}", rule.getFaultType());
            }
        }
    }

    private void applyJdbcException(FaultRuleConfig rule) throws SQLException {
        Map<String, Object> config = rule.getConfig();
        String message = getConfigString(config, "message", "Injected JDBC fault");
        String sqlState = getConfigString(config, "sql_state", "08001");

        log.debug("Injecting JDBC exception: {} (state: {})", message, sqlState);

        throw new SQLException(message, sqlState);
    }

    private void applyJdbcLatency(FaultRuleConfig rule) {
        Map<String, Object> config = rule.getConfig();
        long delayMs = getConfigLong(config, "delay_ms", 2000);

        log.debug("Injecting JDBC latency: {}ms", delayMs);

        try {
            Thread.sleep(delayMs);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Drain the connection pool by holding open connections in background threads.
     * Only one drain can be active at a time.
     */
    private void applyConnectionPoolDrain(FaultRuleConfig rule) {
        if (realDataSource == null) {
            log.warn("Cannot drain connection pool: real DataSource not set");
            return;
        }

        Map<String, Object> config = rule.getConfig();
        int holdCount = getConfigInt(config, "hold_count", 5);
        long holdDurationMs = getConfigLong(config, "hold_duration_ms", 30000);

        // Enforce safety limits
        holdCount = Math.min(Math.max(holdCount, 1), 20);
        holdDurationMs = Math.min(Math.max(holdDurationMs, 1000), 60000);

        if (!drainActive.compareAndSet(false, true)) {
            log.debug("Connection pool drain already active, skipping");
            return;
        }

        log.info("Injecting connection pool drain: {} connections held for {}ms", holdCount, holdDurationMs);

        final int hc = holdCount;
        final long hd = holdDurationMs;
        Thread orchestrator = new Thread(() -> {
            List<Connection> heldConnections = new ArrayList<>();
            try {
                // Acquire connections from the real pool
                for (int i = 0; i < hc; i++) {
                    try {
                        Connection conn = realDataSource.getConnection();
                        heldConnections.add(conn);
                        log.debug("Connection pool drain: acquired connection {}/{}", i + 1, hc);
                    } catch (SQLException e) {
                        log.debug("Connection pool drain: failed to acquire connection {}/{}: {}",
                                i + 1, hc, e.getMessage());
                        break; // Pool is already exhausted
                    }
                }

                log.info("Connection pool drain: holding {} connections for {}ms",
                        heldConnections.size(), hd);

                // Hold the connections
                Thread.sleep(hd);

            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } finally {
                // Release all held connections
                for (Connection conn : heldConnections) {
                    try {
                        conn.close();
                    } catch (SQLException e) {
                        log.debug("Error closing drained connection: {}", e.getMessage());
                    }
                }
                drainActive.set(false);
                log.info("Connection pool drain: released {} connections", heldConnections.size());
            }
        }, "chaos-connection-pool-drain");
        orchestrator.setDaemon(true);
        orchestrator.start();
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
