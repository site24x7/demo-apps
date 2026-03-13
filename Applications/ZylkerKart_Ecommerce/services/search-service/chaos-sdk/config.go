// Site24x7 Labs Chaos SDK for Go — Config File Watcher & Heartbeat Writer
//
// ConfigFileWatcher: polls the fault config JSON file every 2 s, re-parses
// on mtime change, and notifies the engine via a callback.
//
// HeartbeatWriter: writes {app_name}.heartbeat.json every 30 s so the agent
// can discover that this SDK is installed and running.

package chaos

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const (
	// DefaultPollInterval is how often to check for config file changes.
	DefaultPollInterval = 2 * time.Second

	// HeartbeatInterval is how often to write the heartbeat file.
	HeartbeatInterval = 30 * time.Second
)

// ---------------------------------------------------------------------------
// ConfigFileWatcher
// ---------------------------------------------------------------------------

// ConfigUpdateCallback is invoked when the config file changes.
type ConfigUpdateCallback func(config AppFaultConfig)

// ConfigFileWatcher polls a JSON config file on disk and notifies a callback
// when it detects changes (via mtime comparison).
type ConfigFileWatcher struct {
	configPath string
	interval   time.Duration
	listener   ConfigUpdateCallback
	lastMtime  time.Time
	cancel     context.CancelFunc
	done       chan struct{}
}

// NewConfigFileWatcher creates a watcher for the given config file.
func NewConfigFileWatcher(configDir, appName string, interval time.Duration, listener ConfigUpdateCallback) *ConfigFileWatcher {
	return &ConfigFileWatcher{
		configPath: filepath.Join(configDir, appName+".json"),
		interval:   interval,
		listener:   listener,
		done:       make(chan struct{}),
	}
}

// Start begins polling in a background goroutine. Safe to call only once.
func (w *ConfigFileWatcher) Start(ctx context.Context) {
	ctx, w.cancel = context.WithCancel(ctx)

	// Check immediately, then periodically
	w.checkForChanges()

	go func() {
		defer close(w.done)
		ticker := time.NewTicker(w.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				w.checkForChanges()
			}
		}
	}()

	logDebug("ConfigFileWatcher started, watching: %s", w.configPath)
}

// Stop cancels the watcher goroutine and blocks until it exits.
func (w *ConfigFileWatcher) Stop() {
	if w.cancel != nil {
		w.cancel()
		<-w.done
	}
	logDebug("ConfigFileWatcher stopped")
}

func (w *ConfigFileWatcher) checkForChanges() {
	// Check if file exists and has changed
	info, err := os.Stat(w.configPath)
	if err != nil {
		// File doesn't exist — either agent hasn't written it yet,
		// or agent deleted it (all rules removed). If we had rules
		// before, clear them by sending an empty config.
		if !w.lastMtime.IsZero() {
			w.lastMtime = time.Time{}
			logDebug("Config file removed, clearing all rules")
			func() {
				defer func() {
					if r := recover(); r != nil {
						logDebug("Config update listener panic: %v", r)
					}
				}()
				w.listener(AppFaultConfig{Rules: []FaultRuleConfig{}})
			}()
		}
		return
	}

	mtime := info.ModTime()
	if !mtime.After(w.lastMtime) {
		return
	}
	w.lastMtime = mtime

	// Read and parse the config file
	data, err := os.ReadFile(w.configPath)
	if err != nil {
		logDebug("Failed to read config file %s: %v", w.configPath, err)
		return
	}

	var config AppFaultConfig
	if err := json.Unmarshal(data, &config); err != nil {
		logDebug("Failed to parse config file %s: %v", w.configPath, err)
		return
	}

	// Validate minimal structure
	if config.Rules == nil {
		logDebug("Invalid config file structure in %s", w.configPath)
		return
	}

	logDebug("Config file changed, loaded %d rules", len(config.Rules))

	// Notify listener (wrapped in recover to prevent panics from crashing the watcher)
	func() {
		defer func() {
			if r := recover(); r != nil {
				logDebug("Config update listener panic: %v", r)
			}
		}()
		w.listener(config)
	}()
}

// ---------------------------------------------------------------------------
// HeartbeatWriter
// ---------------------------------------------------------------------------

// HeartbeatWriter periodically writes a heartbeat JSON file so the agent
// can detect that this SDK is installed and running.
type HeartbeatWriter struct {
	heartbeatPath    string
	tmpPath          string
	appName          string
	framework        string
	frameworkVersion string
	cancel           context.CancelFunc
	done             chan struct{}
}

// NewHeartbeatWriter creates a heartbeat writer.
func NewHeartbeatWriter(configDir, appName, framework, frameworkVersion string) *HeartbeatWriter {
	return &HeartbeatWriter{
		heartbeatPath:    filepath.Join(configDir, appName+".heartbeat.json"),
		tmpPath:          filepath.Join(configDir, appName+".heartbeat.tmp"),
		appName:          appName,
		framework:        framework,
		frameworkVersion: frameworkVersion,
		done:             make(chan struct{}),
	}
}

// Start begins writing heartbeats in a background goroutine. Safe to call only once.
func (h *HeartbeatWriter) Start(ctx context.Context) {
	ctx, h.cancel = context.WithCancel(ctx)

	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(h.heartbeatPath), 0o755); err != nil {
		logDebug("Failed to create heartbeat directory: %v", err)
	}

	// Write immediately, then periodically
	h.writeHeartbeat()

	go func() {
		defer close(h.done)
		ticker := time.NewTicker(HeartbeatInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				h.writeHeartbeat()
			}
		}
	}()

	logDebug("HeartbeatWriter started, path: %s", h.heartbeatPath)
}

// Stop cancels the heartbeat goroutine, blocks until it exits, and removes the heartbeat file.
func (h *HeartbeatWriter) Stop() {
	if h.cancel != nil {
		h.cancel()
		<-h.done
	}

	// Clean up heartbeat file on shutdown
	_ = os.Remove(h.heartbeatPath)

	logDebug("HeartbeatWriter stopped")
}

func (h *HeartbeatWriter) writeHeartbeat() {
	hostname, _ := os.Hostname()

	data := map[string]interface{}{
		"app_name":          h.appName,
		"sdk_version":       SDKVersion,
		"sdk_language":      SDKLanguage,
		"framework":         h.framework,
		"framework_version": h.frameworkVersion,
		"pid":               os.Getpid(),
		"hostname":          hostname,
		"timestamp":         time.Now().UTC().Format(time.RFC3339),
	}

	content, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		logDebug("Failed to marshal heartbeat: %v", err)
		return
	}

	// Atomic write: write to tmp file, then rename
	if err := os.WriteFile(h.tmpPath, content, 0o644); err != nil {
		logDebug("Failed to write heartbeat tmp file: %v", err)
		return
	}
	if err := os.Rename(h.tmpPath, h.heartbeatPath); err != nil {
		logDebug("Failed to rename heartbeat file: %v", err)
	}
}

// HeartbeatPath returns the path to the heartbeat file (for testing).
func (h *HeartbeatWriter) HeartbeatPath() string {
	return h.heartbeatPath
}

// ConfigPath returns the config file path being watched (for testing).
func (w *ConfigFileWatcher) ConfigPath() string {
	return w.configPath
}

// FormatTimestamp returns an ISO-8601 UTC timestamp string without milliseconds.
func FormatTimestamp() string {
	return time.Now().UTC().Format(time.RFC3339)
}

// HeartbeatPayload represents the heartbeat JSON structure (exported for testing).
type HeartbeatPayload struct {
	AppName          string `json:"app_name"`
	SDKVersion       string `json:"sdk_version"`
	SDKLanguage      string `json:"sdk_language"`
	Framework        string `json:"framework"`
	FrameworkVersion string `json:"framework_version"`
	PID              int    `json:"pid"`
	Hostname         string `json:"hostname"`
	Timestamp        string `json:"timestamp"`
}

// buildHeartbeatPayload creates a HeartbeatPayload for the current state.
func (h *HeartbeatWriter) buildHeartbeatPayload() HeartbeatPayload {
	hn, _ := os.Hostname()
	return HeartbeatPayload{
		AppName:          h.appName,
		SDKVersion:       SDKVersion,
		SDKLanguage:      SDKLanguage,
		Framework:        h.framework,
		FrameworkVersion: h.frameworkVersion,
		PID:              os.Getpid(),
		Hostname:         hn,
		Timestamp:        fmt.Sprintf("%s", time.Now().UTC().Format(time.RFC3339)),
	}
}
