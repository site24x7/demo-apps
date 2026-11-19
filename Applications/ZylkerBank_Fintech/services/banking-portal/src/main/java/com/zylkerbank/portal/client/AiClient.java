package com.zylkerbank.portal.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.dto.ChatRequestDto;
import com.zylkerbank.portal.model.dto.ChatResponseDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

@Component
public class AiClient {

    private static final Logger log = LoggerFactory.getLogger(AiClient.class);

    private final RestTemplate aiRestTemplate;
    private final String aiUrl;
    private final ObjectMapper objectMapper;

    public AiClient(
            @Qualifier("aiRestTemplate") RestTemplate aiRestTemplate,
            @Value("${services.ai.url:http://localhost:8083}") String aiUrl,
            ObjectMapper objectMapper) {
        this.aiRestTemplate = aiRestTemplate;
        this.aiUrl = aiUrl.replaceAll("/+$", "");
        this.objectMapper = objectMapper;
    }

    public ChatResponseDto chat(ChatRequestDto requestDto, String token) {
        String url = aiUrl + "/api/v1/chat";
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<ChatRequestDto> request = new HttpEntity<>(requestDto, headers);

            ResponseEntity<ChatResponseDto> response = aiRestTemplate.postForEntity(url, request, ChatResponseDto.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            log.warn("AI service unreachable: {}", e.getMessage());
            // Friendly fallback if AI is offline
            ChatResponseDto fallback = new ChatResponseDto();
            fallback.setReply("The ZylkerBank AI Advisor is currently offline or unreachable. Please try again in a few moments.");
            fallback.setModel("fallback");
            return fallback;
        }
    }

    private BackendException parseHttpException(HttpStatusCodeException e) {
        String body = e.getResponseBodyAsString();
        String errorCode = "AI_ERROR";
        String message = e.getMessage();
        try {
            JsonNode node = objectMapper.readTree(body);
            if (node.has("error")) errorCode = node.get("error").asText();
            if (node.has("message")) message = node.get("message").asText();
        } catch (Exception ignored) {
        }
        return new BackendException(HttpStatus.valueOf(e.getStatusCode().value()), errorCode, message, e);
    }
}
