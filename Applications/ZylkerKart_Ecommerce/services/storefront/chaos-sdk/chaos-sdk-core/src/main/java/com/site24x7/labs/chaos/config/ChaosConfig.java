package com.site24x7.labs.chaos.config;

import com.google.gson.annotations.SerializedName;
import java.util.ArrayList;
import java.util.List;

/**
 * Top-level configuration read from the JSON config file.
 * Written by the Site24x7 Labs agent, read by this SDK.
 */
public class ChaosConfig {
    private int version;

    @SerializedName("app_name")
    private String appName;

    @SerializedName("environment_id")
    private String environmentId;

    @SerializedName("updated_at")
    private String updatedAt;

    private List<FaultRuleConfig> rules = new ArrayList<>();

    // Getters
    public int getVersion() { return version; }
    public String getAppName() { return appName; }
    public String getEnvironmentId() { return environmentId; }
    public String getUpdatedAt() { return updatedAt; }
    public List<FaultRuleConfig> getRules() { return rules; }

    @Override
    public String toString() {
        return "ChaosConfig{appName='" + appName + "', version=" + version + ", rules=" + (rules != null ? rules.size() : 0) + "}";
    }
}
