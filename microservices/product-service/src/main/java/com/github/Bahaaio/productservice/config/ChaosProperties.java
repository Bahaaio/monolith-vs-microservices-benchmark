package com.github.Bahaaio.productservice.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "chaos")
public class ChaosProperties {

    private boolean enabled = false;
    private String mode = "none";
    private int faultPercent = 0;
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

    public int getFaultPercent() {
        return faultPercent;
    }

    public void setFaultPercent(int faultPercent) {
        this.faultPercent = faultPercent;
    }

    public int getLatencyMs() {
        return latencyMs;
    }

    public void setLatencyMs(int latencyMs) {
        this.latencyMs = latencyMs;
    }
}
