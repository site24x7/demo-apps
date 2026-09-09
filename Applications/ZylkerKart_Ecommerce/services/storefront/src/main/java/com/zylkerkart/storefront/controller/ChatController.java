package com.zylkerkart.storefront.controller;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.zylkerkart.storefront.service.ApiGateway;
import com.zylkerkart.storefront.service.ChatRateLimiter;
import jakarta.servlet.http.HttpSession;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Proxies chat requests to the AI assistant microservice.
 */
@RestController
public class ChatController {

    private final ApiGateway api;
    private final ChatRateLimiter rateLimiter;
    private final RestTemplate aiRestTemplate;
    private final ObjectMapper objectMapper;
    private final String aiServiceUrl;
    private final String aiInternalToken;

    public ChatController(
            ApiGateway api,
            ChatRateLimiter rateLimiter,
            @Qualifier("aiRestTemplate") RestTemplate aiRestTemplate,
            ObjectMapper objectMapper,
            @Value("${services.ai.url}") String aiServiceUrl,
            @Value("${services.ai.internal-token:}") String aiInternalToken) {
        this.api = api;
        this.rateLimiter = rateLimiter;
        this.aiRestTemplate = aiRestTemplate;
        this.objectMapper = objectMapper;
        this.aiServiceUrl = aiServiceUrl;
        this.aiInternalToken = aiInternalToken;
    }

    @PostMapping(value = "/api/chat", produces = "application/json")
    public ResponseEntity<Object> chat(@RequestBody Map<String, Object> body, HttpSession session) {
        Object messageObj = body.get("message");
        if (messageObj == null || messageObj.toString().isBlank()) {
            return ResponseEntity.badRequest().body(Map.of("error", "message is required"));
        }

        if (!rateLimiter.tryAcquire(session.getId())) {
            return ResponseEntity.status(429).body(Map.of(
                    "error", "Too many chat requests. Please wait a moment and try again."));
        }

        Map<String, Object> payload = buildPayload(body, session);
        Map<String, String> headers = Map.of("X-Internal-Token", aiInternalToken == null ? "" : aiInternalToken);
        Map<String, Object> result = api.post("ai", "/chat", payload, null, headers);
        int status = (int) result.getOrDefault("status", 500);
        return ResponseEntity.status(status).body(result.get("data"));
    }

    @PostMapping(value = "/api/chat/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public ResponseEntity<StreamingResponseBody> chatStream(
            @RequestBody Map<String, Object> body, HttpSession session) {
        Object messageObj = body.get("message");
        if (messageObj == null || messageObj.toString().isBlank()) {
            return ResponseEntity.badRequest().build();
        }
        if (!rateLimiter.tryAcquire(session.getId())) {
            StreamingResponseBody err = out -> out.write(
                    "event: error\ndata: {\"error\":\"Too many chat requests\"}\n\n"
                            .getBytes(StandardCharsets.UTF_8));
            return ResponseEntity.status(429).contentType(MediaType.TEXT_EVENT_STREAM).body(err);
        }

        Map<String, Object> payload = buildPayload(body, session);
        StreamingResponseBody stream = outputStream -> proxySse(payload, outputStream);
        return ResponseEntity.ok().contentType(MediaType.TEXT_EVENT_STREAM).body(stream);
    }

    private void proxySse(Map<String, Object> payload, OutputStream outputStream) {
        try {
            aiRestTemplate.execute(
                    aiServiceUrl + "/chat/stream",
                    HttpMethod.POST,
                    request -> {
                        request.getHeaders().setContentType(MediaType.APPLICATION_JSON);
                        request.getHeaders().setAccept(List.of(MediaType.TEXT_EVENT_STREAM));
                        request.getHeaders().set(
                                "X-Internal-Token",
                                aiInternalToken == null ? "" : aiInternalToken);
                        objectMapper.writeValue(request.getBody(), payload);
                    },
                    response -> {
                        try (InputStream in = response.getBody()) {
                            if (in != null) {
                                in.transferTo(outputStream);
                                outputStream.flush();
                            }
                        }
                        return null;
                    });
        } catch (Exception e) {
            try {
                String msg = e.getMessage() == null ? "stream failed" : e.getMessage().replace("\"", "'");
                outputStream.write(
                        ("event: error\ndata: {\"error\":\"" + msg + "\"}\n\n")
                                .getBytes(StandardCharsets.UTF_8));
                outputStream.flush();
            } catch (Exception ignored) {
                // best-effort error event
            }
        }
    }

    @GetMapping(value = "/api/chat/suggestions", produces = "application/json")
    public ResponseEntity<Object> suggestions(@RequestParam(value = "q", defaultValue = "") String q) {
        Map<String, String> query = Map.of("q", q, "limit", "8");
        Map<String, Object> result = api.get("search", "/search/suggestions", query);
        int status = (int) result.getOrDefault("status", 500);
        return ResponseEntity.status(status).body(result.get("data"));
    }

    private Map<String, Object> buildPayload(Map<String, Object> body, HttpSession session) {
        Map<String, Object> payload = new HashMap<>();
        payload.put("message", body.get("message").toString().trim());
        payload.put("session_id", session.getId());
        Object user = session.getAttribute("user");
        if (user instanceof Map<?, ?> userMap && userMap.get("id") != null) {
            payload.put("user_id", userMap.get("id").toString());
        }
        if (body.get("page_context") != null) {
            payload.put("page_context", body.get("page_context").toString());
        }
        return payload;
    }
}
