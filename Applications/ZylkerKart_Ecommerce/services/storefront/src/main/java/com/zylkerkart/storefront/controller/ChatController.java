package com.zylkerkart.storefront.controller;

import com.zylkerkart.storefront.service.ApiGateway;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * Proxies chat requests to the AI assistant microservice.
 */
@RestController
public class ChatController {

    private final ApiGateway api;

    public ChatController(ApiGateway api) {
        this.api = api;
    }

    @PostMapping(value = "/api/chat", produces = "application/json")
    public ResponseEntity<Object> chat(@RequestBody Map<String, Object> body, HttpSession session) {
        Object messageObj = body.get("message");
        if (messageObj == null || messageObj.toString().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "message is required"));
        }

        Map<String, Object> payload = new HashMap<>();
        payload.put("message", messageObj.toString().trim());
        payload.put("session_id", session.getId());

        Object user = session.getAttribute("user");
        if (user instanceof Map<?, ?> userMap && userMap.get("id") != null) {
            payload.put("user_id", userMap.get("id").toString());
        }
        if (body.get("page_context") != null) {
            payload.put("page_context", body.get("page_context").toString());
        }

        Map<String, Object> result = api.post("ai", "/chat", payload);
        int status = (int) result.getOrDefault("status", 500);
        return ResponseEntity.status(status).body(result.get("data"));
    }
}
