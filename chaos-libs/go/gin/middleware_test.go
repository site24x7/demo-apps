package ginmw

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	chaos "github.com/site24x7/observe-labs/sdks/go"
)

func engineWith(t *testing.T, rules ...chaos.FaultRuleConfig) *chaos.Engine {
	t.Helper()
	e := chaos.NewEngine()
	e.UpdateRules(rules)
	return e
}

// A fault that answers the request must stop the chain: the handler must not
// run, nor write after the fault.
func TestFaultStopsHandler(t *testing.T) {
	gin.SetMode(gin.TestMode)
	ran := false
	r := gin.New()
	r.Use(ChaosMiddleware(engineWith(t, chaos.FaultRuleConfig{
		ID: "r", FaultType: chaos.FaultHTTPErrorResponse, Enabled: true, Probability: 1,
		Config: map[string]interface{}{"status_code": 503.0, "body": "chaos"},
	})))
	r.GET("/x", func(c *gin.Context) { ran = true; c.String(200, "handler") })

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/x", nil))
	if ran {
		t.Fatal("handler ran after the fault answered the request")
	}
	if w.Code != 503 || w.Body.String() != "chaos" {
		t.Fatalf("got %d %q, want 503 chaos", w.Code, w.Body.String())
	}
}

// Latency delays but still runs the handler, once.
func TestLatencyRunsHandlerOnce(t *testing.T) {
	gin.SetMode(gin.TestMode)
	runs := 0
	r := gin.New()
	r.Use(ChaosMiddleware(engineWith(t, chaos.FaultRuleConfig{
		ID: "r", FaultType: chaos.FaultHTTPLatency, Enabled: true, Probability: 1,
		Config: map[string]interface{}{"delay_ms": 10.0},
	})))
	r.GET("/x", func(c *gin.Context) { runs++; c.String(200, "ok") })

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/x", nil))
	if runs != 1 || w.Body.String() != "ok" {
		t.Fatalf("handler ran %d times, body %q", runs, w.Body.String())
	}
}

// An outbound http_client_* rule must not fault inbound requests.
func TestClientRuleIgnoredInbound(t *testing.T) {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(ChaosMiddleware(engineWith(t, chaos.FaultRuleConfig{
		ID: "r", FaultType: "http_client_error_response", Enabled: true, Probability: 1,
		Config: map[string]interface{}{"status_code": 503.0},
	})))
	r.GET("/x", func(c *gin.Context) { c.String(200, "ok") })

	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/x", nil))
	if w.Code != 200 {
		t.Fatalf("inbound request got %d from an outbound rule", w.Code)
	}
}
