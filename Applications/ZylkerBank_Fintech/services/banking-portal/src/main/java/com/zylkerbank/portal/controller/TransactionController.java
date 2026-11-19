package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.StatementResponseDto;
import jakarta.servlet.http.HttpSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class TransactionController {

    private static final Logger log = LoggerFactory.getLogger(TransactionController.class);

    private final LedgerClient ledgerClient;

    public TransactionController(LedgerClient ledgerClient) {
        this.ledgerClient = ledgerClient;
    }

    @GetMapping("/transactions")
    public String transactions(
            @RequestParam(value = "page", defaultValue = "1") int page,
            @RequestParam(value = "page_size", defaultValue = "20") int pageSize,
            @RequestParam(value = "from", required = false) String from,
            @RequestParam(value = "to", required = false) String to,
            @RequestParam(value = "q", required = false) String query,
            HttpSession session,
            Model model) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        StatementResponseDto statements = new StatementResponseDto();
        try {
            statements = ledgerClient.getStatements(user.getAccountNumber(), page, pageSize, from, to, user.getToken());
            // Filter by query if provided
            if (query != null && !query.isBlank() && statements.getItems() != null) {
                String qLower = query.toLowerCase();
                var filtered = statements.getItems().stream()
                        .filter(item -> (item.getDescription() != null && item.getDescription().toLowerCase().contains(qLower)) ||
                                (item.getCounterpartyName() != null && item.getCounterpartyName().toLowerCase().contains(qLower)) ||
                                (item.getTransactionRef() != null && item.getTransactionRef().toLowerCase().contains(qLower)))
                        .toList();
                statements.setItems(filtered);
            }
        } catch (Exception e) {
            log.warn("Could not fetch statement: {}", e.getMessage());
        }

        model.addAttribute("statements", statements);
        model.addAttribute("items", statements.getItems());
        model.addAttribute("user", user);
        model.addAttribute("currentPage", page);
        model.addAttribute("pageSize", pageSize);
        model.addAttribute("query", query);

        return "transactions";
    }
}
