package com.zylkerbank.portal.controller;

import com.zylkerbank.portal.client.GatewayClient;
import com.zylkerbank.portal.client.LedgerClient;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.ReceiveWizardState;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.PaymentRequestDto;
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
import java.util.Map;

@Controller
public class ReceiveController {

    private static final Logger log = LoggerFactory.getLogger(ReceiveController.class);
    private static final String RECEIVE_WIZARD_ATTR = "receiveWizard";

    private final GatewayClient gatewayClient;
    private final LedgerClient ledgerClient;

    public ReceiveController(GatewayClient gatewayClient, LedgerClient ledgerClient) {
        this.gatewayClient = gatewayClient;
        this.ledgerClient = ledgerClient;
    }

    private ReceiveWizardState getOrCreateWizard(HttpSession session) {
        ReceiveWizardState wizard = (ReceiveWizardState) session.getAttribute(RECEIVE_WIZARD_ATTR);
        if (wizard == null) {
            wizard = new ReceiveWizardState();
            session.setAttribute(RECEIVE_WIZARD_ATTR, wizard);
        }
        return wizard;
    }

    @GetMapping("/receive/step-1")
    public String step1(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        ReceiveWizardState wizard = getOrCreateWizard(session);
        model.addAttribute("wizard", wizard);
        model.addAttribute("user", user);
        return "receive-step-1";
    }

    @PostMapping("/receive/step-1")
    public String postStep1(
            @RequestParam("payerAccount") String payerAccount,
            @RequestParam(value = "payerName", required = false) String payerName,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        if (payerAccount == null || payerAccount.trim().isBlank()) {
            redirectAttributes.addFlashAttribute("flashError", "Please provide a valid payer account number.");
            return "redirect:/receive/step-1";
        }

        if (payerAccount.trim().equals(user.getAccountNumber())) {
            redirectAttributes.addFlashAttribute("flashError", "Cannot request payment from yourself.");
            return "redirect:/receive/step-1";
        }

        ReceiveWizardState wizard = getOrCreateWizard(session);
        wizard.setPayerAccount(payerAccount.trim());
        wizard.setPayerName(payerName != null && !payerName.isBlank() ? payerName.trim() : "Account " + payerAccount.trim());
        session.setAttribute(RECEIVE_WIZARD_ATTR, wizard);

        return "redirect:/receive/step-2";
    }

    @GetMapping("/receive/step-2")
    public String step2(HttpSession session, Model model, RedirectAttributes redirectAttributes) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        ReceiveWizardState wizard = (ReceiveWizardState) session.getAttribute(RECEIVE_WIZARD_ATTR);
        if (wizard == null || wizard.getPayerAccount() == null) {
            redirectAttributes.addFlashAttribute("flashError", "Please choose a payer first.");
            return "redirect:/receive/step-1";
        }

        model.addAttribute("wizard", wizard);
        model.addAttribute("user", user);
        return "receive-step-2";
    }

    @PostMapping("/receive/step-2")
    public String postStep2(
            @RequestParam("amount") BigDecimal amount,
            @RequestParam(value = "description", required = false) String description,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        ReceiveWizardState wizard = (ReceiveWizardState) session.getAttribute(RECEIVE_WIZARD_ATTR);
        if (wizard == null || wizard.getPayerAccount() == null) {
            return "redirect:/receive/step-1";
        }

        if (amount == null || amount.compareTo(BigDecimal.ZERO) <= 0) {
            redirectAttributes.addFlashAttribute("flashError", "Request amount must be greater than zero.");
            return "redirect:/receive/step-2";
        }

        wizard.setAmount(amount);
        wizard.setDescription(description != null && !description.isBlank() ? description.trim() : "Payment request");
        session.setAttribute(RECEIVE_WIZARD_ATTR, wizard);

        return "redirect:/receive/step-3";
    }

    @GetMapping("/receive/step-3")
    public String step3(HttpSession session, Model model, RedirectAttributes redirectAttributes) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        ReceiveWizardState wizard = (ReceiveWizardState) session.getAttribute(RECEIVE_WIZARD_ATTR);
        if (wizard == null || wizard.getAmount() == null) {
            redirectAttributes.addFlashAttribute("flashError", "Please set the request amount first.");
            return "redirect:/receive/step-2";
        }

        model.addAttribute("wizard", wizard);
        model.addAttribute("user", user);
        return "receive-step-3";
    }

    @PostMapping("/receive/step-3")
    public String postStep3(HttpSession session, RedirectAttributes redirectAttributes) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        ReceiveWizardState wizard = (ReceiveWizardState) session.getAttribute(RECEIVE_WIZARD_ATTR);
        if (wizard == null || wizard.getAmount() == null) {
            return "redirect:/receive/step-1";
        }

        try {
            PaymentRequestDto request = gatewayClient.createPaymentRequest(
                    wizard.getPayerAccount(),
                    wizard.getAmount(),
                    wizard.getDescription(),
                    user.getToken()
            );

            session.removeAttribute(RECEIVE_WIZARD_ATTR);
            redirectAttributes.addFlashAttribute("flashSuccess", "Payment request sent successfully to " + wizard.getPayerName());
            return "redirect:/receive/requests";

        } catch (BackendException e) {
            log.warn("Payment request creation failed: [{}] {}", e.getErrorCode(), e.getMessage());
            redirectAttributes.addFlashAttribute("flashError", e.getMessage());
            return "redirect:/receive/step-3";
        }
    }

    @GetMapping("/receive/requests")
    public String listRequests(HttpSession session, Model model) {
        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        Map<String, List<PaymentRequestDto>> requests = Collections.emptyMap();
        try {
            requests = gatewayClient.getPaymentRequests(user.getToken());
        } catch (Exception e) {
            log.warn("Could not fetch payment requests: {}", e.getMessage());
        }

        model.addAttribute("incoming", requests.getOrDefault("incoming", Collections.emptyList()));
        model.addAttribute("outgoing", requests.getOrDefault("outgoing", Collections.emptyList()));
        model.addAttribute("user", user);
        return "payment-requests";
    }

    @PostMapping("/receive/requests/{id}/settle")
    public String settleRequest(
            @PathVariable("id") String id,
            @RequestParam("pin") String pin,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.settlePaymentRequest(id, pin.trim(), user.getToken());
            redirectAttributes.addFlashAttribute("flashSuccess", "Payment request settled successfully.");
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError", "Failed to settle request: " + e.getMessage());
        }
        return "redirect:/receive/requests";
    }

    @PostMapping("/receive/requests/{id}/decline")
    public String declineRequest(
            @PathVariable("id") String id,
            HttpSession session,
            RedirectAttributes redirectAttributes) {

        UserSession user = (UserSession) session.getAttribute("user");
        if (user == null) return "redirect:/login";

        try {
            gatewayClient.declinePaymentRequest(id, user.getToken());
            redirectAttributes.addFlashAttribute("flashInfo", "Payment request declined.");
        } catch (BackendException e) {
            redirectAttributes.addFlashAttribute("flashError", "Failed to decline request: " + e.getMessage());
        }
        return "redirect:/receive/requests";
    }
}
