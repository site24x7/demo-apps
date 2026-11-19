package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.GatewayClient;
import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.TransferWizardState;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.StatementResponseDto;
import com.zylkerbank.portal.model.dto.TransferResultDto;
import jakarta.servlet.http.HttpSession;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.math.BigDecimal;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.stream.Collectors;

@Controller
public class TransferController {

    private static final Logger log = LoggerFactory.getLogger(TransferController.class);
    private static final String WIZARD_ATTR = "transferWizard";

    private final GatewayClient gatewayClient;
    private final LedgerClient ledgerClient;

    public TransferController(GatewayClient gatewayClient, LedgerClient ledgerClient) {
        this.gatewayClient = gatewayClient;
        this.ledgerClient = ledgerClient;
    }

    private TransferWizardState getOrCreateWizard(HttpSession session) {
        TransferWizardState wizard = (TransferWizardState) session.getAttribute(WIZARD_ATTR);
        if (wizard == null) {
            wizard = new TransferWizardState();
            session.setAttribute(WIZARD_ATTR, wizard);
        }
        return wizard;
    }

    @GetMapping("/transfer/step-1")
    public String step1(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        TransferWizardState wizard = getOrCreateWizard(session);

        // Fetch recent counterparties from statement history
        List<String> recentRecipients = Collections.emptyList();
        try {
            StatementResponseDto statements = ledgerClient.getStatements(user.getAccountNumber(), 1, 20, null, null, user.getToken());
            if (statements != null && statements.getItems() != null) {
                recentRecipients = statements.getItems().stream()
                        .map(item -> item.getCounterpartyName() != null ? item.getCounterpartyName() + " (" + item.getCounterpartyAccount() + ")" : null)
                        .filter(Objects::nonNull)
                        .distinct()
                        .limit(5)
                        .collect(Collectors.toList());
            }
        } catch (Exception ignored) {
        }

        model.addAttribute("wizard", wizard);
        model.addAttribute("recentRecipients", recentRecipients);
        model.addAttribute("user", user);
        return "pay-step-1";
    }

    @PostMapping("/transfer/step-1")
    public String postStep1(
            @RequestParam("recipientAccount") String recipientAccount,
            @RequestParam(value = "recipientName", required = false) String recipientName,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        if (recipientAccount == null || recipientAccount.trim().isBlank()) {
            redirectAttributes.addFlashAttribute("flashError", "Please provide a valid recipient account number.");
            return "redirect:/transfer/step-1";
        }

        if (recipientAccount.trim().equals(user.getAccountNumber())) {
            redirectAttributes.addFlashAttribute("flashError", "Cannot transfer funds to your own account.");
            return "redirect:/transfer/step-1";
        }

        TransferWizardState wizard = getOrCreateWizard(session);
        wizard.setRecipientAccount(recipientAccount.trim());
        wizard.setRecipientName(recipientName != null && !recipientName.isBlank() ? recipientName.trim() : "Recipient " + recipientAccount.trim());
        session.setAttribute(WIZARD_ATTR, wizard);

        return "redirect:/transfer/step-2";
    }

    @GetMapping("/transfer/step-2")
    public String step2(HttpSession session, Model model, RedirectAttributes redirectAttributes) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        TransferWizardState wizard = (TransferWizardState) session.getAttribute(WIZARD_ATTR);
        if (wizard == null || wizard.getRecipientAccount() == null) {
            redirectAttributes.addFlashAttribute("flashError", "Please select a recipient first.");
            return "redirect:/transfer/step-1";
        }

        model.addAttribute("wizard", wizard);
        model.addAttribute("user", user);
        return "pay-step-2";
    }

    @PostMapping("/transfer/step-2")
    public String postStep2(
            @RequestParam("amount") BigDecimal amount,
            @RequestParam(value = "description", required = false) String description,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        TransferWizardState wizard = (TransferWizardState) session.getAttribute(WIZARD_ATTR);
        if (wizard == null || wizard.getRecipientAccount() == null) {
            return "redirect:/transfer/step-1";
        }

        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            redirectAttributes.addFlashAttribute("flashError", "Transfer amount must be greater than zero.");
            return "redirect:/transfer/step-2";
        }

        if (user.getBalance() != null && amount.compareTo(user.getBalance()) > 0) {
            redirectAttributes.addFlashAttribute("flashError", "Transfer amount exceeds your current available balance.");
            return "redirect:/transfer/step-2";
        }

        wizard.setAmount(amount);
        wizard.setDescription(description != null && !description.isBlank() ? description.trim() : "Transfer to " + wizard.getRecipientName());
        wizard.generateNewIdempotencyKey(); // Idempotency key generated and anchored in session wizard
        session.setAttribute(WIZARD_ATTR, wizard);

        return "redirect:/transfer/step-3";
    }

    @GetMapping("/transfer/step-3")
    public String step3(HttpSession session, Model model, RedirectAttributes redirectAttributes) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        TransferWizardState wizard = (TransferWizardState) session.getAttribute(WIZARD_ATTR);
        if (wizard == null || wizard.getAmount() == null) {
            redirectAttributes.addFlashAttribute("flashError", "Please set the transfer amount first.");
            return "redirect:/transfer/step-2";
        }

        model.addAttribute("wizard", wizard);
        model.addAttribute("user", user);
        return "pay-step-3";
    }

    @PostMapping("/transfer/step-3")
    public String postStep3(
            @RequestParam("pin") String pin,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        TransferWizardState wizard = (TransferWizardState) session.getAttribute(WIZARD_ATTR);
        if (wizard == null || wizard.getAmount() == null) {
            return "redirect:/transfer/step-1";
        }

        if (pin == null || pin.trim().isBlank()) {
            redirectAttributes.addFlashAttribute("flashError", "Please enter your security PIN to confirm transfer.");
            return "redirect:/transfer/step-3";
        }

        try {
            TransferResultDto result = gatewayClient.initiateTransfer(
                    wizard.getIdempotencyKey(),
                    wizard.getRecipientAccount(),
                    wizard.getAmount(),
                    wizard.getDescription(),
                    pin.trim(),
                    user.getToken()
            );

            // Update user balance in session
            if (result != null && result.getNewBalance() != null) {
                user.setBalance(result.getNewBalance());
                session.setAttribute("user", user);
            }

            session.removeAttribute(WIZARD_ATTR);
            redirectAttributes.addFlashAttribute("receipt", result);
            redirectAttributes.addFlashAttribute("flashSuccess", "Payment sent successfully!");
            return "redirect:/transfer/success";

        } catch (BackendException e) {
            log.warn("Transfer failed: [{}] {}", e.getErrorCode(), e.getMessage());
            String userMsg;
            switch (e.getErrorCode()) {
                case "INVALID_PIN" -> userMsg = "Invalid security PIN entered. Please try again.";
                case "PIN_LOCKED" -> userMsg = "Security PIN is locked due to consecutive failed attempts.";
                case "INSUFFICIENT_FUNDS" -> userMsg = "Insufficient funds in your account to complete this transfer.";
                case "TRANSFER_BLOCKED" -> userMsg = "Transfer was blocked by real-time risk assessment.";
                case "DAILY_LIMIT_EXCEEDED" -> userMsg = "Daily debit limit exceeded for your account tier.";
                default -> userMsg = e.getMessage();
            }
            redirectAttributes.addFlashAttribute("flashError", userMsg);
            return "redirect:/transfer/step-3";
        }
    }

    @GetMapping("/transfer/success")
    public String success(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        if (!model.containsAttribute("receipt")) {
            return "redirect:/dashboard";
        }

        model.addAttribute("user", user);
        return "payment-success";
    }
}
