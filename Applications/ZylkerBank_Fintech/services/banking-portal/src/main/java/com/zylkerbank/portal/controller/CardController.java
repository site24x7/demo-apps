package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.GatewayClient;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.CardDto;
import jakarta.servlet.http.HttpSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.List;

@Controller
public class CardController {

    private static final Logger log = LoggerFactory.getLogger(CardController.class);

    private final GatewayClient gatewayClient;

    public CardController(GatewayClient gatewayClient) {
        this.gatewayClient = gatewayClient;
    }

    @GetMapping("/cards")
    public String listCards(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        List<CardDto> cards = Collections.emptyList();
        try {
            cards = gatewayClient.getCards(user.getToken());
        } catch (Exception e) {
            log.warn("Could not fetch cards: {}", e.getMessage());
        }

        model.addAttribute("cards", cards);
        model.addAttribute("user", user);
        return "all-card";
    }

    @PostMapping("/cards/new")
    public String createCard(
            @RequestParam(value = "cardType", defaultValue = "VISA") String cardType,
            @RequestParam(value = "spendingLimit", defaultValue = "1000.00") BigDecimal spendingLimit,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            CardDto newCard = gatewayClient.createCard(cardType, spendingLimit, user.getToken());
            redirectAttributes.addFlashAttribute("flashSuccess",
                    "New " + newCard.getCardType() + " virtual card provisioned! Number: " +
                            (newCard.getCardNumber() != null ? newCard.getCardNumber() : newCard.getCardNumberMasked()) +
                            (newCard.getCvv() != null ? " (CVV: " + newCard.getCvv() + ")" : ""));
            return "redirect:/cards";
        } catch (BackendException e) {
            log.warn("Card creation failed: [{}] {}", e.getErrorCode(), e.getMessage());
            redirectAttributes.addFlashAttribute("flashError", "Failed to create card: " + e.getMessage());
            return "redirect:/cards";
        }
    }

    @GetMapping("/cards/{id}")
    public String cardDetail(@PathVariable("id") String id, HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            CardDto card = gatewayClient.getCard(id, user.getToken());
            model.addAttribute("card", card);
            model.addAttribute("user", user);
            return "card-detail";
        } catch (BackendException e) {
            log.warn("Failed to get card {}: [{}] {}", id, e.getErrorCode(), e.getMessage());
            return "redirect:/cards";
        }
    }

    @PostMapping("/cards/{id}/fund")
    public String fundCard(
            @PathVariable("id") String id,
            @RequestParam("amount") BigDecimal amount,
            @RequestParam("pin") String pin,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.fundCard(id, amount, pin.trim(), user.getToken());
            redirectAttributes.addFlashAttribute("flashSuccess", "Card loaded with $" + String.format("%,.2f", amount));
        } catch (BackendException e) {
            log.warn("Fund card failed: [{}] {}", e.getErrorCode(), e.getMessage());
            redirectAttributes.addFlashAttribute("flashError", "Card funding failed: " + e.getMessage());
        }
        return "redirect:/cards/" + id;
    }

    @PostMapping("/cards/{id}/withdraw")
    public String withdrawFromCard(
            @PathVariable("id") String id,
            @RequestParam("amount") BigDecimal amount,
            @RequestParam("pin") String pin,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.withdrawFromCard(id, amount, pin.trim(), user.getToken());
            redirectAttributes.addFlashAttribute("flashSuccess", "Withdrawn $" + String.format("%,.2f", amount) + " back to bank account.");
        } catch (BackendException e) {
            log.warn("Withdraw from card failed: [{}] {}", e.getErrorCode(), e.getMessage());
            redirectAttributes.addFlashAttribute("flashError", "Card withdrawal failed: " + e.getMessage());
        }
        return "redirect:/cards/" + id;
    }

    @PostMapping("/cards/{id}/freeze")
    public String freezeCard(
            @PathVariable("id") String id,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.updateCardStatus(id, true, user.getToken());
            redirectAttributes.addFlashAttribute("flashInfo", "Card has been frozen.");
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError", "Failed to freeze card: " + e.getMessage());
        }
        return "redirect:/cards/" + id;
    }

    @PostMapping("/cards/{id}/unfreeze")
    public String unfreezeCard(
            @PathVariable("id") String id,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.updateCardStatus(id, false, user.getToken());
            redirectAttributes.addFlashAttribute("flashSuccess", "Card un-frozen and active.");
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError", "Failed to unfreeze card: " + e.getMessage());
        }
        return "redirect:/cards/" + id;
    }
}
