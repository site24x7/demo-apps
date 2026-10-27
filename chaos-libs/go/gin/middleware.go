// Site24x7 Labs Chaos SDK for Go — Gin Framework Adapter
//
// Thin adapter that wraps the net/http fault middleware for use with
// the Gin web framework.
//
// Usage:
//
//	r := gin.Default()
//	r.Use(ginmw.ChaosMiddleware(engine))

package ginmw

import (
	"net/http"

	"github.com/gin-gonic/gin"
	chaos "github.com/site24x7/observe-labs/sdks/go"
	"github.com/site24x7/observe-labs/sdks/go/fault"
)

// ChaosMiddleware returns a gin.HandlerFunc that injects inbound HTTP faults.
func ChaosMiddleware(engine *chaos.Engine) gin.HandlerFunc {
	// Build the underlying net/http middleware
	middleware := fault.HTTPMiddleware(engine)

	return func(c *gin.Context) {
		// Wrap gin's next handler as an http.Handler
		proceeded := false
		next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			proceeded = true
			c.Next()
		})

		// Run the chaos middleware
		middleware(next).ServeHTTP(c.Writer, c.Request)

		// When the fault answered the request itself, stop Gin's chain:
		// otherwise Gin runs the remaining handlers after this middleware
		// returns, and the real handler executes (and writes) anyway.
		if !proceeded {
			c.Abort()
		}
	}
}
