package com.site24x7.labs.chaos.engine;

import com.site24x7.labs.chaos.config.ChaosConfig;
import com.site24x7.labs.chaos.config.ChaosProperties;
import com.site24x7.labs.chaos.config.ConfigFileWatcher;
import com.site24x7.labs.chaos.config.FaultRuleConfig;
import com.site24x7.labs.chaos.config.HeartbeatWriter;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.ThreadLocalRandom;
import java.util.function.Consumer;

/**
 * Central chaos engine that coordinates fault injection.
 * 
 * Thread-safety model:
 * - activeRules is volatile and replaced atomically with List.copyOf()
 * - Request-handling threads read the list without synchronization
 * - The ConfigFileWatcher thread writes the list
 */
public class ChaosEngine {

    private static final Logger log = LoggerFactory.getLogger(ChaosEngine.class);

    private final ChaosProperties properties;
    private volatile List<FaultRuleConfig> activeRules = Collections.emptyList();
    private final List<Runnable> configUpdateListeners = new ArrayList<>();
    private ConfigFileWatcher watcher;
    private Thread watcherThread;
    private HeartbeatWriter heartbeatWriter;
    private Thread heartbeatThread;

    public ChaosEngine(ChaosProperties properties) {
        this.properties = properties;
    }

    /**
     * Start the config file watcher daemon thread.
     */
    public void start() {
        if (!properties.isEnabled()) {
            log.info("Chaos SDK is disabled");
            return;
        }

        String configFile = properties.getConfigFile();
        if (configFile == null || configFile.isEmpty()) {
            log.warn("Chaos SDK config file path not set, fault injection disabled");
            return;
        }

        watcher = new ConfigFileWatcher(configFile, properties.getPollIntervalMs(), this::onConfigUpdate);
        watcherThread = new Thread(watcher, "chaos-config-watcher");
        watcherThread.setDaemon(true);
        watcherThread.start();

        // Start heartbeat writer so the agent can detect SDK presence
        heartbeatWriter = new HeartbeatWriter(
                properties.getConfigDir(),
                properties.getAppName(),
                properties.getSdkVersion(),
                properties.getFramework(),
                properties.getFrameworkVersion()
        );
        heartbeatThread = new Thread(heartbeatWriter, "chaos-heartbeat-writer");
        heartbeatThread.setDaemon(true);
        heartbeatThread.start();

        log.info("ChaosEngine started for app '{}', config file: {}", properties.getAppName(), configFile);
    }

    /**
     * Stop the config file watcher.
     */
    public void stop() {
        if (heartbeatWriter != null) {
            heartbeatWriter.stop();
        }
        if (heartbeatThread != null) {
            heartbeatThread.interrupt();
        }
        if (watcher != null) {
            watcher.stop();
        }
        if (watcherThread != null) {
            watcherThread.interrupt();
        }
        log.info("ChaosEngine stopped");
    }

    /**
     * Called by the ConfigFileWatcher when the config file changes.
     */
    private void onConfigUpdate(ChaosConfig config) {
        List<FaultRuleConfig> rules = config.getRules();
        if (rules == null) {
            activeRules = Collections.emptyList();
        } else {
            // Only keep enabled rules
            activeRules = List.copyOf(
                rules.stream().filter(FaultRuleConfig::isEnabled).toList()
            );
        }
        log.debug("Active rules updated: {} rules", activeRules.size());

        // Notify listeners (e.g., ResourceFaultInjector)
        for (Runnable listener : configUpdateListeners) {
            try {
                listener.run();
            } catch (Exception e) {
                log.error("Config update listener error: {}", e.getMessage());
            }
        }
    }

    /**
     * Register a listener that is called whenever the active rules are updated.
     * Used by ResourceFaultInjector to trigger resource faults on config changes.
     */
    public void addConfigUpdateListener(Runnable listener) {
        configUpdateListeners.add(listener);
    }

    /**
     * Find matching fault rules for the given fault type and optional URL.
     * Returns the list of matching rules (caller decides what to do).
     */
    public List<FaultRuleConfig> findMatchingRules(String faultTypePrefix, String requestUrl) {
        if (!properties.isEnabled() || activeRules.isEmpty()) {
            return Collections.emptyList();
        }

        return activeRules.stream()
                .filter(r -> r.getFaultType().startsWith(faultTypePrefix))
                .filter(r -> matchesUrl(r.getUrlPattern(), requestUrl))
                .toList();
    }

    /**
     * Check if the fault should fire based on probability.
     */
    public boolean shouldFire(FaultRuleConfig rule) {
        if (rule.getProbability() >= 1.0) {
            return true;
        }
        if (rule.getProbability() <= 0.0) {
            return false;
        }
        return ThreadLocalRandom.current().nextDouble() < rule.getProbability();
    }

    /**
     * URL pattern matching. Empty pattern matches everything.
     * Supports simple glob: * matches any segment, ** matches any path.
     */
    private boolean matchesUrl(String pattern, String url) {
        if (pattern == null || pattern.isEmpty()) {
            return true; // empty pattern matches all
        }
        if (url == null || url.isEmpty()) {
            return true;
        }
        // Simple glob to regex conversion
        String regex = pattern
                .replace(".", "\\.")
                .replace("**", "##DOUBLESTAR##")
                .replace("*", "[^/]*")
                .replace("##DOUBLESTAR##", ".*");
        try {
            return url.matches(regex);
        } catch (Exception e) {
            log.warn("Invalid URL pattern '{}': {}", pattern, e.getMessage());
            return false;
        }
    }

    public boolean isEnabled() {
        return properties.isEnabled();
    }

    public List<FaultRuleConfig> getActiveRules() {
        return activeRules;
    }
}
