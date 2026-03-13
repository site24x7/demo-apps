package com.site24x7.labs.chaos.spring;

import com.site24x7.labs.chaos.fault.httpclient.HttpClientFaultInjector;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpRequest;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.ClientHttpRequestExecution;
import org.springframework.http.client.ClientHttpRequestInterceptor;
import org.springframework.http.client.ClientHttpResponse;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;

/**
 * Spring RestTemplate interceptor that injects outbound HTTP faults.
 * <p>
 * Intercepts all outbound HTTP calls made via RestTemplate and evaluates
 * fault rules before the actual request is made.
 * <p>
 * Supports:
 * - http_client_exception: throws exception before outbound call
 * - http_client_latency: injects delay before outbound call
 * - http_client_error_response: returns fake error response without making the call
 * - http_client_partial_response: returns truncated response body (simulates TCP reset)
 */
public class ChaosClientHttpRequestInterceptor implements ClientHttpRequestInterceptor {

    private final HttpClientFaultInjector faultInjector;

    public ChaosClientHttpRequestInterceptor(HttpClientFaultInjector faultInjector) {
        this.faultInjector = faultInjector;
    }

    @Override
    public ClientHttpResponse intercept(HttpRequest request, byte[] body,
                                         ClientHttpRequestExecution execution) throws IOException {
        URI uri = request.getURI();
        String url = uri.getPath();

        HttpClientFaultInjector.FaultResult result = faultInjector.applyFault(url);

        if (result.isFaultApplied() && "http_client_error_response".equals(result.getFaultType())) {
            // Return a fake error response
            return new FakeClientHttpResponse(result.getStatusCode(), result.getBody());
        }

        if (result.isFaultApplied() && "http_client_partial_response".equals(result.getFaultType())) {
            // Return a truncated response (body already truncated by injector)
            return new FakeClientHttpResponse(result.getStatusCode(), result.getBody());
        }

        // No response-level fault (exception/latency already applied by injector)
        return execution.execute(request, body);
    }

    /**
     * Fake ClientHttpResponse for error response injection.
     */
    private static class FakeClientHttpResponse implements ClientHttpResponse {
        private final int statusCode;
        private final String body;

        FakeClientHttpResponse(int statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body != null ? body : "";
        }

        @Override
        public HttpStatusCode getStatusCode() {
            return HttpStatusCode.valueOf(statusCode);
        }

        @Override
        public String getStatusText() {
            return "Chaos Fault Injected";
        }

        @Override
        public void close() {
            // No-op
        }

        @Override
        public InputStream getBody() {
            return new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8));
        }

        @Override
        public HttpHeaders getHeaders() {
            HttpHeaders headers = new HttpHeaders();
            headers.set("Content-Type", "text/plain");
            headers.set("X-Chaos-Fault", "http_client_error_response");
            return headers;
        }
    }
}
