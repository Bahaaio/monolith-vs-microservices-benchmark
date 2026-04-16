package com.github.Bahaaio.monolith.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "chaos")
public class ChaosProperties {

    private boolean enabled = false;
    private String mode = "none";
    private String faultIds = "";
    private int latencyMs = 0;

    public boolean isEnabled() {
        return enabled;
    }

    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    public String getMode() {
        return mode;
    }

    public void setMode(String mode) {
        this.mode = mode;
    }

    public String getFaultIds() {
        return faultIds;
    }

    public void setFaultIds(String faultIds) {
        this.faultIds = faultIds;
    }

    public int getLatencyMs() {
        return latencyMs;
    }

    public void setLatencyMs(int latencyMs) {
        this.latencyMs = latencyMs;
    }
}
