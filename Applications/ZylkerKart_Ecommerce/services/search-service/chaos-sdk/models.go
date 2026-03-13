// Package chaos provides the Site24x7 Labs Chaos SDK for Go.
//
// It defines fault types, configuration file schema, exception class mappings,
// and helper functions shared by the engine and fault injectors.
package chaos

import (
	"errors"
	"fmt"
	"math"
)

// ---------------------------------------------------------------------------
// Fault types (all 20)
// ---------------------------------------------------------------------------

// FaultType represents a chaos fault type string.
type FaultType = string

const (
	// Inbound HTTP (5)
	FaultHTTPException       FaultType = "http_exception"
	FaultHTTPLatency         FaultType = "http_latency"
	FaultHTTPErrorResponse   FaultType = "http_error_response"
	FaultHTTPConnectionReset FaultType = "http_connection_reset"
	FaultHTTPSlowBody        FaultType = "http_slow_body"

	// Outbound HTTP client (4)
	FaultHTTPClientLatency         FaultType = "http_client_latency"
	FaultHTTPClientException       FaultType = "http_client_exception"
	FaultHTTPClientErrorResponse   FaultType = "http_client_error_response"
	FaultHTTPClientPartialResponse FaultType = "http_client_partial_response"

	// Database / JDBC (3)
	FaultJDBCException           FaultType = "jdbc_exception"
	FaultJDBCLatency             FaultType = "jdbc_latency"
	FaultJDBCConnectionPoolDrain FaultType = "jdbc_connection_pool_drain"

	// Redis (2)
	FaultRedisException FaultType = "redis_exception"
	FaultRedisLatency   FaultType = "redis_latency"

	// Resource exhaustion (6)
	FaultThreadPoolExhaustion FaultType = "thread_pool_exhaustion"
	FaultMemoryPressure       FaultType = "memory_pressure"
	FaultCPUBurn              FaultType = "cpu_burn"
	FaultGCPressure           FaultType = "gc_pressure"
	FaultThreadDeadlock       FaultType = "thread_deadlock"
	FaultDiskFill             FaultType = "disk_fill"
)

// ResourceFaultTypes is the set of fault types triggered on config change, not per-request.
var ResourceFaultTypes = map[FaultType]bool{
	FaultThreadPoolExhaustion: true,
	FaultMemoryPressure:       true,
	FaultCPUBurn:              true,
	FaultGCPressure:           true,
	FaultThreadDeadlock:       true,
	FaultDiskFill:             true,
}

// ---------------------------------------------------------------------------
// Config file schema (written by agent, read by SDK)
// ---------------------------------------------------------------------------

// FaultRuleConfig represents a single fault rule from the config file.
type FaultRuleConfig struct {
	ID          string                 `json:"id"`
	FaultType   FaultType              `json:"fault_type"`
	Enabled     bool                   `json:"enabled"`
	Probability float64                `json:"probability"`
	Config      map[string]interface{} `json:"config"`
	URLPattern  string                 `json:"url_pattern"`
}

// AppFaultConfig is the top-level config file written by the agent.
type AppFaultConfig struct {
	Version       int               `json:"version"`
	AppName       string            `json:"app_name"`
	EnvironmentID string            `json:"environment_id"`
	UpdatedAt     string            `json:"updated_at"`
	Rules         []FaultRuleConfig `json:"rules"`
}

// ---------------------------------------------------------------------------
// SDK options
// ---------------------------------------------------------------------------

// Options configures the chaos SDK.
type Options struct {
	// AppName identifies this application (matches the service name in Site24x7 Labs).
	AppName string

	// ConfigDir is the directory where the agent writes fault config files.
	// Default: /var/site24x7-labs/faults
	ConfigDir string

	// Framework is reported in the heartbeat (e.g., "net-http", "gin", "echo").
	Framework string

	// FrameworkVersion is reported in the heartbeat.
	FrameworkVersion string

	// Enabled controls whether fault injection is active. Default: true.
	Enabled *bool
}

// DefaultConfigDir is the default directory for fault config files.
const DefaultConfigDir = "/var/site24x7-labs/faults"

// SDKVersion is the version of this SDK.
const SDKVersion = "1.0.0"

// SDKLanguage identifies this SDK in heartbeat files.
const SDKLanguage = "go"

// ---------------------------------------------------------------------------
// Config helpers — extract typed values from rule.Config map
// ---------------------------------------------------------------------------

// GetConfigString extracts a string from the rule config, returning def if missing.
func GetConfigString(rule FaultRuleConfig, key, def string) string {
	v, ok := rule.Config[key]
	if !ok {
		return def
	}
	if s, ok := v.(string); ok {
		return s
	}
	return def
}

// GetConfigInt extracts an integer from the rule config, returning def if missing.
// Handles both float64 (from JSON) and int values.
func GetConfigInt(rule FaultRuleConfig, key string, def int) int {
	v, ok := rule.Config[key]
	if !ok {
		return def
	}
	switch n := v.(type) {
	case float64:
		return int(n)
	case int:
		return n
	case int64:
		return int(n)
	default:
		return def
	}
}

// GetConfigFloat extracts a float64 from the rule config, returning def if missing.
func GetConfigFloat(rule FaultRuleConfig, key string, def float64) float64 {
	v, ok := rule.Config[key]
	if !ok {
		return def
	}
	switch n := v.(type) {
	case float64:
		return n
	case int:
		return float64(n)
	default:
		return def
	}
}

// Clamp restricts v to the range [min, max].
func Clamp(v, min, max int) int {
	if v < min {
		return min
	}
	if v > max {
		return max
	}
	return v
}

// ClampFloat restricts v to the range [min, max].
func ClampFloat(v, min, max float64) float64 {
	return math.Max(min, math.Min(max, v))
}

// ---------------------------------------------------------------------------
// Exception class mapping: Java canonical → Go error
// ---------------------------------------------------------------------------

// exceptionMap maps canonical Java exception class names to Go error constructors.
// The config always stores Java class names for cross-SDK consistency.
var exceptionMap = map[string]func(message string) error{
	// Java standard
	"java.lang.RuntimeException":              func(m string) error { return errors.New(m) },
	"java.lang.NullPointerException":          func(m string) error { return fmt.Errorf("nil pointer: %s", m) },
	"java.lang.IllegalArgumentException":      func(m string) error { return fmt.Errorf("illegal argument: %s", m) },
	"java.lang.IllegalStateException":         func(m string) error { return fmt.Errorf("illegal state: %s", m) },
	"java.lang.UnsupportedOperationException": func(m string) error { return fmt.Errorf("unsupported operation: %s", m) },
	"java.io.IOException":                     func(m string) error { return fmt.Errorf("I/O error: %s", m) },
	"java.net.SocketException":                func(m string) error { return fmt.Errorf("socket error: %s", m) },
	"java.net.SocketTimeoutException":         func(m string) error { return fmt.Errorf("socket timeout: %s", m) },
	"java.net.ConnectException":               func(m string) error { return fmt.Errorf("connection refused: %s", m) },
	"java.net.UnknownHostException":           func(m string) error { return fmt.Errorf("unknown host: %s", m) },
	"java.util.concurrent.TimeoutException":   func(m string) error { return fmt.Errorf("timeout: %s", m) },

	// Spring / HTTP client
	"org.springframework.web.client.ResourceAccessException":  func(m string) error { return fmt.Errorf("resource access error: %s", m) },
	"org.springframework.web.client.HttpServerErrorException": func(m string) error { return fmt.Errorf("HTTP server error: %s", m) },
	"org.springframework.web.client.HttpClientErrorException": func(m string) error { return fmt.Errorf("HTTP client error: %s", m) },
	"ResourceAccessException":                                 func(m string) error { return fmt.Errorf("resource access error: %s", m) },

	// Database / JDBC
	"java.sql.SQLException":                       func(m string) error { return fmt.Errorf("SQL error: %s", m) },
	"java.sql.SQLTimeoutException":                func(m string) error { return fmt.Errorf("SQL timeout: %s", m) },
	"java.sql.SQLTransientConnectionException":    func(m string) error { return fmt.Errorf("SQL transient connection error: %s", m) },
	"java.sql.SQLNonTransientConnectionException": func(m string) error { return fmt.Errorf("SQL connection error: %s", m) },
	"org.postgresql.util.PSQLException":           func(m string) error { return fmt.Errorf("PostgreSQL error: %s", m) },

	// Redis
	"redis.clients.jedis.exceptions.JedisConnectionException":        func(m string) error { return fmt.Errorf("Redis connection error: %s", m) },
	"RedisConnectionFailureException":                                func(m string) error { return fmt.Errorf("Redis connection failure: %s", m) },
	"io.lettuce.core.RedisCommandTimeoutException":                   func(m string) error { return fmt.Errorf("Redis command timeout: %s", m) },
	"org.springframework.data.redis.RedisConnectionFailureException": func(m string) error { return fmt.Errorf("Redis connection failure: %s", m) },
}

// ResolveException maps a canonical Java class name to a Go error.
func ResolveException(javaClass, message string) error {
	if fn, ok := exceptionMap[javaClass]; ok {
		return fn(message)
	}
	return fmt.Errorf("[%s] %s", javaClass, message)
}

// ChaosError is a sentinel error type for chaos-injected faults.
type ChaosError struct {
	JavaClass string
	Message   string
}

func (e *ChaosError) Error() string {
	return fmt.Sprintf("[chaos] %s: %s", e.JavaClass, e.Message)
}

// DatabaseError represents a chaos-injected database error with an SQL state.
type DatabaseError struct {
	Message  string
	SQLState string
}

func (e *DatabaseError) Error() string {
	return fmt.Sprintf("SQL error (state %s): %s", e.SQLState, e.Message)
}
