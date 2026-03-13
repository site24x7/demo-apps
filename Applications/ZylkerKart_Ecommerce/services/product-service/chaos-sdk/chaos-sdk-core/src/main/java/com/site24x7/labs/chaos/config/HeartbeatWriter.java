package com.site24x7.labs.chaos.config;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.net.InetAddress;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Periodically writes a {@code {appName}.heartbeat.json} file so the agent
 * can detect that this SDK is installed and running.
 *
 * <p>The heartbeat file contains:
 * <ul>
 *   <li>{@code app_name} – matches the config filename stem</li>
 *   <li>{@code sdk_version}</li>
 *   <li>{@code sdk_language} – always {@code "java"}</li>
 *   <li>{@code framework} – e.g. {@code "spring-boot"}</li>
 *   <li>{@code framework_version}</li>
 *   <li>{@code pid}</li>
 *   <li>{@code hostname}</li>
 *   <li>{@code timestamp} – ISO-8601 UTC</li>
 * </ul>
 */
public class HeartbeatWriter implements Runnable {

    private static final Logger log = LoggerFactory.getLogger(HeartbeatWriter.class);
    private static final Gson GSON = new GsonBuilder().setPrettyPrinting().create();
    private static final long DEFAULT_INTERVAL_MS = 30_000;

    private final Path heartbeatPath;
    private final String appName;
    private final String sdkVersion;
    private final String framework;
    private final String frameworkVersion;
    private final long intervalMs;
    private volatile boolean running = true;

    public HeartbeatWriter(String configDir, String appName, String sdkVersion,
                           String framework, String frameworkVersion) {
        this(configDir, appName, sdkVersion, framework, frameworkVersion, DEFAULT_INTERVAL_MS);
    }

    public HeartbeatWriter(String configDir, String appName, String sdkVersion,
                           String framework, String frameworkVersion, long intervalMs) {
        this.heartbeatPath = Paths.get(configDir, appName + ".heartbeat.json");
        this.appName = appName;
        this.sdkVersion = sdkVersion;
        this.framework = framework;
        this.frameworkVersion = frameworkVersion;
        this.intervalMs = intervalMs;
    }

    @Override
    public void run() {
        log.info("HeartbeatWriter started, path: {}", heartbeatPath);
        while (running) {
            try {
                writeHeartbeat();
                Thread.sleep(intervalMs);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            } catch (Exception e) {
                log.warn("Error writing heartbeat file: {}", e.getMessage());
                try {
                    Thread.sleep(intervalMs);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }
        // Clean up heartbeat file on shutdown
        try {
            Files.deleteIfExists(heartbeatPath);
        } catch (IOException ignored) {
        }
        log.info("HeartbeatWriter stopped");
    }

    private void writeHeartbeat() throws IOException {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("app_name", appName);
        data.put("sdk_version", sdkVersion);
        data.put("sdk_language", "java");
        data.put("framework", framework);
        data.put("framework_version", frameworkVersion);
        data.put("pid", ProcessHandle.current().pid());
        data.put("hostname", getHostname());
        data.put("timestamp", DateTimeFormatter.ISO_INSTANT.format(Instant.now().atOffset(ZoneOffset.UTC)));

        String json = GSON.toJson(data);

        // Atomic write: write to tmp then rename
        Path tmpPath = heartbeatPath.resolveSibling(heartbeatPath.getFileName() + ".tmp");
        Files.writeString(tmpPath, json);
        Files.move(tmpPath, heartbeatPath, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
    }

    private static String getHostname() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown";
        }
    }

    public void stop() {
        running = false;
    }
}
