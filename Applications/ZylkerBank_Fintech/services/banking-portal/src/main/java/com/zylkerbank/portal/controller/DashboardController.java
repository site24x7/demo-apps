package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.GatewayClient;
import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.AccountDto;
import com.zylkerbank.portal.model.dto.CardDto;
import com.zylkerbank.portal.model.dto.StatementResponseDto;
import jakarta.servlet.http.HttpSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.Collections;
import java.util.List;

@Controller
public class DashboardController {

    private static final Logger log = LoggerFactory.getLogger(DashboardController.class);

    private final LedgerClient ledgerClient;
    private final GatewayClient gatewayClient;

    public DashboardController(LedgerClient ledgerClient, GatewayClient gatewayClient) {
        this.ledgerClient = ledgerClient;
        this.gatewayClient = gatewayClient;
    }

    @GetMapping("/dashboard")
    public String dashboard(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) {
            return "redirect:/login";
        }

        // Fetch fresh account balance and status from Ledger
        AccountDto account = null;
        try {
            account = ledgerClient.getAccount(user.getAccountNumber(), user.getToken());
            if (account != null) {
                user.setBalance(account.getBalance());
                user.setTierLevel(account.getTierLevel());
                user.setKycStatus(account.getKycStatus());
                session.setAttribute("user", user);
            }
        } catch (Exception e) {
            log.warn("Could not refresh account details: {}", e.getMessage());
        }

        // Fetch virtual cards from Gateway
        List<CardDto> cards = Collections.emptyList();
        try {
            cards = gatewayClient.getCards(user.getToken());
        } catch (Exception e) {
            log.warn("Could not fetch cards: {}", e.getMessage());
        }

        // Fetch recent transactions (last 6) from Ledger
        StatementResponseDto statements = new StatementResponseDto();
        try {
            statements = ledgerClient.getStatements(user.getAccountNumber(), 1, 6, null, null, user.getToken());
        } catch (Exception e) {
            log.warn("Could not fetch statements: {}", e.getMessage());
        }

        model.addAttribute("user", user);
        model.addAttribute("account", account);
        model.addAttribute("cards", cards);
        model.addAttribute("statements", statements);
        model.addAttribute("transactions", statements.getItems());

        return "dashboard";
    }
}
