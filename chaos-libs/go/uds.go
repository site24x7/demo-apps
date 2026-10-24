// Site24x7 Labs Chaos SDK for Go — Unix Domain Socket Client
//
// Connects to the agent's Unix Domain Socket for instant fault-config push and
// health reporting, replacing file polling when the socket is available. Runs
// as a background goroutine: on connect it registers the instance, then reads
// newline-delimited JSON messages from the agent (config pushes, kill
// commands), and periodically sends health snapshots. If the socket is
// unavailable or drops, it backs off and retries; the file-based
// ConfigFileWatcher continues to work as a fallback meanwhile.
//
// The client must never panic the host application: the read/serve loop
// recovers from any panic and the connection is retried.

package chaos

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"sync"
	"time"
)

// HealthSnapshotFunc supplies the latest health snapshot to report over UDS.
type HealthSnapshotFunc func() map[string]interface{}

// udsConfigMessage is the on-the-wire shape of a "config" push. It mirrors the
// AppFaultConfig the file watcher produces, plus a config_version field.
type udsConfigMessage struct {
	Type          string            `json:"type"`
	ConfigVersion int               `json:"config_version"`
	Rules         []FaultRuleConfig `json:"rules"`
}

// udsRegisterMessage is the exact registration payload sent on connect.
type udsRegisterMessage struct {
	Type       string   `json:"type"`
	InstanceID string   `json:"instance_id"`
	AppName    string   `json:"app_name"`
	Language   string   `json:"language"`
	Version    string   `json:"version"`
	Hostname   string   `json:"hostname"`
	PID        int      `json:"pid"`
	DBDrivers  []string `json:"db_drivers"`
}

// udsHealthMessage is the health report payload.
type udsHealthMessage struct {
	Type       string                 `json:"type"`
	InstanceID string                 `json:"instance_id"`
	Health     map[string]interface{} `json:"health"`
}

// UDSClient connects to the agent's Unix Domain Socket.
type UDSClient struct {
	socketPath         string
	instanceID         string
	appName            string
	language           string
	version            string
	hostname           string
	pid                int
	dbDrivers          []string
	healthIntervalMs   int
	reconnectBackoffMs int

	onConfig func([]FaultRuleConfig)
	onKill   func()
	health   HealthSnapshotFunc

	writeMu sync.Mutex
	cancel  context.CancelFunc
	done    chan struct{}
}

// NewUDSClient creates a UDS client. The onConfig callback receives pushed
// rules, onKill clears all rules, and health supplies the periodic snapshot.
func NewUDSClient(
	socketPath, instanceID, appName, language, version, hostname string,
	pid int,
	dbDrivers []string,
	healthIntervalMs, reconnectBackoffMs int,
	onConfig func([]FaultRuleConfig),
	onKill func(),
	health HealthSnapshotFunc,
) *UDSClient {
	return &UDSClient{
		socketPath:         socketPath,
		instanceID:         instanceID,
		appName:            appName,
		language:           language,
		version:            version,
		hostname:           hostname,
		pid:                pid,
		dbDrivers:          dbDrivers,
		healthIntervalMs:   healthIntervalMs,
		reconnectBackoffMs: reconnectBackoffMs,
		onConfig:           onConfig,
		onKill:             onKill,
		health:             health,
		done:               make(chan struct{}),
	}
}

// Start launches the connect/serve/reconnect loop in a background goroutine.
// It never panics the host application.
func (c *UDSClient) Start(ctx context.Context) {
	ctx, c.cancel = context.WithCancel(ctx)
	go func() {
		defer close(c.done)
		defer func() {
			if r := recover(); r != nil {
				logDebug("UDS client goroutine recovered from panic: %v", r)
			}
		}()
		for {
			select {
			case <-ctx.Done():
				return
			default:
			}

			func() {
				defer func() {
					if r := recover(); r != nil {
						logDebug("UDS connection panic recovered: %v", r)
					}
				}()
				c.connectAndServe(ctx)
			}()

			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(c.reconnectBackoffMs) * time.Millisecond):
			}
		}
	}()
	logDebug("UDS client started, socket: %s", c.socketPath)
}

// Stop cancels the client goroutine and blocks until it exits.
func (c *UDSClient) Stop() {
	if c.cancel != nil {
		c.cancel()
		<-c.done
	}
	logDebug("UDS client stopped")
}

func (c *UDSClient) connectAndServe(ctx context.Context) {
	conn, err := net.Dial("unix", c.socketPath)
	if err != nil {
		logDebug("UDS connect failed (%s): %v", c.socketPath, err)
		return
	}
	defer conn.Close()

	// Register this instance.
	if err := c.write(conn, udsRegisterMessage{
		Type:       "register",
		InstanceID: c.instanceID,
		AppName:    c.appName,
		Language:   c.language,
		Version:    c.version,
		Hostname:   c.hostname,
		PID:        c.pid,
		DBDrivers:  c.dbDriversOrEmpty(),
	}); err != nil {
		logDebug("UDS register failed: %v", err)
		return
	}
	logDebug("Connected to agent over UDS at %s (app=%s)", c.socketPath, c.appName)

	// Health reporter for the lifetime of this connection.
	connCtx, connCancel := context.WithCancel(ctx)
	defer connCancel()
	go c.healthLoop(connCtx, conn)

	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
		}
		c.handleMessage(scanner.Bytes())
	}
}

func (c *UDSClient) handleMessage(line []byte) {
	if len(line) == 0 {
		return
	}
	var head struct {
		Type string `json:"type"`
	}
	if err := json.Unmarshal(line, &head); err != nil {
		logDebug("Failed to parse UDS message: %v", err)
		return
	}
	switch head.Type {
	case "config":
		var msg udsConfigMessage
		if err := json.Unmarshal(line, &msg); err != nil {
			logDebug("Failed to parse UDS config: %v", err)
			return
		}
		logDebug("UDS config push: version=%d, %d rules", msg.ConfigVersion, len(msg.Rules))
		if c.onConfig != nil {
			c.onConfig(msg.Rules)
		}
	case "kill":
		logDebug("UDS kill switch received — clearing all rules")
		if c.onKill != nil {
			c.onKill()
		}
	case "registered":
		logDebug("Agent acknowledged registration")
	default:
		logDebug("Unknown UDS message type: %s", head.Type)
	}
}

func (c *UDSClient) healthLoop(ctx context.Context, conn net.Conn) {
	defer func() {
		if r := recover(); r != nil {
			logDebug("UDS health loop recovered from panic: %v", r)
		}
	}()
	ticker := time.NewTicker(time.Duration(c.healthIntervalMs) * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			var snapshot map[string]interface{}
			if c.health != nil {
				snapshot = c.health()
			}
			if snapshot == nil {
				snapshot = map[string]interface{}{}
			}
			if err := c.write(conn, udsHealthMessage{
				Type:       "health",
				InstanceID: c.instanceID,
				Health:     snapshot,
			}); err != nil {
				logDebug("UDS health report failed: %v", err)
				return // connection likely dropped; outer loop reconnects
			}
		}
	}
}

func (c *UDSClient) write(conn net.Conn, msg interface{}) error {
	data, err := json.Marshal(msg)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	_, err = conn.Write(data)
	return err
}

func (c *UDSClient) dbDriversOrEmpty() []string {
	if c.dbDrivers == nil {
		return []string{}
	}
	return c.dbDrivers
}

// ---------------------------------------------------------------------------
// Helpers for building UDS client identity from the host process.
// ---------------------------------------------------------------------------

// DefaultHostname returns this host's name, falling back to $HOSTNAME or "unknown".
func DefaultHostname() string {
	if hn, err := os.Hostname(); err == nil && hn != "" {
		return hn
	}
	if env := os.Getenv("HOSTNAME"); env != "" {
		return env
	}
	return "unknown"
}
