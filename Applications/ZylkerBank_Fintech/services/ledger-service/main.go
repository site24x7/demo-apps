package main

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"

	chaos "github.com/site24x7/observe-labs/sdks/go"
	"github.com/site24x7/observe-labs/sdks/go/fault"
	ginmw "github.com/site24x7/observe-labs/sdks/go/gin"

	"zylkerbank/ledger-service/config"
	"zylkerbank/ledger-service/db"
	"zylkerbank/ledger-service/handlers"
	"zylkerbank/ledger-service/middleware"
	"zylkerbank/ledger-service/service"
	"zylkerbank/ledger-service/tracing"
)

func main() {
	cfg := config.LoadConfig()

	// 1. Initialize OpenTelemetry Tracing
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	tracerShutdown, err := tracing.InitTracer(ctx, cfg)
	if err != nil {
		log.Printf("[otel] Warning: %v", err)
	} else {
		defer func() {
			shutdownCtx, sCancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer sCancel()
			_ = tracerShutdown(shutdownCtx)
		}()
	}

	// 2. Initialize Site24x7 Labs Chaos SDK
	var resourceInjector *fault.ResourceFaultInjector
	var chaosEngine *chaos.Engine

	if cfg.ChaosSDKEnabled {
		chaosInstance, err := chaos.InitChaos(
			cfg.ChaosSDKAppName,
			chaos.WithFramework("gin", "1.10.0"),
		)
		if err != nil {
			log.Printf("[chaos-sdk] Warning: %v", err)
		} else {
			chaosEngine = chaosInstance.Engine
			defer chaosInstance.Shutdown()

			resourceInjector = fault.NewResourceFaultInjector(chaosInstance.Engine)
			resourceInjector.Install()
			log.Println("[chaos-sdk] Site24x7 Chaos SDK initialized successfully")
		}
	}

	// 3. Connect to Oracle Database with retry logic
	var oracleDB *sql.DB
	oracleDB, err = db.ConnectOracle(cfg)
	if err != nil {
		log.Printf("[db] Warning: Failed to connect to Oracle: %v. Running in degraded state.", err)
	} else {
		defer oracleDB.Close()
		if resourceInjector != nil {
			resourceInjector.RegisterDB(oracleDB)
		}
	}

	// 4. Initialize Repository and Services
	var repo db.Repository
	if oracleDB != nil {
		repo = db.NewOracleRepository(oracleDB)
	} else {
		// Provide a fallback repository that fails gracefully for health ping
		log.Println("[db] Running with nil Oracle repository handle")
	}

	accountService := service.NewAccountService(repo, cfg)
	ledgerService := service.NewLedgerService(repo, accountService)

	// 5. Initialize HTTP Handlers
	authHandler := handlers.NewAuthHandler(accountService)
	accountsHandler := handlers.NewAccountsHandler(accountService)
	ledgerHandler := handlers.NewLedgerHandler(ledgerService)
	healthHandler := handlers.NewHealthHandler(repo)

	// 6. Setup Gin Engine
	if os.Getenv("GIN_MODE") == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(middleware.StructuredLogger())

	// Chaos SDK HTTP middleware
	if chaosEngine != nil {
		r.Use(ginmw.ChaosMiddleware(chaosEngine))
	}

	// OTel instrumentation middleware
	if !cfg.OTELSDKDisabled && cfg.OTELCollectorEndpoint != "" {
		r.Use(otelgin.Middleware(cfg.OTELServiceName))
	}

	// CORS configuration
	r.Use(cors.New(cors.Config{
		AllowOrigins:     []string{"*"},
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization", "X-Internal-Token", "X-Correlation-Id", "Idempotency-Key"},
		ExposeHeaders:    []string{"Content-Length", "X-Correlation-Id"},
		AllowCredentials: true,
	}))

	// Global auth middleware (populates context with claims/internal token info)
	r.Use(middleware.AuthMiddleware(cfg))

	// 7. Route Registration
	// Health endpoint (public)
	r.GET("/health", healthHandler.Health)

	// Auth routes (public)
	authGroup := r.Group("/api/v1/auth")
	{
		authGroup.POST("/register", authHandler.Register)
		authGroup.POST("/login", authHandler.Login)
		authGroup.GET("/me", middleware.RequireAuth(), authHandler.Me)
	}

	// Accounts routes (authenticated)
	accountsGroup := r.Group("/api/v1/accounts")
	accountsGroup.Use(middleware.RequireAuth())
	{
		accountsGroup.POST("", accountsHandler.CreateAccount)
		accountsGroup.GET("/search", accountsHandler.SearchAccounts)
		accountsGroup.GET("/:n", accountsHandler.GetAccount)
		accountsGroup.POST("/:n/verify-pin", accountsHandler.VerifyPIN)
		accountsGroup.POST("/:n/kyc", accountsHandler.UpdateKYC)
	}

	// Ledger routes (authenticated)
	ledgerGroup := r.Group("/api/v1/ledger")
	ledgerGroup.Use(middleware.RequireAuth())
	{
		ledgerGroup.POST("/transfer", ledgerHandler.Transfer)
		ledgerGroup.GET("/statements/:n", ledgerHandler.Statements)
	}

	// 8. Start HTTP Server with Graceful Shutdown
	srv := &http.Server{
		Addr:    fmt.Sprintf(":%s", cfg.Port),
		Handler: r,
	}

	go func() {
		log.Printf(" Account & Ledger Service running on port %s", cfg.Port)
		log.Printf("   Oracle DB: %s:%s/%s (User: %s)",
			cfg.OracleHost, cfg.OraclePort, cfg.OracleService, cfg.OracleUser)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shut down the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("Received signal %v, shutting down gracefully...", sig)

	shutdownCtx, sCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer sCancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println(" Ledger Service stopped cleanly")
}
