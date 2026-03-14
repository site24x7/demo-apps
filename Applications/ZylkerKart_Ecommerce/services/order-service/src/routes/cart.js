const express = require('express');
const router = express.Router();
const cartService = require('../services/cartService');

// POST /cart/add - Add item to cart
router.post('/add', async (req, res) => {
  try {
    const { sessionId, productId, title, price, quantity, size, image } = req.body;
    if (!sessionId || !productId || !title || !price) {
      return res.status(400).json({ error: 'Missing required fields: sessionId, productId, title, price' });
    }
    const cart = await cartService.addToCart(sessionId, { productId, title, price, quantity, size, image });
    res.json(cart);
  } catch (err) {
    console.error('[Cart] Add error:', err);
    res.status(500).json({ error: err.message });
  }
});

// GET /cart/:sessionId - Get cart contents
router.get('/:sessionId', async (req, res) => {
  try {
    const cart = await cartService.getCart(req.params.sessionId);
    res.json(cart);
  } catch (err) {
    console.error('[Cart] Get error:', err);
    res.status(500).json({ error: err.message });
  }
});

// PUT /cart/:sessionId/item/:productId - Update item quantity
router.put('/:sessionId/item/:productId', async (req, res) => {
  try {
    const { quantity } = req.body;
    if (quantity === undefined) {
      return res.status(400).json({ error: 'Missing quantity' });
    }
    const cart = await cartService.updateQuantity(req.params.sessionId, req.params.productId, quantity);
    res.json(cart);
  } catch (err) {
    console.error('[Cart] Update error:', err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /cart/:sessionId/item/:productId - Remove item
router.delete('/:sessionId/item/:productId', async (req, res) => {
  try {
    const cart = await cartService.removeFromCart(req.params.sessionId, req.params.productId);
    res.json(cart);
  } catch (err) {
    console.error('[Cart] Remove error:', err);
    res.status(500).json({ error: err.message });
  }
});

// DELETE /cart/:sessionId - Clear cart
router.delete('/:sessionId', async (req, res) => {
  try {
    const cart = await cartService.clearCart(req.params.sessionId);
    res.json(cart);
  } catch (err) {
    console.error('[Cart] Clear error:', err);
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
