// Site24x7 Labs Chaos SDK for Go — Resource Fault Injector
//
// Unlike HTTP/DB/Redis faults (triggered per-request), resource faults are
// triggered when the config changes. The injector registers as a
// config-update listener on the ChaosEngine.
//
// 6 fault types:
//  1. thread_pool_exhaustion — Leaked goroutines blocked on a channel.
//  2. memory_pressure        — Allocate []byte slices and hold them.
//  3. cpu_burn               — LockOSThread + tight math loops.
//  4. gc_pressure            — Rapid short-lived allocations.
//  5. thread_deadlock        — Goroutines blocked on channel with no writer.
//  6. disk_fill              — Write temp files to consume disk space.
package fault

import (
	"fmt"
	"log"
	"math"
	"os"
	"path/filepath"
	"runtime"
	"sync/atomic"
	"time"

	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
)

// ---------------------------------------------------------------------------
// ResourceFaultInjector
// ---------------------------------------------------------------------------

// ResourceFaultInjector listens for config changes and injects resource
// exhaustion faults. Only one resource fault is active at a time.
type ResourceFaultInjector struct {
	engine *chaos.Engine
	active atomic.Bool
}

// NewResourceFaultInjector creates a new injector. Call Install() to register
// the config-update listener.
func NewResourceFaultInjector(engine *chaos.Engine) *ResourceFaultInjector {
	return &ResourceFaultInjector{engine: engine}
}

// Install registers this injector as a config-update listener on the engine.
// Call once after the engine is started.
func (r *ResourceFaultInjector) Install() {
	r.engine.AddConfigUpdateListener(func() {
		r.evaluateAndApply()
	})
	log.Println("[chaos-sdk] ResourceFaultInjector installed")
}

// evaluateAndApply finds the first matching resource fault rule and applies it.
func (r *ResourceFaultInjector) evaluateAndApply() {
	if !r.engine.Enabled() {
		return
	}
	if r.active.Load() {
		log.Println("[chaos-sdk] Resource fault already active, skipping")
		return
	}

	// Find the first matching resource fault rule
	rules := r.engine.FindMatchingRules("")
	for _, rule := range rules {
		if !chaos.ResourceFaultTypes[rule.FaultType] {
			continue
		}
		if !r.engine.ShouldFire(rule) {
			continue
		}

		switch rule.FaultType {
		case chaos.FaultThreadPoolExhaustion:
			r.applyThreadPoolExhaustion(rule)
		case chaos.FaultMemoryPressure:
			r.applyMemoryPressure(rule)
		case chaos.FaultCPUBurn:
			r.applyCPUBurn(rule)
		case chaos.FaultGCPressure:
			r.applyGCPressure(rule)
		case chaos.FaultThreadDeadlock:
			r.applyThreadDeadlock(rule)
		case chaos.FaultDiskFill:
			r.applyDiskFill(rule)
		default:
			log.Printf("[chaos-sdk] Unknown resource fault type: %s", rule.FaultType)
		}
		return // Only inject one at a time
	}
}

// ---------------------------------------------------------------------------
// 1. Thread pool exhaustion — leaked goroutines
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyThreadPoolExhaustion(rule chaos.FaultRuleConfig) {
	threadCount := chaos.Clamp(chaos.GetConfigInt(rule, "thread_count", 10), 1, 50)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting goroutine leak: %d goroutines for %dms", threadCount, durationMs)
	r.active.Store(true)

	// done channel is closed after duration to release all goroutines
	done := make(chan struct{})

	for i := 0; i < threadCount; i++ {
		go func() {
			// Block on a channel — simulates a leaked goroutine consuming
			// scheduler resources.
			block := make(chan struct{})
			select {
			case <-block: // never fires
			case <-done:
			}
		}()
	}

	// Cleanup after duration
	go func() {
		time.Sleep(time.Duration(durationMs) * time.Millisecond)
		close(done)
		r.active.Store(false)
		log.Println("[chaos-sdk] Goroutine leak fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 2. Memory pressure — allocate and hold []byte slices
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyMemoryPressure(rule chaos.FaultRuleConfig) {
	allocationMB := chaos.Clamp(chaos.GetConfigInt(rule, "allocation_mb", 64), 1, 512)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting memory pressure: %dMB for %dms", allocationMB, durationMs)
	r.active.Store(true)

	blocks := make([][]byte, 0, allocationMB)
	func() {
		defer func() {
			if rec := recover(); rec != nil {
				log.Printf("[chaos-sdk] Memory pressure: allocation error, holding partial (%d MB)", len(blocks))
			}
		}()
		for i := 0; i < allocationMB; i++ {
			block := make([]byte, 1024*1024) // 1 MB
			// Touch all pages to ensure real allocation
			for j := 0; j < len(block); j += 4096 {
				block[j] = byte(i & 0xff)
			}
			blocks = append(blocks, block)
		}
		log.Printf("[chaos-sdk] Memory pressure: allocated %dMB", allocationMB)
	}()

	// Hold for duration, then release
	go func() {
		time.Sleep(time.Duration(durationMs) * time.Millisecond)
		// Release references — GC will collect
		blocks = nil //nolint:ineffassign
		runtime.GC() // Hint GC
		r.active.Store(false)
		log.Println("[chaos-sdk] Memory pressure fault completed, memory released")
	}()
}

// ---------------------------------------------------------------------------
// 3. CPU burn — LockOSThread + tight math loops
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyCPUBurn(rule chaos.FaultRuleConfig) {
	threadCount := chaos.Clamp(chaos.GetConfigInt(rule, "thread_count", 2), 1, 8)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting CPU burn: %d threads for %dms", threadCount, durationMs)
	r.active.Store(true)

	deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
	var completed atomic.Int32

	for i := 0; i < threadCount; i++ {
		go func() {
			runtime.LockOSThread()
			defer runtime.UnlockOSThread()

			x := 1.1
			for time.Now().Before(deadline) {
				// Tight math loop — burns CPU
				for j := 0; j < 10000; j++ {
					x = math.Sin(x)*math.Cos(x) + math.Sqrt(math.Abs(x))
				}
			}
			_ = x // prevent optimisation

			if int(completed.Add(1)) == threadCount {
				r.active.Store(false)
				log.Printf("[chaos-sdk] CPU burn fault completed (%d threads)", threadCount)
			}
		}()
	}
}

// ---------------------------------------------------------------------------
// 4. GC pressure — rapid short-lived allocations
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyGCPressure(rule chaos.FaultRuleConfig) {
	allocRateMBPerSec := chaos.Clamp(chaos.GetConfigInt(rule, "allocation_rate_mb_per_sec", 10), 1, 100)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting GC pressure: %dMB/sec for %dms", allocRateMBPerSec, durationMs)
	r.active.Store(true)

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		interval := time.Duration(float64(time.Second) / float64(allocRateMBPerSec))
		if interval < time.Millisecond {
			interval = time.Millisecond
		}

		ticker := time.NewTicker(interval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				if time.Now().After(deadline) {
					r.active.Store(false)
					log.Println("[chaos-sdk] GC pressure fault completed")
					return
				}
				// Allocate 1 MB — immediately discard so GC must collect
				garbage := make([]byte, 1024*1024)
				garbage[0] = 1
				garbage[len(garbage)-1] = 1
				_ = garbage // goes out of scope, eligible for GC
			}
		}
	}()
}

// ---------------------------------------------------------------------------
// 5. Thread deadlock — goroutines blocked on channel with no writer
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyThreadDeadlock(rule chaos.FaultRuleConfig) {
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting simulated deadlock for %dms", durationMs)
	r.active.Store(true)

	// done channel released after duration
	done := make(chan struct{})

	// Create goroutines that simulate deadlock: each waits on a channel
	// that no other goroutine will ever write to.
	const deadlockedCount = 4
	for i := 0; i < deadlockedCount; i++ {
		go func(id int) {
			block := make(chan struct{})
			select {
			case <-block: // never fires — simulates deadlock
			case <-done:
			}
		}(i)
	}

	go func() {
		time.Sleep(time.Duration(durationMs) * time.Millisecond)
		close(done)
		r.active.Store(false)
		log.Println("[chaos-sdk] Simulated deadlock fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 6. Disk fill — write temp files
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyDiskFill(rule chaos.FaultRuleConfig) {
	allocationMB := chaos.Clamp(chaos.GetConfigInt(rule, "allocation_mb", 64), 1, 512)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 60000)

	log.Printf("[chaos-sdk] Injecting disk fill: %dMB for %dms", allocationMB, durationMs)
	r.active.Store(true)

	tempDir := os.TempDir()
	tempFiles := make([]string, 0, allocationMB)
	block := make([]byte, 1024*1024) // 1 MB
	for i := range block {
		block[i] = 0xAA
	}

	for i := 0; i < allocationMB; i++ {
		filePath := filepath.Join(tempDir, fmt.Sprintf("chaos-disk-fill-%d.tmp", i))
		if err := os.WriteFile(filePath, block, 0644); err != nil {
			log.Printf("[chaos-sdk] Disk fill: error writing %s: %v", filePath, err)
			break
		}
		tempFiles = append(tempFiles, filePath)
	}
	log.Printf("[chaos-sdk] Disk fill: wrote %dMB of temp files", len(tempFiles))

	// Hold for duration, then clean up
	go func() {
		time.Sleep(time.Duration(durationMs) * time.Millisecond)
		for _, fp := range tempFiles {
			_ = os.Remove(fp) // ignore errors
		}
		r.active.Store(false)
		log.Printf("[chaos-sdk] Disk fill fault completed, %d temp files cleaned up", len(tempFiles))
	}()
}
