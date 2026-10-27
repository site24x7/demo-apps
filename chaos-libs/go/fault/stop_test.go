package fault

import (
	"database/sql"
	"database/sql/driver"
	"errors"
	"sync"
	"testing"
	"time"

	chaos "github.com/site24x7/observe-labs/sdks/go"
)

func waitIdle(t *testing.T, r *ResourceFaultInjector, within time.Duration) {
	t.Helper()
	deadline := time.Now().Add(within)
	for r.active.Load() {
		if time.Now().After(deadline) {
			t.Fatalf("fault still active %v after its rule was removed", within)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

func startFault(t *testing.T, ft chaos.FaultType, cfg map[string]interface{}) (*chaos.Engine, *ResourceFaultInjector) {
	t.Helper()
	e := chaos.NewEngine()
	r := NewResourceFaultInjector(e)
	r.Install()
	e.UpdateRules([]chaos.FaultRuleConfig{{ID: "r1", FaultType: ft, Enabled: true, Probability: 1, Config: cfg}})
	if !r.active.Load() {
		t.Fatalf("%s did not start", ft)
	}
	return e, r
}

// Removing the rule (experiment revert) ends a running fault early.
func TestRuleRemovalStopsResourceFault(t *testing.T) {
	for _, ft := range []chaos.FaultType{chaos.FaultCPUBurn, chaos.FaultThreadDeadlock, chaos.FaultGCPressure, chaos.FaultMemoryPressure} {
		e, r := startFault(t, ft, map[string]interface{}{"duration_ms": 60000, "thread_count": 1, "allocation_mb": 1})
		e.UpdateRules(nil)
		waitIdle(t, r, 3*time.Second)
	}
}

// The kill switch clears rules; it must stop the fault too.
func TestKillSwitchStopsResourceFault(t *testing.T) {
	e, r := startFault(t, chaos.FaultCPUBurn, map[string]interface{}{"duration_ms": 60000, "thread_count": 1})
	e.ClearRules()
	waitIdle(t, r, 3*time.Second)
}

// Disabling the SDK stops a running fault on the next config change.
func TestDisableStopsResourceFault(t *testing.T) {
	e, r := startFault(t, chaos.FaultThreadDeadlock, map[string]interface{}{"duration_ms": 60000})
	e.SetEnabled(false)
	e.UpdateRules(e.GetRules())
	waitIdle(t, r, 3*time.Second)
}

// An unrelated config change leaves the running fault alone.
func TestUnrelatedRuleChangeKeepsFault(t *testing.T) {
	e, r := startFault(t, chaos.FaultThreadDeadlock, map[string]interface{}{"duration_ms": 60000})
	rules := append(e.GetRules(), chaos.FaultRuleConfig{ID: "other", FaultType: chaos.FaultHTTPLatency, Enabled: true, Probability: 1})
	e.UpdateRules(rules)
	time.Sleep(200 * time.Millisecond)
	if !r.active.Load() {
		t.Fatal("fault stopped although its rule is still present")
	}
	e.UpdateRules(nil)
	waitIdle(t, r, 3*time.Second)
}

// A delayed process_exit is cancelled if its rule goes away first.
func TestProcessExitCancelledBeforeFiring(t *testing.T) {
	e, r := startFault(t, chaos.FaultProcessExit, map[string]interface{}{"delay_seconds": 30})
	e.UpdateRules(nil)
	waitIdle(t, r, 3*time.Second)
}

// --- connection_leak against a pool smaller than leak_count -----------------

type fakeDriver struct{}
type fakeConn struct{}

func (fakeDriver) Open(string) (driver.Conn, error)  { return fakeConn{}, nil }
func (fakeConn) Prepare(string) (driver.Stmt, error) { return nil, errors.New("unsupported") }
func (fakeConn) Close() error                        { return nil }
func (fakeConn) Begin() (driver.Tx, error)           { return nil, errors.New("unsupported") }

var registerOnce sync.Once

// With leak_count larger than the app's pool, the fault must not hang on a
// checkout forever: it holds what it got, and returns every connection when
// stopped, leaving the pool usable.
func TestConnectionLeakReleasesSmallPool(t *testing.T) {
	registerOnce.Do(func() { sql.Register("chaosfake", fakeDriver{}) })
	db, err := sql.Open("chaosfake", "")
	if err != nil {
		t.Fatal(err)
	}
	db.SetMaxOpenConns(5)

	e := chaos.NewEngine()
	r := NewResourceFaultInjector(e)
	r.RegisterDB(db)
	r.Install()
	e.UpdateRules([]chaos.FaultRuleConfig{{ID: "leak", FaultType: chaos.FaultConnectionLeak, Enabled: true, Probability: 1,
		Config: map[string]interface{}{"leak_count": 50, "duration_ms": 60000}}})

	deadline := time.Now().Add(10 * time.Second)
	for db.Stats().InUse < 5 {
		if time.Now().After(deadline) {
			t.Fatalf("pool not exhausted: %+v", db.Stats())
		}
		time.Sleep(50 * time.Millisecond)
	}
	e.UpdateRules(nil)
	waitIdle(t, r, 8*time.Second)
	if inUse := db.Stats().InUse; inUse != 0 {
		t.Fatalf("%d connections still held after the fault stopped", inUse)
	}
}
