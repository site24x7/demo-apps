// Site24x7 Labs Chaos SDK for Go — Realistic Error Pools
//
// Pools of realistic Go errors, selected at random when a fault fires. The
// goal is that an injected failure is indistinguishable from a genuine
// production failure: the messages mirror what net, net/http, and the common
// database/Redis drivers actually emit.
//
// No string in this file contains "chaos", "site24x7", or "inject", or any
// other marker that would reveal the failure was synthetic.

package chaos

import (
	"errors"
	"math/rand"
)

// HTTP / outbound service-call failure messages.
// Mirror net.OpError / *url.Error style strings.
var httpErrorPool = []string{
	"dial tcp: connect: connection refused",
	"read tcp: connection reset by peer",
	"context deadline exceeded (Client.Timeout exceeded while awaiting headers)",
	"i/o timeout",
	"EOF",
}

// Per-engine database error message pools.
var dbErrorPools = map[string][]string{
	"postgresql": {
		"pq: server closed the connection unexpectedly",
		"dial tcp: connect: connection refused",
	},
	"postgres": {
		"pq: server closed the connection unexpectedly",
		"dial tcp: connect: connection refused",
	},
	"pgx": {
		"pq: server closed the connection unexpectedly",
		"dial tcp: connect: connection refused",
	},
	"mysql": {
		"invalid connection",
		"driver: bad connection",
	},
	"mariadb": {
		"invalid connection",
		"driver: bad connection",
	},
	"redis": {
		"redis: connection pool timeout",
		"dial tcp: connect: connection refused",
	},
}

// Generic SQL fallback pool when the engine is unknown.
var dbErrorGeneric = []string{
	"sql: database is closed",
	"driver: bad connection",
}

func pickMessage(pool []string) string {
	if len(pool) == 0 {
		return "unexpected error"
	}
	return pool[rand.Intn(len(pool))]
}

// RealisticHTTPError returns a random realistic HTTP/outbound error. Used as
// the DEFAULT error when an HTTP-client fault rule does not specify a message.
func RealisticHTTPError() error {
	return errors.New(pickMessage(httpErrorPool))
}

// RealisticDBError returns a random realistic database error appropriate for
// the given engine (postgresql, mysql, redis, ...). Falls back to a generic
// SQL error when the engine is unknown. Used as the DEFAULT error when a DB
// fault rule does not specify a message.
func RealisticDBError(engine string) error {
	if engine != "" {
		if pool, ok := dbErrorPools[engine]; ok {
			return errors.New(pickMessage(pool))
		}
	}
	return errors.New(pickMessage(dbErrorGeneric))
}
