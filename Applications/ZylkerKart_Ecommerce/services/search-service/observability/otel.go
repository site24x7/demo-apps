// Package observability wires the OpenTelemetry SDK to a Site24x7 OTLP/HTTP
// endpoint. Activated when S247_OTEL_ENABLED=true; otherwise InitTracer is a
// no-op and returns a nil shutdown function.
package observability

import (
	"context"
	"log"
	"os"
	"strings"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

// InitTracer initialises the global tracer provider. Returns a shutdown
// function (nil if OTel is disabled) that flushes spans before exit.
func InitTracer(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	if !strings.EqualFold(os.Getenv("S247_OTEL_ENABLED"), "true") {
		return nil, nil
	}

	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return nil, err
	}

	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName(serviceName),
			semconv.ServiceVersion("1.0.0"),
			semconv.DeploymentEnvironmentName(envDefault("OTEL_DEPLOYMENT_ENVIRONMENT", "demo")),
		),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("[otel] Search Service tracing → %s", envDefault("OTEL_EXPORTER_OTLP_ENDPOINT", "default OTLP endpoint"))
	return tp.Shutdown, nil
}

func envDefault(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
