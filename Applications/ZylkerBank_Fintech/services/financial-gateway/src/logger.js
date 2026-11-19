'use strict';
const { AsyncLocalStorage } = require('async_hooks');
const { trace } = require('@opentelemetry/api');

const als = new AsyncLocalStorage();
const LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = LEVELS[(process.env.LOG_LEVEL || 'info').toLowerCase()] || LEVELS.info;
const SERVICE = 'financial-gateway';

function write(level, msg, fields) {
  if (LEVELS[level] < threshold) return;
  const store = als.getStore() || {};
  const entry = { ts: new Date().toISOString(), level, service: SERVICE, msg };
  if (store.correlationId) entry.correlation_id = store.correlationId;
  try {
    const span = trace.getActiveSpan && trace.getActiveSpan();
    const ctx = span && span.spanContext();
    if (ctx && ctx.traceId) {
      entry.trace_id = ctx.traceId;
      entry.span_id = ctx.spanId;
    }
  } catch (_) { /* ignore */ }
  if (fields) {
    for (const [k, v] of Object.entries(fields)) {
      entry[k] = v instanceof Error ? { name: v.name, message: v.message, stack: v.stack } : v;
    }
  }
  const line = JSON.stringify(entry);
  (level === 'error' || level === 'warn' ? process.stderr : process.stdout).write(line + '\n');
}

const logger = {
  debug: (m, f) => write('debug', m, f),
  info: (m, f) => write('info', m, f),
  warn: (m, f) => write('warn', m, f),
  error: (m, f) => write('error', m, f),
  runWithContext: (ctx, fn) => als.run(ctx, fn),
  getCorrelationId: () => (als.getStore() || {}).correlationId,
};

module.exports = logger;
