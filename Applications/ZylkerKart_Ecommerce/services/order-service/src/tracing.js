'use strict';

// OpenTelemetry bootstrap for ZylkerKart Order Service.
// Loaded via `node --require ./src/tracing.js` when S247_OTEL_ENABLED=true.
// Exporter targets the Site24x7 OTLP/HTTP endpoint configured via standard
// OTEL_EXPORTER_OTLP_* env vars. The license key is injected as the `Api-Key`
// header by the entrypoint script.

const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { resourceFromAttributes } = require('@opentelemetry/resources');
const {
  ATTR_SERVICE_NAME,
  ATTR_SERVICE_VERSION,
} = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: process.env.OTEL_SERVICE_NAME || 'ZylkerKart-Order',
    [ATTR_SERVICE_VERSION]: process.env.OTEL_SERVICE_VERSION || '1.0.0',
    'deployment.environment': process.env.OTEL_DEPLOYMENT_ENVIRONMENT || 'demo',
  }),
  traceExporter: new OTLPTraceExporter(),
  metricReader: new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 30000,
  }),
  instrumentations: [getNodeAutoInstrumentations()],
});

sdk.start();
console.log('[otel] Order Service tracing initialised → ' + (process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'default OTLP endpoint'));

process.on('SIGTERM', () => {
  sdk.shutdown().finally(() => process.exit(0));
});
