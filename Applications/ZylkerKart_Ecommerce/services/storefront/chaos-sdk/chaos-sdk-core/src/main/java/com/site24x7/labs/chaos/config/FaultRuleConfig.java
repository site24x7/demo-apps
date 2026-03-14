package com.site24x7.labs.chaos.config;

import com.google.gson.annotations.SerializedName;
import java.util.Map;

/**
 * A single fault injection rule as read from the config file.
 */
public class FaultRuleConfig {
    private String id;

    @SerializedName("fault_type")
    private String faultType;

    private boolean enabled;
    private double probability;
    private Map<String, Object> config;

    @SerializedName("url_pattern")
    private String urlPattern;

    // Getters
    public String getId() { return id; }
    public String getFaultType() { return faultType; }
    public boolean isEnabled() { return enabled; }
    public double getProbability() { return probability; }
    public Map<String, Object> getConfig() { return config; }
    public String getUrlPattern() { return urlPattern; }

    @Override
    public String toString() {
        return "FaultRuleConfig{id='" + id + "', faultType='" + faultType + "', enabled=" + enabled + ", probability=" + probability + "}";
    }
}
