package com.site24x7.labs.chaos.spring;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Spring Boot configuration properties for the Chaos SDK.
 * 
 * Usage in application.yml:
 * <pre>
 * chaos:
 *   enabled: true
 *   app-name: order-service
 *   config-file: /var/site24x7-labs/faults/order-service.json
 *   poll-interval-ms: 2000
 * </pre>
 */
@ConfigurationProperties(prefix = "chaos")
public class ChaosProperties {
    
    /** Enable/disable fault injection. Defaults to true. */
    private boolean enabled = true;
    
    /** Application name. Must match the app_name registered in Site24x7 Labs. */
    private String appName;
    
    /** Path to the JSON config file written by the agent. */
    private String configFile;
    
    /** Interval in milliseconds for polling the config file. Defaults to 2000. */
    private long pollIntervalMs = 2000;

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getAppName() { return appName; }
    public void setAppName(String appName) { this.appName = appName; }

    public String getConfigFile() { return configFile; }
    public void setConfigFile(String configFile) { this.configFile = configFile; }

    public long getPollIntervalMs() { return pollIntervalMs; }
    public void setPollIntervalMs(long pollIntervalMs) { this.pollIntervalMs = pollIntervalMs; }
}
