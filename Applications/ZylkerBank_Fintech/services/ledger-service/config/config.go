package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	Port           string
	OracleHost     string
	OraclePort     string
	OracleService  string
	OracleUser     string
	OraclePassword string

	JWTSecret      string
	InternalToken  string
	KYCAutoApprove bool
	WelcomeDeposit float64

	OTELCollectorEndpoint string
	OTELSDKDisabled       bool
	OTELServiceName       string

	ChaosSDKEnabled   bool
	ChaosSDKAppName   string
	ChaosSDKConfigDir string
}

func LoadConfig() *Config {
	return &Config{
		Port:           GetEnv("PORT", "8081"),
		OracleHost:     GetEnv("ORACLE_HOST", "localhost"),
		OraclePort:     GetEnv("ORACLE_PORT", "1521"),
		OracleService:  GetEnv("ORACLE_SERVICE", "FREEPDB1"),
		OracleUser:     GetEnv("ORACLE_USER", "BANKLEDGER"),
		OraclePassword: GetEnv("ORACLE_PASSWORD", "ZylkerBank@2024"),

		JWTSecret:      GetEnv("JWT_SECRET", "zylkerbank-dev-jwt-secret-please-change-0123456789"),
		InternalToken:  GetEnv("INTERNAL_TOKEN", "zylkerbank-internal-dev-token"),
		KYCAutoApprove: GetEnvBool("KYC_AUTO_APPROVE", true),
		WelcomeDeposit: GetEnvFloat("WELCOME_DEPOSIT", 1000.00),

		OTELCollectorEndpoint: GetEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318"),
		OTELSDKDisabled:       GetEnvBool("OTEL_SDK_DISABLED", false),
		OTELServiceName:       GetEnv("OTEL_SERVICE_NAME", "ledger-service"),

		ChaosSDKEnabled:   GetEnvBool("CHAOS_SDK_ENABLED", true),
		ChaosSDKAppName:   GetEnv("CHAOS_SDK_APP_NAME", "ledger-service"),
		ChaosSDKConfigDir: GetEnv("CHAOS_SDK_CONFIG_DIR", "/var/site24x7-labs/faults"),
	}
}

func (c *Config) OracleDSN() string {
	// Standard go-ora URL format: oracle://user:password@host:port/service
	return fmt.Sprintf("oracle://%s:%s@%s:%s/%s",
		c.OracleUser,
		c.OraclePassword,
		c.OracleHost,
		c.OraclePort,
		c.OracleService,
	)
}

func GetEnv(key, defaultValue string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return defaultValue
}

func GetEnvBool(key string, defaultValue bool) bool {
	if val := os.Getenv(key); val != "" {
		parsed, err := strconv.ParseBool(val)
		if err == nil {
			return parsed
		}
	}
	return defaultValue
}

func GetEnvFloat(key string, defaultValue float64) float64 {
	if val := os.Getenv(key); val != "" {
		parsed, err := strconv.ParseFloat(val, 64)
		if err == nil {
			return parsed
		}
	}
	return defaultValue
}
