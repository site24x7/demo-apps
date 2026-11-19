package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.RecipientSearchResultDto;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class RecipientApiController {

    private final LedgerClient ledgerClient;

    public RecipientApiController(LedgerClient ledgerClient) {
        this.ledgerClient = ledgerClient;
    }

    @GetMapping("/api/recipients/search")
    public ResponseEntity<RecipientSearchResultDto> search(
            @RequestParam("q") String query,
            HttpSession session) {

        UserSession user = (session != null) ? (UserSession) session.getAttribute("user") : null;
        String token = (user != null) ? user.getToken() : null;

        RecipientSearchResultDto results = ledgerClient.searchRecipients(query, token);
        return ResponseEntity.ok(results);
    }
}
