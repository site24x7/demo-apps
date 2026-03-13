const { getRedis } = require('../config/redis');

const CART_TTL = 86400; // 24 hours in seconds

class CartService {
  /**
   * Add item to cart (stored in Redis hash)
   */
  async addToCart(sessionId, item) {
    const redis = getRedis();
    const cartKey = `cart:${sessionId}`;
    const itemKey = `item:${item.productId}`;

    const existingItem = await redis.hget(cartKey, itemKey);
    if (existingItem) {
      const parsed = JSON.parse(existingItem);
      parsed.quantity += item.quantity || 1;
      await redis.hset(cartKey, itemKey, JSON.stringify(parsed));
    } else {
      const cartItem = {
        productId: item.productId,
        title: item.title,
        price: item.price,
        quantity: item.quantity || 1,
        size: item.size || null,
        image: item.image || null
      };
      await redis.hset(cartKey, itemKey, JSON.stringify(cartItem));
    }

    await redis.expire(cartKey, CART_TTL);
    return this.getCart(sessionId);
  }

  /**
   * Get all items in cart
   */
  async getCart(sessionId) {
    const redis = getRedis();
    const cartKey = `cart:${sessionId}`;
    const items = await redis.hgetall(cartKey);

    const cartItems = [];
    let totalAmount = 0;

    for (const [key, value] of Object.entries(items)) {
      const item = JSON.parse(value);
      const itemTotal = item.price * item.quantity;
      totalAmount += itemTotal;
      cartItems.push({ ...item, itemTotal });
    }

    return {
      sessionId,
      items: cartItems,
      itemCount: cartItems.length,
      totalAmount: Math.round(totalAmount * 100) / 100
    };
  }

  /**
   * Update item quantity
   */
  async updateQuantity(sessionId, productId, quantity) {
    const redis = getRedis();
    const cartKey = `cart:${sessionId}`;
    const itemKey = `item:${productId}`;

    const existing = await redis.hget(cartKey, itemKey);
    if (!existing) {
      throw new Error(`Product ${productId} not found in cart`);
    }

    if (quantity <= 0) {
      await redis.hdel(cartKey, itemKey);
    } else {
      const item = JSON.parse(existing);
      item.quantity = quantity;
      await redis.hset(cartKey, itemKey, JSON.stringify(item));
    }

    return this.getCart(sessionId);
  }

  /**
   * Remove item from cart
   */
  async removeFromCart(sessionId, productId) {
    const redis = getRedis();
    const cartKey = `cart:${sessionId}`;
    const itemKey = `item:${productId}`;
    await redis.hdel(cartKey, itemKey);
    return this.getCart(sessionId);
  }

  /**
   * Clear entire cart
   */
  async clearCart(sessionId) {
    const redis = getRedis();
    await redis.del(`cart:${sessionId}`);
    return { sessionId, items: [], itemCount: 0, totalAmount: 0 };
  }
}

module.exports = new CartService();
