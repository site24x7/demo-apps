// Site24x7 Labs Chaos SDK for Go — Public API
//
// InitChaos is the single entry point. It creates the engine, starts
// the config file watcher and heartbeat writer, and returns the engine
// for use with HTTP middleware, RoundTripper wrappers, database drivers,
// and Redis hooks.
//
// Usage:
//
//	engine, err := chaos.InitChaos("order-service",
//	    chaos.WithFramework("net-http", "1.22"),
//	)
//	if err != nil { log.Fatal(err) }
//	defer engine.Shutdown()
//
//	mux := http.NewServeMux()
//	http.ListenAndServe(":8080", engine.HTTPMiddleware(mux))

package chaos

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"strings"
)

// ---------------------------------------------------------------------------
// Functional options
// ---------------------------------------------------------------------------

// Option configures InitChaos.
type Option func(*Options)

// WithConfigDir overrides the default config directory.
func WithConfigDir(dir string) Option {
	return func(o *Options) { o.ConfigDir = dir }
}

// WithFramework sets the framework name and version for the heartbeat.
func WithFramework(name, version string) Option {
	return func(o *Options) {
		o.Framework = name
		o.FrameworkVersion = version
	}
}

// WithEnabled sets whether fault injection is active.
func WithEnabled(enabled bool) Option {
	return func(o *Options) { o.Enabled = &enabled }
}

// WithUDS overrides the Unix Domain Socket settings used for instant config
// push + health reporting.
func WithUDS(enabled bool, path string) Option {
	return func(o *Options) {
		o.UDSEnabled = &enabled
		if path != "" {
			o.UDSPath = path
		}
	}
}

// ---------------------------------------------------------------------------
// InitChaos — the public entry point
// ---------------------------------------------------------------------------

// InitChaos initialises the Chaos SDK for a Go application.
//
// It creates a ChaosEngine, starts the config file watcher and heartbeat
// writer, and returns the engine. The caller should defer engine.Shutdown().
//
// The engine exposes:
//   - HTTPMiddleware(next http.Handler) http.Handler — net/http inbound faults
//   - NewTransport(base http.RoundTripper) http.RoundTripper — outbound HTTP faults
//   - WrapDriver / RedisHook — database/Redis faults
//
// Environment variable overrides (lower priority than options):
//
//	CHAOS_SDK_ENABLED    — "false" disables the SDK
//	CHAOS_SDK_APP_NAME   — application name
//	CHAOS_SDK_CONFIG_DIR — config directory path
func InitChaos(appName string, opts ...Option) (*ChaosInstance, error) {
	// Build options
	o := &Options{
		AppName:             appName,
		ConfigDir:           DefaultConfigDir,
		Framework:           "net-http",
		UDSPath:             DefaultUDSPath,
		UDSHealthIntervalMs: DefaultUDSHealthIntervalMs,
	}
	for _, fn := range opts {
		fn(o)
	}
	if o.UDSPath == "" {
		o.UDSPath = DefaultUDSPath
	}
	if o.UDSHealthIntervalMs <= 0 {
		o.UDSHealthIntervalMs = DefaultUDSHealthIntervalMs
	}

	// Environment variable overrides
	if envApp := os.Getenv("CHAOS_SDK_APP_NAME"); envApp != "" && o.AppName == "" {
		o.AppName = envApp
	}
	if envDir := os.Getenv("CHAOS_SDK_CONFIG_DIR"); envDir != "" {
		o.ConfigDir = envDir
	}
	if envEnabled := os.Getenv("CHAOS_SDK_ENABLED"); strings.EqualFold(envEnabled, "false") {
		f := false
		o.Enabled = &f
	}
	if envUDS := os.Getenv("CHAOS_SDK_UDS_ENABLED"); strings.EqualFold(envUDS, "false") {
		f := false
		o.UDSEnabled = &f
	}
	if envUDSPath := os.Getenv("CHAOS_SDK_UDS_PATH"); envUDSPath != "" {
		o.UDSPath = envUDSPath
	}

	// Validate
	if o.AppName == "" {
		return nil, fmt.Errorf("chaos: AppName is required (pass to InitChaos or set CHAOS_SDK_APP_NAME)")
	}

	// Create engine
	engine := NewEngine()
	if o.Enabled != nil {
		engine.SetEnabled(*o.Enabled)
	}

	// Root context for all background goroutines
	ctx, cancel := context.WithCancel(context.Background())

	// Config file watcher
	watcher := NewConfigFileWatcher(o.ConfigDir, o.AppName, DefaultPollInterval, func(config AppFaultConfig) {
		engine.UpdateRules(config.Rules)
	})
	watcher.Start(ctx)

	// Heartbeat writer
	heartbeat := NewHeartbeatWriter(o.ConfigDir, o.AppName, o.Framework, o.FrameworkVersion)
	heartbeat.Start(ctx)

	inst := &ChaosInstance{
		Engine:    engine,
		Options:   *o,
		cancel:    cancel,
		watcher:   watcher,
		heartbeat: heartbeat,
	}

	// v2: connect to the agent over UDS for instant config push + health
	// reporting. The file watcher above remains active as a fallback. UDS is
	// on by default; never let UDS setup break the app.
	udsOn := o.UDSEnabled == nil || *o.UDSEnabled
	if udsOn {
		func() {
			defer func() {
				if r := recover(); r != nil {
					logDebug("Failed to start UDS client, falling back to file polling: %v", r)
				}
			}()
			hostname := DefaultHostname()
			pid := os.Getpid()
			instanceID := fmt.Sprintf("%s@%s:%d", o.AppName, hostname, pid)
			uds := NewUDSClient(
				o.UDSPath,
				instanceID,
				o.AppName,
				SDKLanguage,
				SDKVersion,
				hostname,
				pid,
				detectDBDrivers(),
				o.UDSHealthIntervalMs,
				DefaultUDSReconnectBackoffMs,
				func(rules []FaultRuleConfig) { engine.UpdateRules(rules) },
				engine.ClearRules,
				func() map[string]interface{} { return healthSnapshot(engine) },
			)
			uds.Start(ctx)
			inst.uds = uds
		}()
	}

	logDebug("Chaos SDK initialized for %s app %q", o.Framework, o.AppName)
	return inst, nil
}

// detectDBDrivers reports which DB driver families this process likely uses,
// based on registered database/sql drivers. Detection never opens a connection.
func detectDBDrivers() []string {
	seen := map[string]bool{}
	var out []string
	add := func(family string) {
		if !seen[family] {
			seen[family] = true
			out = append(out, family)
		}
	}
	for _, name := range sql.Drivers() {
		n := strings.ToLower(name)
		switch {
		case strings.Contains(n, "postgres") || strings.Contains(n, "pgx") || n == "pq":
			add("postgresql")
		case strings.Contains(n, "mysql") || strings.Contains(n, "mariadb"):
			add("mysql")
		case strings.Contains(n, "redis"):
			add("redis")
		}
	}
	return out
}

// healthSnapshot returns a lightweight health snapshot for UDS reporting.
func healthSnapshot(engine *Engine) map[string]interface{} {
	return map[string]interface{}{
		"active_rules": len(engine.GetRules()),
		"enabled":      engine.Enabled(),
		"pid":          os.Getpid(),
	}
}

// ---------------------------------------------------------------------------
// ChaosInstance — holds the engine + background services
// ---------------------------------------------------------------------------

// ChaosInstance holds the engine and all background services. Use Engine
// to access fault matching. Call Shutdown when the application exits.
type ChaosInstance struct {
	// Engine is the central fault rule engine. Pass it to middleware,
	// transports, database wrappers, and Redis hooks.
	Engine *Engine

	// Options is a copy of the resolved configuration.
	Options Options

	cancel    context.CancelFunc
	watcher   *ConfigFileWatcher
	heartbeat *HeartbeatWriter
	uds       *UDSClient
}

// Shutdown stops the config watcher, heartbeat writer, and releases resources.
// It is safe to call multiple times.
func (ci *ChaosInstance) Shutdown() {
	if ci.cancel != nil {
		ci.cancel()
		ci.cancel = nil
	}
	if ci.uds != nil {
		ci.uds.Stop()
		ci.uds = nil
	}
	if ci.watcher != nil {
		ci.watcher.Stop()
		ci.watcher = nil
	}
	if ci.heartbeat != nil {
		ci.heartbeat.Stop()
		ci.heartbeat = nil
	}
	logDebug("Chaos SDK shut down")
}
