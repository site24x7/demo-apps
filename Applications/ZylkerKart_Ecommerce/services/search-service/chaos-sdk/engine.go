package chaos

import (
	"log"
	"math/rand"
	"strings"
	"sync"

	"github.com/pazhanir/site24x7-labs/sdks/go/internal"
)

// ---------------------------------------------------------------------------
// ChaosEngine — central orchestrator for fault rule management
// ---------------------------------------------------------------------------

// ConfigUpdateListener is called when the fault config changes.
type ConfigUpdateListener func()

// Engine manages fault rules, URL matching, and probability evaluation.
// It is thread-safe for concurrent access from HTTP handlers and goroutines.
type Engine struct {
	mu        sync.RWMutex
	rules     []FaultRuleConfig
	enabled   bool
	matcher   *internal.URLMatcher
	listeners []ConfigUpdateListener
}

// NewEngine creates a new ChaosEngine.
func NewEngine() *Engine {
	return &Engine{
		enabled: true,
		matcher: internal.NewURLMatcher(),
	}
}

// SetEnabled toggles fault injection on or off.
func (e *Engine) SetEnabled(enabled bool) {
	e.mu.Lock()
	e.enabled = enabled
	e.mu.Unlock()
}

// Enabled returns whether fault injection is active.
func (e *Engine) Enabled() bool {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return e.enabled
}

// UpdateRules replaces the current set of fault rules (called by ConfigFileWatcher).
func (e *Engine) UpdateRules(rules []FaultRuleConfig) {
	e.mu.Lock()
	e.rules = rules
	e.mu.Unlock()

	// Notify listeners outside the lock
	e.mu.RLock()
	listeners := make([]ConfigUpdateListener, len(e.listeners))
	copy(listeners, e.listeners)
	e.mu.RUnlock()

	for _, fn := range listeners {
		fn()
	}
}

// AddConfigUpdateListener registers a callback invoked when rules change.
// Used by ResourceFaultInjector to trigger on config updates.
func (e *Engine) AddConfigUpdateListener(fn ConfigUpdateListener) {
	e.mu.Lock()
	e.listeners = append(e.listeners, fn)
	e.mu.Unlock()
}

// FindMatchingRules returns all enabled rules whose fault_type starts with prefix
// and whose url_pattern matches the given URL. An empty prefix matches all fault types.
// An empty url matches rules with no url_pattern.
func (e *Engine) FindMatchingRules(prefix string, url ...string) []FaultRuleConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()

	if !e.enabled {
		return nil
	}

	urlPath := ""
	if len(url) > 0 {
		urlPath = url[0]
	}

	var matched []FaultRuleConfig
	for _, rule := range e.rules {
		if !rule.Enabled {
			continue
		}
		if prefix != "" && !strings.HasPrefix(rule.FaultType, prefix) {
			continue
		}
		if urlPath != "" && rule.URLPattern != "" {
			if !e.matcher.Matches(rule.URLPattern, urlPath) {
				continue
			}
		}
		matched = append(matched, rule)
	}
	return matched
}

// ShouldFire evaluates whether a rule should fire based on its probability.
// Returns true with probability = rule.Probability (0.0–1.0).
func (e *Engine) ShouldFire(rule FaultRuleConfig) bool {
	if rule.Probability <= 0 {
		return false
	}
	if rule.Probability >= 1.0 {
		return true
	}
	return rand.Float64() < rule.Probability
}

// GetRules returns a copy of the current rules (for diagnostics).
func (e *Engine) GetRules() []FaultRuleConfig {
	e.mu.RLock()
	defer e.mu.RUnlock()
	out := make([]FaultRuleConfig, len(e.rules))
	copy(out, e.rules)
	return out
}

// logDebug logs a debug-level message with [chaos-sdk] prefix.
func logDebug(format string, args ...interface{}) {
	log.Printf("[chaos-sdk] "+format, args...)
}
