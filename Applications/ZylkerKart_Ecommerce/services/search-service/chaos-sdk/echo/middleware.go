// Site24x7 Labs Chaos SDK for Go — Echo Framework Adapter
//
// Thin adapter that wraps the net/http fault middleware for use with
// the Echo web framework.
//
// Usage:
//
//	e := echo.New()
//	e.Use(echomw.ChaosMiddleware(engine))

package echomw

import (
	"net/http"

	"github.com/labstack/echo/v4"
	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
	"github.com/pazhanir/site24x7-labs/sdks/go/fault"
)

// ChaosMiddleware returns an echo.MiddlewareFunc that injects inbound HTTP faults.
func ChaosMiddleware(engine *chaos.Engine) echo.MiddlewareFunc {
	middleware := fault.HTTPMiddleware(engine)

	return func(next echo.HandlerFunc) echo.HandlerFunc {
		return func(c echo.Context) error {
			// Track whether the chaos middleware passed through to next
			var nextErr error
			proceeded := false

			handler := middleware(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				proceeded = true
				nextErr = next(c)
			}))

			handler.ServeHTTP(c.Response(), c.Request())

			if proceeded {
				return nextErr
			}
			// Chaos middleware handled the response (fault injected)
			return nil
		}
	}
}
