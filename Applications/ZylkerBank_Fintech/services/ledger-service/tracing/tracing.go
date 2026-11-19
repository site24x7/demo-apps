package tracing

import (
	"context"
	"log"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.24.0"

	"zylkerbank/ledger-service/config"
)

// InitTracer initializes OpenTelemetry tracing with OTLP HTTP exporter
func InitTracer(ctx context.Context, cfg *config.Config) (func(context.Context) error, error) {
	if cfg.OTELSDKDisabled || cfg.OTELCollectorEndpoint == "" {
		log.Println("[otel] OpenTelemetry SDK disabled or endpoint empty; tracing is no-op")
		return func(context.Context) error { return nil }, nil
	}

	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpointURL(cfg.OTELCollectorEndpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		log.Printf("[otel] Warning: failed to initialize OTLP exporter (%v); running without traces", err)
		return func(context.Context) error { return nil }, nil
	}

	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceNameKey.String(cfg.OTELServiceName),
		),
	)
	if err != nil {
		log.Printf("[otel] Warning: failed to create OTel resource: %v", err)
	}

	bsp := sdktrace.NewBatchSpanProcessor(exporter)
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
		sdktrace.WithResource(res),
		sdktrace.WithSpanProcessor(bsp),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	log.Printf("[otel] OpenTelemetry initialized with endpoint %s", cfg.OTELCollectorEndpoint)
	return tp.Shutdown, nil
}
