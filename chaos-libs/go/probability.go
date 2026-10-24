// Site24x7 Labs Chaos SDK for Go — Probability Onset Shaping
//
// Computes the effective firing probability for a fault rule at the moment it
// is evaluated, so that injected failures ramp in naturally instead of
// switching on at full rate. Two onset shapes are supported via the rule
// config:
//
//   - "gradual" — probability ramps linearly from start_probability to the
//     rule's base probability over ramp_seconds. Mirrors a real degradation
//     that worsens over time.
//   - "bursty"  — the base probability is multiplied by burst_factor (default
//     2x) during deterministic burst windows, emulating intermittent spikes.
//
// When no onset is configured the rule's base probability is used unchanged.
// First-seen time is tracked per rule (keyed by rule id) and pruned when a
// rule disappears from config.

package chaos

import (
	"sync"
	"time"
)

// nowFunc is a clock seam for deterministic testing.
type nowFunc func() time.Time

// ProbabilityEngine computes onset-shaped firing probabilities and tracks each
// rule's first-seen time. It is safe for concurrent use.
type ProbabilityEngine struct {
	mu        sync.Mutex
	firstSeen map[string]time.Time
	now       nowFunc
}

// NewProbabilityEngine creates a ProbabilityEngine using the wall clock.
func NewProbabilityEngine() *ProbabilityEngine {
	return &ProbabilityEngine{
		firstSeen: make(map[string]time.Time),
		now:       time.Now,
	}
}

func ruleKey(rule FaultRuleConfig) string {
	if rule.ID != "" {
		return rule.ID
	}
	return rule.FaultType
}

// EffectiveProbability computes the effective probability for a rule at the
// given time, applying any gradual ramp or burst shaping on top of the rule's
// base probability. Result is clamped to [0,1].
func (p *ProbabilityEngine) EffectiveProbability(rule FaultRuleConfig, now time.Time) float64 {
	base := rule.Probability
	onset := GetConfigString(rule, "onset", "")

	key := ruleKey(rule)
	p.mu.Lock()
	first, ok := p.firstSeen[key]
	if !ok {
		first = now
		p.firstSeen[key] = first
	}
	p.mu.Unlock()

	elapsed := now.Sub(first).Seconds()
	if elapsed < 0 {
		elapsed = 0
	}

	switch onset {
	case "gradual":
		start := ClampFloat(GetConfigFloat(rule, "start_probability", 0.0), 0, 1)
		ramp := GetConfigFloat(rule, "ramp_seconds", 60.0)
		if ramp < 0.001 {
			ramp = 0.001
		}
		if elapsed >= ramp {
			return ClampFloat(base, 0, 1)
		}
		frac := elapsed / ramp
		return ClampFloat(start+(base-start)*frac, 0, 1)
	case "bursty":
		factor := GetConfigFloat(rule, "burst_factor", 2.0)
		if p.inBurstWindow(rule, now) {
			return ClampFloat(base*factor, 0, 1)
		}
		return ClampFloat(base, 0, 1)
	default:
		return ClampFloat(base, 0, 1)
	}
}

// inBurstWindow reports whether now falls in an active burst window.
// burst_period_seconds is the full cycle length; burst_active_seconds is how
// much of each cycle is "bursting".
func (p *ProbabilityEngine) inBurstWindow(rule FaultRuleConfig, now time.Time) bool {
	period := GetConfigFloat(rule, "burst_period_seconds", 30.0)
	if period < 1.0 {
		period = 1.0
	}
	active := GetConfigFloat(rule, "burst_active_seconds", 10.0)
	if active < 0 {
		active = 0
	}
	nowSeconds := float64(now.Unix())
	posInCycle := nowSeconds - period*float64(int64(nowSeconds/period))
	return posInCycle < active
}

// RetainOnly drops first-seen tracking for rules no longer present, so a
// re-added rule restarts its onset cleanly.
func (p *ProbabilityEngine) RetainOnly(liveKeys map[string]bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for k := range p.firstSeen {
		if !liveKeys[k] {
			delete(p.firstSeen, k)
		}
	}
}
