package chaos

import (
	"log"
	"math/rand"
	"strings"
	"sync"
	"time"

	"github.com/site24x7/observe-labs/sdks/go/internal"
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
	prob      *ProbabilityEngine
}

// NewEngine creates a new ChaosEngine.
func NewEngine() *Engine {
	return &Engine{
		enabled: true,
		matcher: internal.NewURLMatcher(),
		prob:    NewProbabilityEngine(),
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

// UpdateRules replaces the current set of fault rules (called by ConfigFileWatcher
// and the UDS client). Probability onset state is pruned for rules no longer present.
func (e *Engine) UpdateRules(rules []FaultRuleConfig) {
	e.mu.Lock()
	e.rules = rules
	e.mu.Unlock()

	// Prune onset tracking for rules that have disappeared.
	live := make(map[string]bool, len(rules))
	for _, r := range rules {
		live[ruleKey(r)] = true
	}
	e.prob.RetainOnly(live)

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
//
// If rules were already loaded before this listener was registered (race
// condition where ConfigFileWatcher fires before ResourceFaultInjector.Install()),
// the listener is invoked immediately so it doesn't miss the initial config.
func (e *Engine) AddConfigUpdateListener(fn ConfigUpdateListener) {
	e.mu.Lock()
	e.listeners = append(e.listeners, fn)
	hasRules := len(e.rules) > 0
	ruleCount := len(e.rules)
	e.mu.Unlock()

	// If rules were already loaded, invoke the listener immediately.
	if hasRules {
		log.Printf("[chaos-sdk] Invoking new config listener immediately — %d active rules already loaded", ruleCount)
		fn()
	}
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

	// Health/observability endpoints are never faulted.
	if urlPath != "" && IsExcluded(urlPath) {
		return nil
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

// ShouldFire evaluates whether a rule should fire based on its effective
// probability, applying onset shaping (gradual ramp / bursty) over the rule's
// base probability.
func (e *Engine) ShouldFire(rule FaultRuleConfig) bool {
	p := e.prob.EffectiveProbability(rule, time.Now())
	if p <= 0 {
		return false
	}
	if p >= 1.0 {
		return true
	}
	return rand.Float64() < p
}

// ClearRules drops all active rules immediately (UDS kill switch). Listeners
// are notified so resource injectors can release held resources.
func (e *Engine) ClearRules() {
	e.UpdateRules(nil)
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
