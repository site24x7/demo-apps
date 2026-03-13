// Site24x7 Labs Chaos SDK for Go — Outbound HTTP Client Fault Injector
//
// Implements http.RoundTripper to intercept outbound HTTP calls and inject
// 4 fault types:
//   1. http_client_latency            — Delay before the outbound call proceeds.
//   2. http_client_exception          — Return an error instead of making the call.
//   3. http_client_error_response     — Return a fake error response.
//   4. http_client_partial_response   — Return a truncated response body.

package fault

import (
	"bytes"
	"io"
	"log"
	"net/http"
	"time"

	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
)

const httpClientFaultPrefix = "http_client_"

// ChaosTransport is an http.RoundTripper that wraps a base transport and
// injects outbound HTTP client faults.
type ChaosTransport struct {
	Base   http.RoundTripper
	Engine *chaos.Engine
}

// NewTransport creates a ChaosTransport wrapping the given base transport.
// If base is nil, http.DefaultTransport is used.
func NewTransport(engine *chaos.Engine, base http.RoundTripper) *ChaosTransport {
	if base == nil {
		base = http.DefaultTransport
	}
	return &ChaosTransport{
		Base:   base,
		Engine: engine,
	}
}

// RoundTrip implements http.RoundTripper.
func (t *ChaosTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	if !t.Engine.Enabled() {
		return t.Base.RoundTrip(req)
	}

	url := req.URL.Path
	rules := t.Engine.FindMatchingRules(httpClientFaultPrefix, url)

	for _, rule := range rules {
		if !t.Engine.ShouldFire(rule) {
			continue
		}

		switch rule.FaultType {
		case chaos.FaultHTTPClientLatency:
			delayMs := chaos.GetConfigInt(rule, "delay_ms", 3000)
			log.Printf("[chaos-sdk] Injecting HTTP client latency: %dms on %s", delayMs, url)
			time.Sleep(time.Duration(delayMs) * time.Millisecond)
			// Fall through to the real request after delay
			return t.Base.RoundTrip(req)

		case chaos.FaultHTTPClientException:
			javaClass := chaos.GetConfigString(rule, "exception_class", "ResourceAccessException")
			message := chaos.GetConfigString(rule, "message", "Injected outbound fault")
			log.Printf("[chaos-sdk] Injecting HTTP client exception: %s - %s on %s", javaClass, message, url)
			return nil, chaos.ResolveException(javaClass, message)

		case chaos.FaultHTTPClientErrorResponse:
			statusCode := chaos.GetConfigInt(rule, "status_code", 503)
			body := chaos.GetConfigString(rule, "body", "Service Unavailable")
			log.Printf("[chaos-sdk] Injecting HTTP client error response: %d on %s", statusCode, url)
			return &http.Response{
				StatusCode: statusCode,
				Status:     http.StatusText(statusCode),
				Header:     http.Header{"Content-Type": {"text/plain"}},
				Body:       io.NopCloser(bytes.NewBufferString(body)),
				Request:    req,
			}, nil

		case chaos.FaultHTTPClientPartialResponse:
			statusCode := chaos.GetConfigInt(rule, "status_code", 200)
			body := chaos.GetConfigString(rule, "body", `{"data":[{"id":1,"name":"item"`)
			truncatePct := chaos.Clamp(chaos.GetConfigInt(rule, "truncate_percentage", 50), 10, 90)

			truncLen := len(body) * truncatePct / 100
			if truncLen < 1 {
				truncLen = 1
			}
			truncatedBody := body[:truncLen]

			log.Printf("[chaos-sdk] Injecting HTTP client partial response: %d%% of body on %s", truncatePct, url)
			return &http.Response{
				StatusCode: statusCode,
				Status:     http.StatusText(statusCode),
				Header:     http.Header{"Content-Type": {"application/json"}},
				Body:       io.NopCloser(bytes.NewBufferString(truncatedBody)),
				Request:    req,
			}, nil

		default:
			log.Printf("[chaos-sdk] Unknown HTTP client fault type: %s", rule.FaultType)
		}
	}

	return t.Base.RoundTrip(req)
}
