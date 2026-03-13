package com.site24x7.labs.chaos.config;

/**
 * SDK configuration properties. Typically set via application.yml:
 * 
 * chaos:
 *   enabled: true
 *   app-name: order-service
 *   config-file: /var/site24x7-labs/faults/order-service.json
 *   poll-interval-ms: 2000
 */
public class ChaosProperties {
    private boolean enabled = true;
    private String appName;
    private String configFile;
    private long pollIntervalMs = 2000;
    private String sdkVersion = "1.0.0";
    private String framework = "";
    private String frameworkVersion = "";

    public boolean isEnabled() { return enabled; }
    public void setEnabled(boolean enabled) { this.enabled = enabled; }

    public String getAppName() { return appName; }
    public void setAppName(String appName) { this.appName = appName; }

    public String getConfigFile() { return configFile; }
    public void setConfigFile(String configFile) { this.configFile = configFile; }

    public long getPollIntervalMs() { return pollIntervalMs; }
    public void setPollIntervalMs(long pollIntervalMs) { this.pollIntervalMs = pollIntervalMs; }

    public String getSdkVersion() { return sdkVersion; }
    public void setSdkVersion(String sdkVersion) { this.sdkVersion = sdkVersion; }

    public String getFramework() { return framework; }
    public void setFramework(String framework) { this.framework = framework; }

    public String getFrameworkVersion() { return frameworkVersion; }
    public void setFrameworkVersion(String frameworkVersion) { this.frameworkVersion = frameworkVersion; }

    /**
     * Derive the config directory from the config file path.
     * E.g. "/var/site24x7-labs/faults/order-service.json" → "/var/site24x7-labs/faults"
     */
    public String getConfigDir() {
        if (configFile == null || configFile.isEmpty()) {
            return "/var/site24x7-labs/faults";
        }
        int lastSlash = configFile.lastIndexOf('/');
        if (lastSlash > 0) {
            return configFile.substring(0, lastSlash);
        }
        return ".";
    }
}
