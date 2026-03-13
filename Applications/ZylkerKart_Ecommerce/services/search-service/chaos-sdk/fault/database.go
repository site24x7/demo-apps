// Site24x7 Labs Chaos SDK for Go — Database Fault Injector
//
// Wraps database/sql/driver.Driver to intercept database operations
// and inject 3 fault types:
//   1. jdbc_exception          — Return a database error before the query.
//   2. jdbc_latency            — Delay before the query executes.
//   3. jdbc_connection_pool_drain — Acquire and hold connections.
//
// Usage:
//
//	chaos.WrapDriver("postgres", &pq.Driver{}, engine)
//	db, _ := sql.Open("chaos-postgres", dsn)

package fault

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"log"
	"sync"
	"time"

	chaos "github.com/pazhanir/site24x7-labs/sdks/go"
)

const dbFaultPrefix = "jdbc_"

// WrapDriver registers a new database/sql driver named "chaos-{name}" that
// wraps the given base driver with chaos fault injection.
func WrapDriver(name string, base driver.Driver, engine *chaos.Engine) {
	wrapped := &chaosDriver{
		base:   base,
		engine: engine,
	}
	sql.Register("chaos-"+name, wrapped)
	log.Printf("[chaos-sdk] Registered chaos driver: chaos-%s", name)
}

// ---------------------------------------------------------------------------
// Chaos driver
// ---------------------------------------------------------------------------

type chaosDriver struct {
	base   driver.Driver
	engine *chaos.Engine
}

func (d *chaosDriver) Open(dsn string) (driver.Conn, error) {
	// Check for connection pool drain
	if d.evaluateConnectionPoolDrain() {
		// Block — simulate pool drain by delaying the connection acquisition
		return nil, &chaos.DatabaseError{
			Message:  "Connection pool exhausted (chaos fault)",
			SQLState: "08001",
		}
	}

	conn, err := d.base.Open(dsn)
	if err != nil {
		return nil, err
	}
	return &chaosConn{base: conn, engine: d.engine}, nil
}

func (d *chaosDriver) evaluateConnectionPoolDrain() bool {
	rules := d.engine.FindMatchingRules(dbFaultPrefix)
	for _, rule := range rules {
		if rule.FaultType == chaos.FaultJDBCConnectionPoolDrain && d.engine.ShouldFire(rule) {
			holdDurationMs := chaos.Clamp(chaos.GetConfigInt(rule, "hold_duration_ms", 5000), 1000, 60000)
			log.Printf("[chaos-sdk] Injecting JDBC connection pool drain: hold for %dms", holdDurationMs)
			time.Sleep(time.Duration(holdDurationMs) * time.Millisecond)
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// Chaos connection
// ---------------------------------------------------------------------------

type chaosConn struct {
	base   driver.Conn
	engine *chaos.Engine
}

func (c *chaosConn) Prepare(query string) (driver.Stmt, error) {
	if err := c.evaluateFaults(); err != nil {
		return nil, err
	}
	return c.base.Prepare(query)
}

func (c *chaosConn) Close() error {
	return c.base.Close()
}

func (c *chaosConn) Begin() (driver.Tx, error) {
	if err := c.evaluateFaults(); err != nil {
		return nil, err
	}
	return c.base.Begin() //nolint:staticcheck
}

// Implement driver.QueryerContext if the base connection supports it.
func (c *chaosConn) QueryContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Rows, error) {
	if err := c.evaluateFaults(); err != nil {
		return nil, err
	}
	if qc, ok := c.base.(driver.QueryerContext); ok {
		return qc.QueryContext(ctx, query, args)
	}
	return nil, driver.ErrSkip
}

// Implement driver.ExecerContext if the base connection supports it.
func (c *chaosConn) ExecContext(ctx context.Context, query string, args []driver.NamedValue) (driver.Result, error) {
	if err := c.evaluateFaults(); err != nil {
		return nil, err
	}
	if ec, ok := c.base.(driver.ExecerContext); ok {
		return ec.ExecContext(ctx, query, args)
	}
	return nil, driver.ErrSkip
}

// evaluateFaults checks jdbc_exception and jdbc_latency fault rules.
func (c *chaosConn) evaluateFaults() error {
	if !c.engine.Enabled() {
		return nil
	}

	rules := c.engine.FindMatchingRules(dbFaultPrefix)
	for _, rule := range rules {
		if !c.engine.ShouldFire(rule) {
			continue
		}

		switch rule.FaultType {
		case chaos.FaultJDBCException:
			javaClass := chaos.GetConfigString(rule, "exception_class", "java.sql.SQLException")
			message := chaos.GetConfigString(rule, "message", "Injected database fault")
			sqlState := chaos.GetConfigString(rule, "sql_state", "HY000")
			log.Printf("[chaos-sdk] Injecting JDBC exception: %s - %s (state: %s)", javaClass, message, sqlState)
			return &chaos.DatabaseError{
				Message:  message,
				SQLState: sqlState,
			}

		case chaos.FaultJDBCLatency:
			delayMs := chaos.GetConfigInt(rule, "delay_ms", 3000)
			log.Printf("[chaos-sdk] Injecting JDBC latency: %dms", delayMs)
			time.Sleep(time.Duration(delayMs) * time.Millisecond)
			return nil // Continue with the real query after delay
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// ConnectionPoolDrainInjector — config-change listener for pool drain
// ---------------------------------------------------------------------------

// ConnectionPoolDrainInjector holds connections to simulate pool exhaustion.
// It listens for config changes and acquires/releases connections.
type ConnectionPoolDrainInjector struct {
	engine *chaos.Engine
	db     *sql.DB
	mu     sync.Mutex
	held   []*sql.Conn
	cancel context.CancelFunc
}

// NewConnectionPoolDrainInjector creates a pool drain injector for the given DB.
func NewConnectionPoolDrainInjector(engine *chaos.Engine, db *sql.DB) *ConnectionPoolDrainInjector {
	return &ConnectionPoolDrainInjector{
		engine: engine,
		db:     db,
	}
}

// Install registers the injector as a config update listener.
func (d *ConnectionPoolDrainInjector) Install() {
	d.engine.AddConfigUpdateListener(func() {
		d.evaluateAndApply()
	})
}

func (d *ConnectionPoolDrainInjector) evaluateAndApply() {
	rules := d.engine.FindMatchingRules(dbFaultPrefix)
	for _, rule := range rules {
		if rule.FaultType != chaos.FaultJDBCConnectionPoolDrain {
			continue
		}
		if !d.engine.ShouldFire(rule) {
			continue
		}

		holdCount := chaos.Clamp(chaos.GetConfigInt(rule, "hold_count", 5), 1, 50)
		holdDurationMs := chaos.Clamp(chaos.GetConfigInt(rule, "hold_duration_ms", 10000), 1000, 60000)

		log.Printf("[chaos-sdk] Injecting connection pool drain: %d connections for %dms", holdCount, holdDurationMs)
		d.drainPool(holdCount, holdDurationMs)
		return
	}

	// No active drain rule — release held connections
	d.releaseAll()
}

func (d *ConnectionPoolDrainInjector) drainPool(count, durationMs int) {
	d.mu.Lock()
	defer d.mu.Unlock()

	// Release previous held connections
	d.releaseHeldLocked()

	ctx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel

	for i := 0; i < count; i++ {
		conn, err := d.db.Conn(ctx)
		if err != nil {
			log.Printf("[chaos-sdk] Failed to acquire connection %d/%d: %v", i+1, count, err)
			break
		}
		d.held = append(d.held, conn)
	}

	// Release after duration
	go func() {
		select {
		case <-ctx.Done():
		case <-time.After(time.Duration(durationMs) * time.Millisecond):
		}
		d.releaseAll()
	}()
}

func (d *ConnectionPoolDrainInjector) releaseAll() {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.releaseHeldLocked()
}

func (d *ConnectionPoolDrainInjector) releaseHeldLocked() {
	if d.cancel != nil {
		d.cancel()
		d.cancel = nil
	}
	for _, conn := range d.held {
		_ = conn.Close()
	}
	d.held = nil
}
