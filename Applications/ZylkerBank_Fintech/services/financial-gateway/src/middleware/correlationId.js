'use strict';
const crypto = require('crypto');
const logger = require('../logger');

function correlationIdMiddleware(req, res, next) {
  const correlationId = req.headers['x-correlation-id'] || crypto.randomUUID();
  req.correlationId = correlationId;
  res.setHeader('X-Correlation-Id', correlationId);

  logger.runWithContext({ correlationId }, () => {
    next();
  });
}

module.exports = correlationIdMiddleware;
