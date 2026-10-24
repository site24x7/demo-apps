// Site24x7 Labs Chaos SDK for Go — Resource Fault Injector
//
// Unlike HTTP/DB/Redis faults (triggered per-request), resource faults are
// triggered when the config changes. The injector registers as a
// config-update listener on the ChaosEngine.
//
// 15 fault types:
//  1. thread_pool_exhaustion — Leaked goroutines blocked on a channel.
//  2. memory_pressure        — Allocate []byte slices and hold them.
//  3. cpu_burn               — LockOSThread + tight math loops.
//  4. gc_pressure            — Rapid short-lived allocations.
//  5. thread_deadlock        — Goroutines blocked on channel with no writer.
//  6. disk_fill              — Write temp files to consume disk space.
//  7. process_exit           — Terminate the process (crash simulation).
//  8. log_flood              — Write random data to stderr at high rate.
//  9. connpool_exhaust       — Open and hold N TCP connections to a target.
//
// 10. startup_delay          — Sleep for delay_ms to simulate slow startup.
// 11. n_plus_one             — Fire N+1 queries via app's DB connection.
// 12. full_table_scan        — Run SELECT * without WHERE via app's DB.
// 13. thundering_herd        — Fire N concurrent identical queries via app's DB.
// 14. unbounded_query        — Run SELECT * on large table via app's DB.
// 15. connection_leak        — Open DB connections without closing them.
package fault

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"math"
	"math/rand"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	chaos "github.com/site24x7/observe-labs/sdks/go"
)

// ---------------------------------------------------------------------------
// ResourceFaultInjector
// ---------------------------------------------------------------------------

// ResourceFaultInjector listens for config changes and injects resource
// exhaustion faults. Only one resource fault is active at a time.
type ResourceFaultInjector struct {
	engine *chaos.Engine
	active atomic.Bool

	// db is the app's own database connection, registered via RegisterDB().
	// Used by app-induced DB faults (n_plus_one, full_table_scan, etc.)
	dbMu sync.RWMutex
	db   *sql.DB
	// leakedConns holds connections opened by connection_leak fault
	leakedConns []*sql.DB
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

// RegisterDB registers the app's database connection with the injector.
// This enables app-induced DB fault types (n_plus_one, full_table_scan, etc.).
// Call this once at app startup after opening the DB connection.
//
//	db, _ := sql.Open("mysql", dsn)
//	injector.RegisterDB(db)
func (r *ResourceFaultInjector) RegisterDB(db *sql.DB) {
	r.dbMu.Lock()
	r.db = db
	r.dbMu.Unlock()
	log.Println("[chaos-sdk] DB connection registered for app-induced fault injection")
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
		case chaos.FaultProcessExit:
			r.applyProcessExit(rule)
		case chaos.FaultLogFlood:
			r.applyLogFlood(rule)
		case chaos.FaultConnPoolExhaust:
			r.applyConnPoolExhaust(rule)
		case chaos.FaultStartupDelay:
			r.applyStartupDelay(rule)
		case chaos.FaultNPlusOne:
			r.applyNPlusOne(rule)
		case chaos.FaultFullTableScan:
			r.applyFullTableScan(rule)
		case chaos.FaultThunderingHerd:
			r.applyThunderingHerd(rule)
		case chaos.FaultUnboundedQuery:
			r.applyUnboundedQuery(rule)
		case chaos.FaultConnectionLeak:
			r.applyConnectionLeak(rule)
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

// ---------------------------------------------------------------------------
// 7. Process exit — terminate the process to simulate a crash
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyProcessExit(rule chaos.FaultRuleConfig) {
	delaySeconds := chaos.Clamp(chaos.GetConfigInt(rule, "delay_seconds", 0), 0, 60)
	exitCode := chaos.Clamp(chaos.GetConfigInt(rule, "exit_code", 1), 1, 255)

	log.Printf("[chaos-sdk] Injecting process exit: exit_code=%d delay=%ds", exitCode, delaySeconds)
	r.active.Store(true)

	go func() {
		if delaySeconds > 0 {
			log.Printf("[chaos-sdk] Process exit: waiting %ds before terminating...", delaySeconds)
			time.Sleep(time.Duration(delaySeconds) * time.Second)
		}
		log.Printf("[chaos-sdk] CHAOS FAULT: Terminating process with exit code %d — simulating application crash", exitCode)
		// Use os.Exit() for immediate termination — K8s will detect
		// the container exit and restart the pod.
		os.Exit(exitCode)
	}()
}

// ---------------------------------------------------------------------------
// 8. Log flood — write random data to stderr at high rate
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyLogFlood(rule chaos.FaultRuleConfig) {
	rateMBPerSec := chaos.Clamp(chaos.GetConfigInt(rule, "rate_mb_per_sec", 5), 1, 50)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting log flood: %dMB/sec for %dms", rateMBPerSec, durationMs)
	r.active.Store(true)

	chunk := make([]byte, 1024*1024)
	for i := range chunk {
		chunk[i] = byte(0x20 + rand.Intn(95)) // printable ASCII
	}

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-ticker.C:
				if time.Now().After(deadline) {
					r.active.Store(false)
					log.Println("[chaos-sdk] Log flood fault completed")
					return
				}
				for i := 0; i < rateMBPerSec; i++ {
					chunk[rand.Intn(len(chunk))] = byte(rand.Intn(256))
					os.Stderr.Write(chunk) //nolint:errcheck
				}
			}
		}
	}()
}

// ---------------------------------------------------------------------------
// 9. Connection pool exhaust — open and hold N TCP connections
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyConnPoolExhaust(rule chaos.FaultRuleConfig) {
	connCount := chaos.Clamp(chaos.GetConfigInt(rule, "connection_count", 50), 1, 500)
	host := chaos.GetConfigString(rule, "db_host", "localhost")
	port := chaos.GetConfigInt(rule, "db_port", 5432)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)
	addr := net.JoinHostPort(host, strconv.Itoa(port))

	log.Printf("[chaos-sdk] Injecting connpool exhaustion: %d connections to %s for %dms", connCount, addr, durationMs)
	r.active.Store(true)

	conns := make([]net.Conn, 0, connCount)
	for i := 0; i < connCount; i++ {
		c, err := net.DialTimeout("tcp", addr, 2*time.Second)
		if err != nil {
			log.Printf("[chaos-sdk] ConnPool: connection %d failed: %v", i, err)
			break
		}
		conns = append(conns, c)
	}
	log.Printf("[chaos-sdk] ConnPool: holding %d connections to %s", len(conns), addr)

	go func() {
		time.Sleep(time.Duration(durationMs) * time.Millisecond)
		for _, c := range conns {
			c.Close() //nolint:errcheck
		}
		r.active.Store(false)
		log.Printf("[chaos-sdk] ConnPool exhaustion fault completed, %d connections released", len(conns))
	}()
}

// ---------------------------------------------------------------------------
// 10. Startup delay — sleep for delay_ms inside the application process
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyStartupDelay(rule chaos.FaultRuleConfig) {
	delayMs := chaos.Clamp(chaos.GetConfigInt(rule, "delay_ms", 5000), 100, 120000)

	log.Printf("[chaos-sdk] Injecting startup delay: %dms", delayMs)
	r.active.Store(true)

	go func() {
		time.Sleep(time.Duration(delayMs) * time.Millisecond)
		r.active.Store(false)
		log.Printf("[chaos-sdk] Startup delay fault completed (%dms elapsed)", delayMs)
	}()
}

// ---------------------------------------------------------------------------
// App-induced DB fault helpers
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) getDB() *sql.DB {
	r.dbMu.RLock()
	defer r.dbMu.RUnlock()
	return r.db
}

// ---------------------------------------------------------------------------
// 11. N+1 query — fetch N rows then do individual lookups (classic N+1)
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyNPlusOne(rule chaos.FaultRuleConfig) {
	db := r.getDB()
	if db == nil {
		log.Println("[chaos-sdk] n_plus_one: no DB registered — call injector.RegisterDB(db) at app startup")
		return
	}
	primaryTable := chaos.GetConfigString(rule, "primary_table", "orders")
	relatedTable := chaos.GetConfigString(rule, "related_table", "order_items")
	joinColumn := chaos.GetConfigString(rule, "join_column", "order_id")
	rowCount := chaos.Clamp(chaos.GetConfigInt(rule, "row_count", 50), 1, 500)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting N+1 query: %s → %s x%d for %dms",
		primaryTable, relatedTable, rowCount, durationMs)
	r.active.Store(true)

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		for time.Now().Before(deadline) {
			rows, err := db.QueryContext(context.Background(),
				fmt.Sprintf("SELECT id FROM %s LIMIT %d", primaryTable, rowCount))
			if err != nil {
				log.Printf("[chaos-sdk] n_plus_one: primary query failed: %v", err)
				break
			}
			var ids []interface{}
			for rows.Next() {
				var id interface{}
				if rows.Scan(&id) == nil {
					ids = append(ids, id)
				}
			}
			rows.Close()
			// The N+1: one extra query per row
			for _, id := range ids {
				db.QueryRowContext(context.Background(),
					fmt.Sprintf("SELECT * FROM %s WHERE %s = ?", relatedTable, joinColumn), id) //nolint:errcheck
			}
			time.Sleep(500 * time.Millisecond)
		}
		r.active.Store(false)
		log.Println("[chaos-sdk] N+1 query fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 12. Full table scan — SELECT * without WHERE on app table
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyFullTableScan(rule chaos.FaultRuleConfig) {
	db := r.getDB()
	if db == nil {
		log.Println("[chaos-sdk] full_table_scan: no DB registered — call injector.RegisterDB(db) at app startup")
		return
	}
	tableName := chaos.GetConfigString(rule, "table_name", "orders")
	rowLimit := chaos.Clamp(chaos.GetConfigInt(rule, "row_limit", 10000), 100, 1000000)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting full table scan: SELECT * FROM %s LIMIT %d for %dms",
		tableName, rowLimit, durationMs)
	r.active.Store(true)

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		for time.Now().Before(deadline) {
			rows, err := db.QueryContext(context.Background(),
				fmt.Sprintf("SELECT * FROM %s LIMIT %d", tableName, rowLimit))
			if err != nil {
				log.Printf("[chaos-sdk] full_table_scan: query failed: %v", err)
				break
			}
			// drain results to force full scan
			for rows.Next() {
			}
			rows.Close()
			time.Sleep(200 * time.Millisecond)
		}
		r.active.Store(false)
		log.Println("[chaos-sdk] Full table scan fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 13. Thundering herd — fire N concurrent identical queries simultaneously
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyThunderingHerd(rule chaos.FaultRuleConfig) {
	db := r.getDB()
	if db == nil {
		log.Println("[chaos-sdk] thundering_herd: no DB registered — call injector.RegisterDB(db) at app startup")
		return
	}
	tableName := chaos.GetConfigString(rule, "table_name", "products")
	concurrency := chaos.Clamp(chaos.GetConfigInt(rule, "concurrency", 50), 2, 500)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting thundering herd: %d concurrent queries on %s for %dms",
		concurrency, tableName, durationMs)
	r.active.Store(true)

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		for time.Now().Before(deadline) {
			var wg sync.WaitGroup
			for i := 0; i < concurrency; i++ {
				wg.Add(1)
				go func() {
					defer wg.Done()
					rows, err := db.QueryContext(context.Background(),
						fmt.Sprintf("SELECT * FROM %s LIMIT 100", tableName))
					if err == nil {
						for rows.Next() {
						}
						rows.Close()
					}
				}()
			}
			wg.Wait()
			time.Sleep(1 * time.Second)
		}
		r.active.Store(false)
		log.Println("[chaos-sdk] Thundering herd fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 14. Unbounded query — SELECT * without meaningful WHERE clause
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyUnboundedQuery(rule chaos.FaultRuleConfig) {
	db := r.getDB()
	if db == nil {
		log.Println("[chaos-sdk] unbounded_query: no DB registered — call injector.RegisterDB(db) at app startup")
		return
	}
	tableName := chaos.GetConfigString(rule, "table_name", "orders")
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting unbounded query on %s for %dms", tableName, durationMs)
	r.active.Store(true)

	go func() {
		deadline := time.Now().Add(time.Duration(durationMs) * time.Millisecond)
		for time.Now().Before(deadline) {
			// No WHERE, no LIMIT — full table read
			rows, err := db.QueryContext(context.Background(),
				fmt.Sprintf("SELECT * FROM %s", tableName))
			if err != nil {
				log.Printf("[chaos-sdk] unbounded_query: failed: %v", err)
				break
			}
			for rows.Next() {
			}
			rows.Close()
			time.Sleep(100 * time.Millisecond)
		}
		r.active.Store(false)
		log.Println("[chaos-sdk] Unbounded query fault completed")
	}()
}

// ---------------------------------------------------------------------------
// 15. Connection leak — open DB connections without closing them
// ---------------------------------------------------------------------------

func (r *ResourceFaultInjector) applyConnectionLeak(rule chaos.FaultRuleConfig) {
	db := r.getDB()
	if db == nil {
		log.Println("[chaos-sdk] connection_leak: no DB registered — call injector.RegisterDB(db) at app startup")
		return
	}
	leakCount := chaos.Clamp(chaos.GetConfigInt(rule, "leak_count", 50), 1, 500)
	durationMs := chaos.Clamp(chaos.GetConfigInt(rule, "duration_ms", 30000), 1000, 300000)

	log.Printf("[chaos-sdk] Injecting connection leak: %d connections for %dms", leakCount, durationMs)
	r.active.Store(true)

	go func() {
		// Get connections from the app's pool without releasing them
		r.dbMu.Lock()
		leaked := make([]*sql.Conn, 0, leakCount)
		for i := 0; i < leakCount; i++ {
			conn, err := db.Conn(context.Background())
			if err != nil {
				log.Printf("[chaos-sdk] connection_leak: conn %d failed: %v", i, err)
				break
			}
			leaked = append(leaked, conn)
		}
		r.dbMu.Unlock()

		log.Printf("[chaos-sdk] connection_leak: %d connections leaked from app pool", len(leaked))
		time.Sleep(time.Duration(durationMs) * time.Millisecond)

		// Release all leaked connections
		for _, c := range leaked {
			c.Close() //nolint:errcheck
		}
		r.active.Store(false)
		log.Printf("[chaos-sdk] Connection leak fault completed, %d connections returned", len(leaked))
	}()
}
