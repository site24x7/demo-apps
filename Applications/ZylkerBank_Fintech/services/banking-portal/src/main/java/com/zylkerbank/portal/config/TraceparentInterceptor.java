package com.zylkerbank.portal.config;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpRequest;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.io.IOException;
import java.security.SecureRandom;
import java.util.HexFormat;

/**
 * ClientHttpRequestInterceptor that injects W3C traceparent and correlation IDs
 * into all outbound RestTemplate calls.
 */
public class TraceparentInterceptor implements ClientHttpRequestInterceptor {

    private final SecureRandom random = new SecureRandom();
    private final HexFormat hexFormat = HexFormat.of();

    @Override
    public ClientHttpResponse intercept(HttpRequest request, byte[] body, ClientHttpRequestExecution execution) throws IOException {
        String existingTraceparent = request.getHeaders().getFirst("traceparent");

        if (existingTraceparent == null || existingTraceparent.isBlank()) {
            String incomingTraceparent = null;
            String correlationId = null;

            ServletRequestAttributes attributes = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            if (attributes != null) {
                HttpServletRequest servletRequest = attributes.getRequest();
                incomingTraceparent = servletRequest.getHeader("traceparent");
                correlationId = servletRequest.getHeader("X-Correlation-Id");
            }

            String traceparent;
            if (incomingTraceparent != null && incomingTraceparent.matches("^00-[0-9a-f]{32}-[0-9a-f]{16}-[0-9a-f]{2}$")) {
                // Propagate incoming trace ID with a new child span ID
                String[] parts = incomingTraceparent.split("-");
                String traceId = parts[1];
                String childSpanId = generateSpanId();
                traceparent = String.format("00-%s-%s-01", traceId, childSpanId);
                if (correlationId == null) {
                    correlationId = traceId;
                }
            } else {
                // Generate a fresh W3C traceparent
                String traceId = generateTraceId();
                String spanId = generateSpanId();
                traceparent = String.format("00-%s-%s-01", traceId, spanId);
                if (correlationId == null) {
                    correlationId = traceId;
                }
            }

            request.getHeaders().add("traceparent", traceparent);
            if (!request.getHeaders().containsKey("X-Correlation-Id")) {
                request.getHeaders().add("X-Correlation-Id", correlationId);
            }
        }

        return execution.execute(request, body);
    }

    private String generateTraceId() {
        byte[] bytes = new byte[16];
        random.nextBytes(bytes);
        return hexFormat.formatHex(bytes);
    }

    private String generateSpanId() {
        byte[] bytes = new byte[8];
        random.nextBytes(bytes);
        return hexFormat.formatHex(bytes);
    }
}
