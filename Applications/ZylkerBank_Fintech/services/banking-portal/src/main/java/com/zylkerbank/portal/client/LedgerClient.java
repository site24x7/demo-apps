package com.zylkerbank.portal.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.UserSession;
import com.zylkerbank.portal.model.dto.AccountDto;
import com.zylkerbank.portal.model.dto.RecipientSearchResultDto;
import com.zylkerbank.portal.model.dto.StatementResponseDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.util.UriComponentsBuilder;

import java.math.BigDecimal;
import java.util.Map;

@Component
public class LedgerClient {

    private static final Logger log = LoggerFactory.getLogger(LedgerClient.class);

    private final RestTemplate restTemplate;
    private final String ledgerUrl;
    private final ObjectMapper objectMapper;

    public LedgerClient(
            RestTemplate restTemplate,
            @Value("${services.ledger.url:http://localhost:8081}") String ledgerUrl,
            ObjectMapper objectMapper) {
        this.restTemplate = restTemplate;
        this.ledgerUrl = ledgerUrl.replaceAll("/+$", "");
        this.objectMapper = objectMapper;
    }

    public UserSession login(String email, String password) {
        String url = ledgerUrl + "/api/v1/auth/login";
        Map<String, String> body = Map.of(
                "email", email,
                "password", password
        );
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, String>> request = new HttpEntity<>(body, headers);

            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            JsonNode root = response.getBody();
            if (root == null) {
                throw new BackendException(HttpStatus.INTERNAL_SERVER_ERROR, "EMPTY_RESPONSE", "Empty response from Ledger service");
            }

            String token = root.path("token").asText();
            JsonNode userNode = root.path("user");
            JsonNode accountNode = root.path("account");

            UserSession session = new UserSession();
            session.setToken(token);
            session.setUserId(userNode.path("user_id").asText());
            session.setEmail(userNode.path("email").asText());
            session.setFullName(userNode.path("full_name").asText());
            session.setPhone(userNode.path("phone").asText());

            if (!accountNode.isMissingNode()) {
                session.setAccountNumber(accountNode.path("account_number").asText());
                if (accountNode.has("balance")) {
                    session.setBalance(new BigDecimal(accountNode.path("balance").asText("0.00")));
                }
                session.setTierLevel(accountNode.path("tier_level").asInt(1));
                session.setKycStatus(accountNode.path("kyc_status").asText("VERIFIED"));
            } else if (userNode.has("account_number")) {
                session.setAccountNumber(userNode.path("account_number").asText());
            }

            return session;
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    public UserSession register(String email, String password, String fullName, String phone, String pin) {
        String url = ledgerUrl + "/api/v1/auth/register";
        Map<String, String> body = Map.of(
                "email", email,
                "password", password,
                "full_name", fullName,
                "phone", phone,
                "pin", pin
        );
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<Map<String, String>> request = new HttpEntity<>(body, headers);

            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            JsonNode root = response.getBody();
            if (root == null) {
                throw new BackendException(HttpStatus.INTERNAL_SERVER_ERROR, "EMPTY_RESPONSE", "Empty response from Ledger service");
            }

            String token = root.path("token").asText();
            JsonNode userNode = root.path("user");
            JsonNode accountNode = root.path("account");

            UserSession session = new UserSession();
            session.setToken(token);
            session.setUserId(userNode.path("user_id").asText());
            session.setEmail(userNode.path("email").asText());
            session.setFullName(userNode.path("full_name").asText());
            session.setPhone(userNode.path("phone").asText());

            if (!accountNode.isMissingNode()) {
                session.setAccountNumber(accountNode.path("account_number").asText());
                if (accountNode.has("balance")) {
                    session.setBalance(new BigDecimal(accountNode.path("balance").asText("1000.00")));
                }
                session.setTierLevel(accountNode.path("tier_level").asInt(1));
                session.setKycStatus(accountNode.path("kyc_status").asText("VERIFIED"));
            }

            return session;
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    public AccountDto getAccount(String accountNumber, String token) {
        String url = ledgerUrl + "/api/v1/accounts/" + accountNumber;
        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<AccountDto> response = restTemplate.exchange(url, HttpMethod.GET, entity, AccountDto.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    public RecipientSearchResultDto searchRecipients(String query, String token) {
        String url = UriComponentsBuilder.fromHttpUrl(ledgerUrl + "/api/v1/accounts/search")
                .queryParam("q", query)
                .toUriString();
        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<RecipientSearchResultDto> response = restTemplate.exchange(
                    url, HttpMethod.GET, entity, RecipientSearchResultDto.class);
            return response.getBody() != null ? response.getBody() : new RecipientSearchResultDto();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    public boolean verifyPin(String accountNumber, String pin, String token) {
        String url = ledgerUrl + "/api/v1/accounts/" + accountNumber + "/verify-pin";
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, String>> request = new HttpEntity<>(Map.of("pin", pin), headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            return response.getStatusCode().is2xxSuccessful();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    public StatementResponseDto getStatements(String accountNumber, int page, int pageSize, String from, String to, String token) {
        UriComponentsBuilder builder = UriComponentsBuilder.fromHttpUrl(ledgerUrl + "/api/v1/ledger/statements/" + accountNumber)
                .queryParam("page", page)
                .queryParam("page_size", pageSize);
        if (from != null && !from.isBlank()) builder.queryParam("from", from);
        if (to != null && !to.isBlank()) builder.queryParam("to", to);

        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<StatementResponseDto> response = restTemplate.exchange(
                    builder.toUriString(), HttpMethod.GET, entity, StatementResponseDto.class);
            return response.getBody() != null ? response.getBody() : new StatementResponseDto();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Ledger Service", e);
        }
    }

    private BackendException parseHttpException(HttpStatusCodeException e) {
        String body = e.getResponseBodyAsString();
        String errorCode = "LEDGER_ERROR";
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
