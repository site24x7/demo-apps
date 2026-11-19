package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.UserSession;
import jakarta.servlet.http.HttpSession;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

@Controller
public class AuthController {

    private final LedgerClient ledgerClient;

    public AuthController(LedgerClient ledgerClient) {
        this.ledgerClient = ledgerClient;
    }

    @GetMapping("/login")
    public String loginPage(HttpSession session) {
        if (session != null && session.getAttribute("user") != null) {
            return "redirect:/dashboard";
        }
        return "login";
    }

    @PostMapping("/login")
    public String doLogin(
            @RequestParam("email") String email,
            @RequestParam("password") String password,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        try {
            UserSession user = ledgerClient.login(email.trim(), password);
            session.setAttribute("user", user);
            return "redirect:/dashboard";
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError",
                    "INVALID_CREDENTIALS".equals(e.getErrorCode())
                            ? "Invalid email or password. Please try again."
                            : e.getMessage());
            return "redirect:/login";
        }
    }

    @GetMapping("/register")
    public String registerPage(HttpSession session) {
        if (session != null && session.getAttribute("user") != null) {
            return "redirect:/dashboard";
        }
        return "register";
    }

    @PostMapping("/register")
    public String doRegister(
            @RequestParam("email") String email,
            @RequestParam("password") String password,
            @RequestParam("fullName") String fullName,
            @RequestParam("phone") String phone,
            @RequestParam("pin") String pin,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        try {
            UserSession user = ledgerClient.register(
                    email.trim(),
                    password,
                    fullName.trim(),
                    phone.trim(),
                    pin.trim()
            );
            session.setAttribute("user", user);
            redirectAttributes.addFlashAttribute("flashSuccess", "Welcome to ZylkerBank! Your account has been provisioned.");
            return "redirect:/dashboard";
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError",
                    "EMAIL_EXISTS".equals(e.getErrorCode())
                            ? "An account with this email already exists."
                            : e.getMessage());
            return "redirect:/register";
        }
    }

    @PostMapping("/logout")
    public String logout(HttpSession session, RedirectAttributes redirectAttributes) {
        if (session != null) {
            session.invalidate();
        }
        redirectAttributes.addFlashAttribute("flashInfo", "You have been logged out safely.");
        return "redirect:/login";
    }
}
