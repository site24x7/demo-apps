'use strict';
const jwt = require('jsonwebtoken');
const { config } = require('../config');
const { unauthorized } = require('../errors');
const logger = require('../logger');

function authenticate(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return next(unauthorized('UNAUTHORIZED', 'Authorization header is required'));
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
    return next(unauthorized('UNAUTHORIZED', 'Authorization header must be Bearer <token>'));
  }

  const token = parts[1];
  try {
    const decoded = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });

    req.user = {
      userId: decoded.sub,
      user_id: decoded.sub,
      email: decoded.email,
      name: decoded.name,
      accountNumber: decoded.account_number,
      account_number: decoded.account_number,
      tierLevel: decoded.tier_level,
      rawToken: token,
    };

    next();
  } catch (err) {
    logger.debug('JWT verification failed', { error: err.message });
    if (err.name === 'TokenExpiredError') {
      return next(unauthorized('TOKEN_EXPIRED', 'Authentication token has expired'));
    }
    return next(unauthorized('INVALID_TOKEN', 'Invalid authentication token'));
  }
}

module.exports = authenticate;
