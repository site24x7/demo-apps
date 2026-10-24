// Site24x7 Labs Chaos SDK for Go — Health/Observability Path Exclusion
//
// Hard-coded set of health/readiness/observability endpoints that chaos must
// never touch. Affecting these paths would let monitoring systems (and
// orchestrators) detect that failures are externally induced — or, worse,
// trigger pod restarts and mask the experiment. The exclusion is
// non-negotiable and intentionally not configurable.

package chaos

import "strings"

// excludedExact is the exact-match set of excluded paths (lower-cased).
var excludedExact = map[string]bool{
	"/health":     true,
	"/healthz":    true,
	"/ready":      true,
	"/readyz":     true,
	"/live":       true,
	"/livez":      true,
	"/liveness":   true,
	"/readiness":  true,
	"/_health":    true,
	"/ping":       true,
	"/status":     true,
	"/metrics":    true,
	"/prometheus": true,
}

// excludedPrefixes is the prefix-match set of excluded paths (lower-cased).
var excludedPrefixes = []string{
	"/actuator",    // Spring Boot Actuator style (health, info, metrics, ...)
	"/management",  // common management context path
	"/.well-known", // probes / discovery
}

// IsExcluded reports whether the request path is a health/observability
// endpoint that must be excluded from fault injection. The path is
// lower-cased, query string stripped, and a trailing slash (except root)
// removed before matching.
func IsExcluded(path string) bool {
	if path == "" {
		return false
	}
	p := strings.ToLower(path)
	if q := strings.IndexByte(p, '?'); q >= 0 {
		p = p[:q]
	}
	// Normalize a trailing slash (but keep root "/").
	if len(p) > 1 && strings.HasSuffix(p, "/") {
		p = p[:len(p)-1]
	}
	if excludedExact[p] {
		return true
	}
	for _, prefix := range excludedPrefixes {
		if p == prefix || strings.HasPrefix(p, prefix+"/") {
			return true
		}
	}
	return false
}
