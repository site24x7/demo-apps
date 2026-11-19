'use strict';

class AppError extends Error {
  /**
   * @param {number} status HTTP status
   * @param {string} code UPPER_SNAKE_CASE error code
   * @param {string} message human readable
   * @param {object} [extra] additional body fields (e.g. {risk}, {attempts_remaining})
   */
  constructor(status, code, message, extra) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.extra = extra || undefined;
  }
  toBody() {
    return { error: this.code, message: this.message, ...(this.extra || {}) };
  }
}

const badRequest = (code, msg, extra) => new AppError(400, code, msg, extra);
const unauthorized = (code, msg) => new AppError(401, code || 'UNAUTHORIZED', msg || 'Authentication required');
const forbidden = (code, msg, extra) => new AppError(403, code || 'FORBIDDEN', msg || 'Forbidden', extra);
const notFound = (code, msg) => new AppError(404, code || 'NOT_FOUND', msg || 'Resource not found');
const conflict = (code, msg) => new AppError(409, code, msg);
const unprocessable = (code, msg, extra) => new AppError(422, code, msg, extra);

module.exports = { AppError, badRequest, unauthorized, forbidden, notFound, conflict, unprocessable };
