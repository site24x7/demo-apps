package com.site24x7.labs.chaos.config;

import com.google.gson.Gson;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.function.Consumer;

/**
 * Daemon thread that polls a JSON config file for changes.
 * When a change is detected (via file modification time), the file is re-parsed
 * and the new config is passed to the registered listener.
 */
public class ConfigFileWatcher implements Runnable {

    private static final Logger log = LoggerFactory.getLogger(ConfigFileWatcher.class);
    private static final Gson GSON = new Gson();

    private final Path configPath;
    private final long pollIntervalMs;
    private final Consumer<ChaosConfig> listener;
    private volatile boolean running = true;
    private long lastModifiedTime = 0;

    public ConfigFileWatcher(String configFile, long pollIntervalMs, Consumer<ChaosConfig> listener) {
        this.configPath = Paths.get(configFile);
        this.pollIntervalMs = pollIntervalMs;
        this.listener = listener;
    }

    @Override
    public void run() {
        log.info("ConfigFileWatcher started, watching: {}", configPath);
        while (running) {
            try {
                checkForChanges();
                Thread.sleep(pollIntervalMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            } catch (Exception e) {
                log.warn("Error checking config file: {}", e.getMessage());
                try {
                    Thread.sleep(pollIntervalMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        log.info("ConfigFileWatcher stopped");
    }

    private void checkForChanges() {
        if (!Files.exists(configPath)) {
            // File doesn't exist — either agent hasn't written it yet,
            // or agent deleted it (all rules removed). If we had rules
            // before, clear them by sending an empty config.
            if (lastModifiedTime > 0) {
                lastModifiedTime = 0;
                log.info("Config file removed, clearing all rules");
                try {
                    ChaosConfig empty = new ChaosConfig();
                    listener.accept(empty);
                } catch (Exception e) {
                    log.warn("Config update listener error on clear: {}", e.getMessage());
                }
            }
            return;
        }

        try {
            long currentModTime = Files.getLastModifiedTime(configPath).toMillis();
            if (currentModTime > lastModifiedTime) {
                lastModifiedTime = currentModTime;
                String content = Files.readString(configPath);
                ChaosConfig config = GSON.fromJson(content, ChaosConfig.class);
                if (config != null && config.getRules() != null) {
                    log.info("Config file changed, loaded {} rules", config.getRules().size());
                    listener.accept(config);
                }
            }
        } catch (IOException e) {
            log.warn("Failed to read config file: {}", e.getMessage());
        } catch (Exception e) {
            log.warn("Failed to parse config file: {}", e.getMessage());
        }
    }

    public void stop() {
        running = false;
    }
}
