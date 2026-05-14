'use strict';

// Only activate when Phoenix is explicitly enabled
if (process.env.PHOENIX_ENABLED !== 'true') {
  return;
}

try {
  const { NodeSDK } = require('@opentelemetry/sdk-node');
  const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-grpc');
  const { LangChainInstrumentation } = require('@arizeai/openinference-instrumentation-langchain');

  const exporter = new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317',
  });

  const sdk = new NodeSDK({
    traceExporter: exporter,
    instrumentations: [new LangChainInstrumentation()],
    serviceName: process.env.OTEL_SERVICE_NAME || 'flowise',
  });

  sdk.start();
  console.log('[Phoenix] OpenTelemetry instrumentation active →', process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://localhost:4317');

  process.on('SIGTERM', () => sdk.shutdown().finally(() => process.exit(0)));
} catch (err) {
  console.warn('[Phoenix] Instrumentation failed to load, continuing without tracing:', err.message);
}
