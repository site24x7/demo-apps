package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.AccountDto;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class AccountController {

    private final LedgerClient ledgerClient;

    public AccountController(LedgerClient ledgerClient) {
        this.ledgerClient = ledgerClient;
    }

    @GetMapping("/account")
    public String account(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) {
            return "redirect:/login";
        }

        AccountDto account = null;
        try {
            account = ledgerClient.getAccount(user.getAccountNumber(), user.getToken());
            if (account != null) {
                user.setBalance(account.getBalance());
                user.setTierLevel(account.getTierLevel());
                user.setKycStatus(account.getKycStatus());
                session.setAttribute("user", user);
            }
        } catch (Exception ignored) {
        }

        model.addAttribute("user", user);
        model.addAttribute("account", account);
        return "account";
    }
}
