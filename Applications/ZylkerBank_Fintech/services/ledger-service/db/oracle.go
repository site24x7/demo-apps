package db

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"time"

	"github.com/XSAM/otelsql"
	_ "github.com/sijms/go-ora/v2"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"

	"zylkerbank/ledger-service/config"
)

// ConnectOracle creates a database connection pool with automatic retries for Oracle startup
func ConnectOracle(cfg *config.Config) (*sql.DB, error) {
	driverName := "oracle"

	if !cfg.OTELSDKDisabled && cfg.OTELCollectorEndpoint != "" {
		var err error
		driverName, err = otelsql.Register("oracle",
			otelsql.WithAttributes(
				semconv.DBSystemOracle,
				semconv.ServerAddress(cfg.OracleHost),
			),
		)
		if err != nil {
			log.Printf("[otelsql] Warning: failed to register otelsql: %v, falling back to pure oracle driver", err)
			driverName = "oracle"
		}
	}

	dsn := cfg.OracleDSN()
	log.Printf("[db] Connecting to Oracle at %s:%s/%s as %s",
		cfg.OracleHost, cfg.OraclePort, cfg.OracleService, cfg.OracleUser)

	db, err := sql.Open(driverName, dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database handle: %w", err)
	}

	// Configure pool
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(15 * time.Minute)

	// Retry loop for Oracle startup (Oracle container often takes 30-60s to open pluggable DB)
	maxRetries := 30
	retryInterval := 2 * time.Second

	var lastErr error
	for attempt := 1; attempt <= maxRetries; attempt++ {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		err = db.PingContext(ctx)
		cancel()

		if err == nil {
			log.Printf(" Connected to Oracle Database successfully on attempt %d", attempt)
			return db, nil
		}

		lastErr = err
		log.Printf("[db] Oracle not ready yet (attempt %d/%d): %v. Retrying in %v...",
			attempt, maxRetries, err, retryInterval)
		time.Sleep(retryInterval)
	}

	db.Close()
	return nil, fmt.Errorf("failed to connect to Oracle after %d attempts: %w", maxRetries, lastErr)
}
