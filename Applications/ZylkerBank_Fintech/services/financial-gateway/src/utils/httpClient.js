'use strict';
const axios = require('axios');
const logger = require('../logger');

/**
 * Perform outbound HTTP request with correlation ID and traceparent header propagation.
 */
async function callHttp({ method, url, data, headers = {}, timeout, correlationId, traceparent, tracestate }) {
  const reqHeaders = {
    'Content-Type': 'application/json',
    Accept: 'application/json',
    ...headers,
  };

  const corrId = correlationId || logger.getCorrelationId();
  if (corrId && !reqHeaders['X-Correlation-Id']) {
    reqHeaders['X-Correlation-Id'] = corrId;
  }

  if (traceparent && !reqHeaders['traceparent']) {
    reqHeaders['traceparent'] = traceparent;
  }
  if (tracestate && !reqHeaders['tracestate']) {
    reqHeaders['tracestate'] = tracestate;
  }

  logger.debug('Outbound HTTP request', { method, url, correlationId: corrId });

  return axios({
    method,
    url,
    data,
    headers: reqHeaders,
    timeout,
  });
}

module.exports = { callHttp };
