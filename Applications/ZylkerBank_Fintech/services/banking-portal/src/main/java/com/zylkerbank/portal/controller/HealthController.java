package com.zylkerbank.portal.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import javax.sql.DataSource;
import java.sql.Connection;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class HealthController {

    private static final Logger log = LoggerFactory.getLogger(HealthController.class);

    private final DataSource dataSource;
    private final RestTemplate restTemplate;
    private final String ledgerUrl;
    private final String gatewayUrl;
    private final String aiUrl;

    public HealthController(
            DataSource dataSource,
            RestTemplate restTemplate,
            @Value("${services.ledger.url:http://localhost:8081}") String ledgerUrl,
            @Value("${services.gateway.url:http://localhost:8082}") String gatewayUrl,
            @Value("${services.ai.url:http://localhost:8083}") String aiUrl) {
        this.dataSource = dataSource;
        this.restTemplate = restTemplate;
        this.ledgerUrl = ledgerUrl.replaceAll("/+$", "");
        this.gatewayUrl = gatewayUrl.replaceAll("/+$", "");
        this.aiUrl = aiUrl.replaceAll("/+$", "");
    }

    @GetMapping("/health")
    public ResponseEntity<Map<String, Object>> health() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("service", "banking-portal");
        body.put("timestamp", Instant.now().toString());

        Map<String, String> dependencies = new LinkedHashMap<>();

        // 1. Check database connectivity
        try (Connection conn = dataSource.getConnection()) {
            dependencies.put("database", conn.isValid(2) ? "UP" : "DEGRADED");
        } catch (Exception e) {
            dependencies.put("database", "DOWN");
        }

        // 2. Check downstream services (optional, report state without failing)
        dependencies.put("ledger", checkService(ledgerUrl + "/health"));
        dependencies.put("gateway", checkService(gatewayUrl + "/health"));
        dependencies.put("ai", checkService(aiUrl + "/health"));

        body.put("dependencies", dependencies);

        // Health always returns 200 per contracts
        return ResponseEntity.ok(body);
    }

    private String checkService(String healthUrl) {
        try {
            ResponseEntity<String> res = restTemplate.getForEntity(healthUrl, String.class);
            return res.getStatusCode().is2xxSuccessful() ? "UP" : "DEGRADED";
        } catch (Exception e) {
            return "DOWN";
        }
    }
}
