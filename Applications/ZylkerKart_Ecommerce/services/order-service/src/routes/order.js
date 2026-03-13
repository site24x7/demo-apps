const express = require('express');
const router = express.Router();
const orderService = require('../services/orderService');
const { optionalAuth } = require('../middleware/authMiddleware');

// POST /orders - Create order from cart
router.post('/', optionalAuth, async (req, res) => {
  try {
    const { sessionId, customer, userId: bodyUserId } = req.body;
    if (!sessionId || !customer || !customer.name) {
      return res.status(400).json({ error: 'Missing required fields: sessionId, customer.name' });
    }
    // Use token-based userId first, fall back to userId from request body
    const userId = req.user?.id || bodyUserId || null;
    const order = await orderService.createOrder(sessionId, customer, userId);
    res.status(201).json(order);
  } catch (err) {
    console.error('[Order] Create error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /orders/user/:userId - Get orders by user (MUST be before /:id)
router.get('/user/:userId', async (req, res) => {
  try {
    const orders = await orderService.getOrdersByUser(parseInt(req.params.userId));
    res.json(orders);
  } catch (err) {
    console.error('[Order] Get by user error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /orders/session/:sessionId - Get orders by session (MUST be before /:id)
router.get('/session/:sessionId', async (req, res) => {
  try {
    const orders = await orderService.getOrdersBySession(req.params.sessionId);
    res.json(orders);
  } catch (err) {
    console.error('[Order] Get by session error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /orders/:id - Get order details
router.get('/:id', async (req, res) => {
  try {
    const order = await orderService.getOrder(parseInt(req.params.id));
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }
    res.json(order);
  } catch (err) {
    console.error('[Order] Get error:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
