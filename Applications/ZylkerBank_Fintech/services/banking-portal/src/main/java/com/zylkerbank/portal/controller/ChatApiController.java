package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.AiClient;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.ChatRequestDto;
import com.zylkerbank.portal.model.dto.ChatResponseDto;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ChatApiController {

    private final AiClient aiClient;

    public ChatApiController(AiClient aiClient) {
        this.aiClient = aiClient;
    }

    @PostMapping("/api/chat")
    public ResponseEntity<ChatResponseDto> chat(
            @RequestBody ChatRequestDto requestDto,
            HttpSession session) {

        UserSession user = (session != null) ? (UserSession) session.getAttribute("user") : null;
        String token = (user != null) ? user.getToken() : null;

        if (requestDto.getSessionId() == null && session != null) {
            requestDto.setSessionId(session.getId());
        }

        ChatResponseDto response = aiClient.chat(requestDto, token);
        return ResponseEntity.ok(response);
    }
}
