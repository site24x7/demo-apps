// Site24x7 Labs Chaos SDK for Go — Redis Fault Injector
//
// Implements the go-redis/redis/v9 redis.Hook interface to intercept
// Redis commands and inject 2 fault types:
//   1. redis_exception  — Return a mapped error before the command runs.
//   2. redis_latency    — Delay before the command runs.
//
// Usage:
//
//	rdb := redis.NewClient(&redis.Options{...})
//	rdb.AddHook(fault.NewRedisHook(engine))

package fault

import (
	"context"
	"log"
	"net"
	"time"

	"github.com/redis/go-redis/v9"

	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
)

const redisFaultPrefix = "redis_"

// RedisHook implements the go-redis Hook interface for chaos fault injection.
type RedisHook struct {
	engine *chaos.Engine
}

// NewRedisHook creates a Redis hook that injects faults.
func NewRedisHook(engine *chaos.Engine) *RedisHook {
	return &RedisHook{engine: engine}
}

// DialHook is not used — we only inject on commands.
func (h *RedisHook) DialHook(next redis.DialHook) redis.DialHook {
	return next
}

// ProcessHook intercepts single Redis commands.
func (h *RedisHook) ProcessHook(next redis.ProcessHook) redis.ProcessHook {
	return func(ctx context.Context, cmd redis.Cmder) error {
		if err := h.evaluateFaults(); err != nil {
			cmd.SetErr(err)
			return err
		}
		return next(ctx, cmd)
	}
}

// ProcessPipelineHook intercepts pipelined Redis commands.
func (h *RedisHook) ProcessPipelineHook(next redis.ProcessPipelineHook) redis.ProcessPipelineHook {
	return func(ctx context.Context, cmds []redis.Cmder) error {
		if err := h.evaluateFaults(); err != nil {
			for _, cmd := range cmds {
				cmd.SetErr(err)
			}
			return err
		}
		return next(ctx, cmds)
	}
}

func (h *RedisHook) evaluateFaults() error {
	if !h.engine.Enabled() {
		return nil
	}

	rules := h.engine.FindMatchingRules(redisFaultPrefix)
	for _, rule := range rules {
		if !h.engine.ShouldFire(rule) {
			continue
		}

		switch rule.FaultType {
		case chaos.FaultRedisException:
			javaClass := chaos.GetConfigString(rule, "exception_class", "RedisConnectionFailureException")
			message := chaos.GetConfigString(rule, "message", "Injected Redis fault")
			log.Printf("[chaos-sdk] Injecting Redis exception: %s - %s", javaClass, message)

			// Return a net.OpError to simulate a realistic Redis connection error
			return &net.OpError{
				Op:  "dial",
				Net: "tcp",
				Err: chaos.ResolveException(javaClass, message),
			}

		case chaos.FaultRedisLatency:
			delayMs := chaos.GetConfigInt(rule, "delay_ms", 3000)
			log.Printf("[chaos-sdk] Injecting Redis latency: %dms", delayMs)
			time.Sleep(time.Duration(delayMs) * time.Millisecond)
			return nil // Continue with real command after delay
		}
	}

	return nil
}
