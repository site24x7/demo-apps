'use strict';
const { ZodError } = require('zod');
const { AppError } = require('../errors');
const logger = require('../logger');

function errorHandler(err, req, res, next) {
  if (res.headersSent) {
    return next(err);
  }

  // App-specific operational errors
  if (err instanceof AppError) {
    logger.warn('Operational error handled', {
      code: err.code,
      status: err.status,
      message: err.message,
      path: req.originalUrl,
      method: req.method,
    });
    return res.status(err.status).json(err.toBody());
  }

  // Zod validation errors
  if (err instanceof ZodError) {
    const firstIssue = err.errors[0];
    const message = firstIssue ? `${firstIssue.path.join('.')}: ${firstIssue.message}` : 'Validation error';
    logger.warn('Validation error handled', { message, errors: err.errors, path: req.originalUrl });
    return res.status(400).json({
      error: 'VALIDATION_ERROR',
      message,
      details: err.errors,
    });
  }

  // JSON syntax errors (from express.json())
  if (err instanceof SyntaxError && err.status === 400 && 'body' in err) {
    logger.warn('Malformed JSON payload received', { error: err.message, path: req.originalUrl });
    return res.status(400).json({
      error: 'INVALID_JSON',
      message: 'Malformed JSON payload',
    });
  }

  // Unhandled internal errors
  logger.error('Unhandled internal server error', {
    error: err.message,
    stack: err.stack,
    path: req.originalUrl,
    method: req.method,
  });

  return res.status(500).json({
    error: 'INTERNAL_SERVER_ERROR',
    message: 'An internal server error occurred',
  });
}

module.exports = errorHandler;
