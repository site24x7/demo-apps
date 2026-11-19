package com.zylkerbank.portal.client;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.zylkerbank.portal.exception.BackendException;
import com.zylkerbank.portal.model.dto.CardDto;
import com.zylkerbank.portal.model.dto.PaymentRequestDto;
import com.zylkerbank.portal.model.dto.TransferResultDto;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpStatusCodeException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestTemplate;

import java.math.BigDecimal;
import java.util.*;

@Component
public class GatewayClient {

    private static final Logger log = LoggerFactory.getLogger(GatewayClient.class);

    private final RestTemplate restTemplate;
    private final String gatewayUrl;
    private final ObjectMapper objectMapper;

    public GatewayClient(
            RestTemplate restTemplate,
            @Value("${services.gateway.url:http://localhost:8082}") String gatewayUrl,
            ObjectMapper objectMapper) {
        this.restTemplate = restTemplate;
        this.gatewayUrl = gatewayUrl.replaceAll("/+$", "");
        this.objectMapper = objectMapper;
    }

    public TransferResultDto initiateTransfer(
            String idempotencyKey,
            String toAccount,
            BigDecimal amount,
            String description,
            String pin,
            String token) {

        String url = gatewayUrl + "/api/v1/transfers/initiate";
        Map<String, Object> body = new HashMap<>();
        body.put("to_account", toAccount);
        body.put("amount", amount != null ? amount.toPlainString() : "0.00");
        body.put("description", description != null ? description : "P2P Transfer");
        body.put("pin", pin);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            headers.set("Idempotency-Key", idempotencyKey);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

            ResponseEntity<TransferResultDto> response = restTemplate.postForEntity(url, request, TransferResultDto.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public PaymentRequestDto createPaymentRequest(
            String payerAccount,
            BigDecimal amount,
            String description,
            String token) {

        String url = gatewayUrl + "/api/v1/transfers/requests";
        Map<String, Object> body = new HashMap<>();
        body.put("payer_account", payerAccount);
        body.put("amount", amount != null ? amount.toPlainString() : "0.00");
        body.put("description", description != null ? description : "Payment Request");

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);

            ResponseEntity<PaymentRequestDto> response = restTemplate.postForEntity(url, request, PaymentRequestDto.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public Map<String, List<PaymentRequestDto>> getPaymentRequests(String token) {
        String url = gatewayUrl + "/api/v1/transfers/requests";
        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<JsonNode> response = restTemplate.exchange(url, HttpMethod.GET, entity, JsonNode.class);

            Map<String, List<PaymentRequestDto>> result = new HashMap<>();
            result.put("incoming", new ArrayList<>());
            result.put("outgoing", new ArrayList<>());

            JsonNode root = response.getBody();
            if (root != null) {
                if (root.has("incoming")) {
                    List<PaymentRequestDto> incoming = objectMapper.convertValue(
                            root.get("incoming"), new TypeReference<List<PaymentRequestDto>>() {});
                    result.put("incoming", incoming);
                }
                if (root.has("outgoing")) {
                    List<PaymentRequestDto> outgoing = objectMapper.convertValue(
                            root.get("outgoing"), new TypeReference<List<PaymentRequestDto>>() {});
                    result.put("outgoing", outgoing);
                }
            }
            return result;
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public JsonNode settlePaymentRequest(String requestId, String pin, String token) {
        String url = gatewayUrl + "/api/v1/transfers/requests/" + requestId + "/settle";
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, String>> request = new HttpEntity<>(Map.of("pin", pin), headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public JsonNode declinePaymentRequest(String requestId, String token) {
        String url = gatewayUrl + "/api/v1/transfers/requests/" + requestId + "/decline";
        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> request = new HttpEntity<>(headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public List<CardDto> getCards(String token) {
        String url = gatewayUrl + "/api/v1/cards";
        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<JsonNode> response = restTemplate.exchange(url, HttpMethod.GET, entity, JsonNode.class);

            JsonNode root = response.getBody();
            if (root != null && root.has("cards")) {
                return objectMapper.convertValue(root.get("cards"), new TypeReference<List<CardDto>>() {});
            }
            return Collections.emptyList();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public CardDto getCard(String cardId, String token) {
        String url = gatewayUrl + "/api/v1/cards/" + cardId;
        try {
            HttpHeaders headers = new HttpHeaders();
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<JsonNode> response = restTemplate.exchange(url, HttpMethod.GET, entity, JsonNode.class);
            JsonNode root = response.getBody();
            if (root != null && root.has("card")) {
                return objectMapper.convertValue(root.get("card"), CardDto.class);
            }
            return objectMapper.convertValue(root, CardDto.class);
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public CardDto createCard(String cardType, BigDecimal spendingLimit, String token) {
        String url = gatewayUrl + "/api/v1/cards";
        Map<String, Object> body = new HashMap<>();
        body.put("card_type", cardType != null ? cardType : "VISA");
        if (spendingLimit != null) {
            body.put("spending_limit", spendingLimit.toPlainString());
        }

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            JsonNode root = response.getBody();
            if (root != null && root.has("card")) {
                return objectMapper.convertValue(root.get("card"), CardDto.class);
            }
            return objectMapper.convertValue(root, CardDto.class);
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public JsonNode fundCard(String cardId, BigDecimal amount, String pin, String token) {
        String url = gatewayUrl + "/api/v1/cards/" + cardId + "/fund";
        Map<String, Object> body = new HashMap<>();
        body.put("amount", amount != null ? amount.toPlainString() : "0.00");
        body.put("pin", pin);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public JsonNode withdrawFromCard(String cardId, BigDecimal amount, String pin, String token) {
        String url = gatewayUrl + "/api/v1/cards/" + cardId + "/withdraw";
        Map<String, Object> body = new HashMap<>();
        body.put("amount", amount != null ? amount.toPlainString() : "0.00");
        body.put("pin", pin);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
            ResponseEntity<JsonNode> response = restTemplate.postForEntity(url, request, JsonNode.class);
            return response.getBody();
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    public CardDto updateCardStatus(String cardId, boolean frozen, String token) {
        String url = gatewayUrl + "/api/v1/cards/" + cardId + "/status";
        Map<String, Object> body = Map.of("frozen", frozen);

        try {
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Map<String, Object>> request = new HttpEntity<>(body, headers);
            ResponseEntity<JsonNode> response = restTemplate.exchange(url, HttpMethod.PATCH, request, JsonNode.class);
            JsonNode root = response.getBody();
            if (root != null && root.has("card")) {
                return objectMapper.convertValue(root.get("card"), CardDto.class);
            }
            return objectMapper.convertValue(root, CardDto.class);
        } catch (HttpStatusCodeException e) {
            throw parseHttpException(e);
        } catch (ResourceAccessException e) {
            throw BackendException.serviceUnavailable("Financial Gateway", e);
        }
    }

    private BackendException parseHttpException(HttpStatusCodeException e) {
        String body = e.getResponseBodyAsString();
        String errorCode = "GATEWAY_ERROR";
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
