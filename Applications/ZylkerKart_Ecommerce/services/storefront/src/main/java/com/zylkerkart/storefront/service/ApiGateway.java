package com.zylkerkart.storefront.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

/**
 * HTTP client service for communicating with backend microservices.
 * Acts as BFF (Backend-for-Frontend) gateway.
 */
@Service
public class ApiGateway {

    private final RestTemplate restTemplate;
    private final Map<String, String> serviceUrls;

    public ApiGateway(
            RestTemplate restTemplate,
            @Value("${services.product.url}") String productUrl,
            @Value("${services.order.url}") String orderUrl,
            @Value("${services.search.url}") String searchUrl,
            @Value("${services.payment.url}") String paymentUrl,
            @Value("${services.auth.url}") String authUrl) {
        this.restTemplate = restTemplate;
        this.serviceUrls = Map.of(
                "product", productUrl,
                "order", orderUrl,
                "search", searchUrl,
                "payment", paymentUrl,
                "auth", authUrl
        );
    }

    /**
     * Make a GET request to a backend service.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> get(String service, String path, Map<String, String> query, String token) {
        try {
            String url = buildUrl(service, path, query);
            HttpHeaders headers = new HttpHeaders();
            if (token != null && !token.isEmpty()) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<Object> response = restTemplate.exchange(url, HttpMethod.GET, entity, Object.class);
            Map<String, Object> result = new HashMap<>();
            result.put("status", response.getStatusCode().value());
            result.put("data", response.getBody());
            return result;
        } catch (RestClientException e) {
            Map<String, Object> result = new HashMap<>();
            result.put("status", 503);
            Map<String, String> errorData = new HashMap<>();
            errorData.put("error", "Service '" + service + "' unavailable: " + e.getMessage());
            result.put("data", errorData);
            return result;
        }
    }

    public Map<String, Object> get(String service, String path) {
        return get(service, path, null, null);
    }

    public Map<String, Object> get(String service, String path, Map<String, String> query) {
        return get(service, path, query, null);
    }

    /**
     * Make a POST request to a backend service.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> post(String service, String path, Object body, String token) {
        try {
            String url = serviceUrls.get(service) + path;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null && !token.isEmpty()) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Object> entity = new HttpEntity<>(body, headers);
            ResponseEntity<Object> response = restTemplate.exchange(url, HttpMethod.POST, entity, Object.class);
            Map<String, Object> result = new HashMap<>();
            result.put("status", response.getStatusCode().value());
            result.put("data", response.getBody());
            return result;
        } catch (RestClientException e) {
            Map<String, Object> result = new HashMap<>();
            result.put("status", 503);
            Map<String, String> errorData = new HashMap<>();
            errorData.put("error", "Service '" + service + "' unavailable: " + e.getMessage());
            result.put("data", errorData);
            return result;
        }
    }

    public Map<String, Object> post(String service, String path, Object body) {
        return post(service, path, body, null);
    }

    /**
     * Make a PUT request to a backend service.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> put(String service, String path, Object body, String token) {
        try {
            String url = serviceUrls.get(service) + path;
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            if (token != null && !token.isEmpty()) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Object> entity = new HttpEntity<>(body, headers);
            ResponseEntity<Object> response = restTemplate.exchange(url, HttpMethod.PUT, entity, Object.class);
            Map<String, Object> result = new HashMap<>();
            result.put("status", response.getStatusCode().value());
            result.put("data", response.getBody());
            return result;
        } catch (RestClientException e) {
            Map<String, Object> result = new HashMap<>();
            result.put("status", 503);
            Map<String, String> errorData = new HashMap<>();
            errorData.put("error", "Service '" + service + "' unavailable: " + e.getMessage());
            result.put("data", errorData);
            return result;
        }
    }

    /**
     * Make a DELETE request to a backend service.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> delete(String service, String path, String token) {
        try {
            String url = serviceUrls.get(service) + path;
            HttpHeaders headers = new HttpHeaders();
            if (token != null && !token.isEmpty()) {
                headers.setBearerAuth(token);
            }
            HttpEntity<Void> entity = new HttpEntity<>(headers);
            ResponseEntity<Object> response = restTemplate.exchange(url, HttpMethod.DELETE, entity, Object.class);
            Map<String, Object> result = new HashMap<>();
            result.put("status", response.getStatusCode().value());
            result.put("data", response.getBody());
            return result;
        } catch (RestClientException e) {
            Map<String, Object> result = new HashMap<>();
            result.put("status", 503);
            Map<String, String> errorData = new HashMap<>();
            errorData.put("error", "Service '" + service + "' unavailable: " + e.getMessage());
            result.put("data", errorData);
            return result;
        }
    }

    public Map<String, Object> delete(String service, String path) {
        return delete(service, path, null);
    }

    // ── URL Builder ──

    private String buildUrl(String service, String path, Map<String, String> query) {
        StringBuilder url = new StringBuilder(serviceUrls.get(service)).append(path);
        if (query != null && !query.isEmpty()) {
            StringBuilder params = new StringBuilder();
            query.forEach((k, v) -> {
                if (v != null && !v.isEmpty()) {
                    if (params.length() > 0) params.append("&");
                    try {
                        params.append(java.net.URLEncoder.encode(k, "UTF-8"))
                              .append("=")
                              .append(java.net.URLEncoder.encode(v, "UTF-8"));
                    } catch (java.io.UnsupportedEncodingException e) {
                        params.append(k).append("=").append(v);
                    }
                }
            });
            if (params.length() > 0) {
                url.append("?").append(params);
            }
        }
        return url.toString();
    }
}
