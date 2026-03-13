// Site24x7 Labs Chaos SDK for Go — Inbound HTTP Fault Middleware
//
// net/http middleware that intercepts incoming requests and injects
// 5 fault types:
//   1. http_exception       — Return the mapped Go error as a 500 response.
//   2. http_latency         — Delay before the request is handled.
//   3. http_error_response  — Return a static error status + body.
//   4. http_connection_reset— Hijack and close the connection.
//   5. http_slow_body       — Stream a response body with inter-chunk delays.

package fault

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"strings"
	"time"

	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
)

const httpFaultPrefix = "http_"

// HTTPMiddleware returns an http.Handler that evaluates inbound HTTP fault
// rules before delegating to the next handler.
func HTTPMiddleware(engine *chaos.Engine) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if !engine.Enabled() {
				next.ServeHTTP(w, r)
				return
			}

			// Match rules against the request path
			rules := engine.FindMatchingRules(httpFaultPrefix, r.URL.Path)

			for _, rule := range rules {
				if !engine.ShouldFire(rule) {
					continue
				}

				switch rule.FaultType {
				case chaos.FaultHTTPException:
					applyHTTPException(w, rule)
					return
				case chaos.FaultHTTPLatency:
					applyHTTPLatency(rule)
					// Fall through to next handler after delay
					next.ServeHTTP(w, r)
					return
				case chaos.FaultHTTPErrorResponse:
					applyHTTPErrorResponse(w, rule)
					return
				case chaos.FaultHTTPConnectionReset:
					applyHTTPConnectionReset(w)
					return
				case chaos.FaultHTTPSlowBody:
					applyHTTPSlowBody(w, rule)
					return
				default:
					log.Printf("[chaos-sdk] Unknown HTTP fault type: %s", rule.FaultType)
				}
			}

			// No fault fired — pass through
			next.ServeHTTP(w, r)
		})
	}
}

// ---------------------------------------------------------------------------
// Fault implementations
// ---------------------------------------------------------------------------

func applyHTTPException(w http.ResponseWriter, rule chaos.FaultRuleConfig) {
	javaClass := chaos.GetConfigString(rule, "exception_class", "java.lang.RuntimeException")
	message := chaos.GetConfigString(rule, "message", "Injected fault")

	log.Printf("[chaos-sdk] Injecting HTTP exception: %s - %s", javaClass, message)

	err := chaos.ResolveException(javaClass, message)
	http.Error(w, err.Error(), http.StatusInternalServerError)
}

func applyHTTPLatency(rule chaos.FaultRuleConfig) {
	delayMs := chaos.GetConfigInt(rule, "delay_ms", 1000)
	log.Printf("[chaos-sdk] Injecting HTTP latency: %dms", delayMs)
	time.Sleep(time.Duration(delayMs) * time.Millisecond)
}

func applyHTTPErrorResponse(w http.ResponseWriter, rule chaos.FaultRuleConfig) {
	statusCode := chaos.GetConfigInt(rule, "status_code", 500)
	body := chaos.GetConfigString(rule, "body", "Internal Server Error")

	log.Printf("[chaos-sdk] Injecting HTTP error response: %d - %s", statusCode, body)

	w.Header().Set("Content-Type", "text/plain")
	w.WriteHeader(statusCode)
	fmt.Fprint(w, body)
}

func applyHTTPConnectionReset(w http.ResponseWriter) {
	log.Printf("[chaos-sdk] Injecting HTTP connection reset")

	// Hijack the connection and close it immediately
	hijacker, ok := w.(http.Hijacker)
	if !ok {
		// Fallback: just close with an error
		http.Error(w, "Connection reset", http.StatusBadGateway)
		return
	}

	conn, _, err := hijacker.Hijack()
	if err != nil {
		http.Error(w, "Connection reset", http.StatusBadGateway)
		return
	}

	// Set TCP RST via linger = 0
	if tcpConn, ok := conn.(*net.TCPConn); ok {
		_ = tcpConn.SetLinger(0)
	}
	_ = conn.Close()
}

func applyHTTPSlowBody(w http.ResponseWriter, rule chaos.FaultRuleConfig) {
	delayMs := chaos.GetConfigInt(rule, "delay_ms", 200)
	chunkSize := chaos.GetConfigInt(rule, "chunk_size_bytes", 64)
	totalChunks := 32

	log.Printf("[chaos-sdk] Injecting HTTP slow body: %dms delay, %d byte chunks", delayMs, chunkSize)

	w.Header().Set("Content-Type", "text/plain")
	w.Header().Set("Transfer-Encoding", "chunked")
	w.WriteHeader(http.StatusOK)

	flusher, canFlush := w.(http.Flusher)
	chunk := strings.Repeat("X", chunkSize)

	for i := 0; i < totalChunks; i++ {
		_, err := fmt.Fprint(w, chunk)
		if err != nil {
			return // Client disconnected
		}
		if canFlush {
			flusher.Flush()
		}
		time.Sleep(time.Duration(delayMs) * time.Millisecond)
	}
}
