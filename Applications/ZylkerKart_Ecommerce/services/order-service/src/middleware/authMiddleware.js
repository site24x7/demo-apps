const axios = require('axios');

const AUTH_SERVICE_URL = process.env.AUTH_SERVICE_URL || 'http://auth-service:8085';

/**
 * Auth middleware - validates JWT token via Auth Service
 * Adds req.user with decoded token data on success
 * Guest browsing allowed for GET requests (configurable)
 */
const authMiddleware = async (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      error: 'Authentication required',
      message: 'Missing or invalid Authorization header. Use: Bearer <token>'
    });
  }

  const token = authHeader.split(' ')[1];

  try {
    const response = await axios.get(`${AUTH_SERVICE_URL}/auth/validate`, {
      headers: { Authorization: `Bearer ${token}` },
      timeout: 5000
    });

    if (response.data && response.data.valid) {
      req.user = response.data.user || { token };
      next();
    } else {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'Token validation failed'
      });
    }
  } catch (err) {
    if (err.response && err.response.status === 401) {
      return res.status(401).json({
        error: 'Token expired or invalid',
        message: err.response.data?.message || 'Authentication failed'
      });
    }

    // Auth service unreachable — fail open for demo, log warning
    console.warn(`[AUTH] Auth service unreachable: ${err.message}. Allowing request.`);
    req.user = { id: null, fallback: true };
    next();
  }
};

/**
 * Optional auth - attaches user info if token present, but doesn't block
 * Used for guest-allowed endpoints like cart operations
 */
const optionalAuth = async (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    req.user = null;
    return next();
  }

  const token = authHeader.split(' ')[1];

  try {
    const response = await axios.get(`${AUTH_SERVICE_URL}/auth/validate`, {
      headers: { Authorization: `Bearer ${token}` },
      timeout: 3000
    });

    if (response.data && response.data.valid) {
      req.user = response.data.user || { token };
    } else {
      req.user = null;
    }
  } catch (err) {
    console.warn(`[AUTH] Optional auth failed: ${err.message}`);
    req.user = null;
  }

  next();
};

module.exports = { authMiddleware, optionalAuth };
