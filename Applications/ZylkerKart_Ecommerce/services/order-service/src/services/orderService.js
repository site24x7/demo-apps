const db = require('../config/db');
const cartService = require('./cartService');
const axios = require('axios');

const PAYMENT_URL = process.env.PAYMENT_SERVICE_URL || 'http://localhost:8084';
const AUTH_URL = process.env.AUTH_SERVICE_URL || 'http://localhost:8085';

class OrderService {
  /**
   * Create order from cart contents
   */
  async createOrder(sessionId, customerInfo, userId = null) {
    const connection = await db.getConnection();

    try {
      // 1. Get cart from Redis
      const cart = await cartService.getCart(sessionId);
      if (!cart.items || cart.items.length === 0) {
        throw new Error('Cart is empty');
      }

      await connection.beginTransaction();

      // 2. Create or find customer
      let customerId;
      const [existing] = await connection.execute(
        'SELECT id FROM customers WHERE session_id = ? OR (email = ? AND email IS NOT NULL) LIMIT 1',
        [sessionId, customerInfo.email || null]
      );

      if (existing.length > 0) {
        customerId = existing[0].id;
      } else {
        const [result] = await connection.execute(
          'INSERT INTO customers (user_id, session_id, name, email, phone) VALUES (?, ?, ?, ?, ?)',
          [userId, sessionId, customerInfo.name, customerInfo.email || null, customerInfo.phone || null]
        );
        customerId = result.insertId;
      }

      // 3. Create order
      const [orderResult] = await connection.execute(
        'INSERT INTO orders (customer_id, user_id, total_amount, status, shipping_address) VALUES (?, ?, ?, ?, ?)',
        [customerId, userId, cart.totalAmount, 'pending', customerInfo.address || null]
      );
      const orderId = orderResult.insertId;

      // 4. Insert order items
      for (const item of cart.items) {
        await connection.execute(
          'INSERT INTO order_items (order_id, product_id, product_title, quantity, unit_price, size, image_url) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [orderId, item.productId, item.title, item.quantity, item.price, item.size, item.image]
        );
      }

      // 5. Process payment
      let paymentResult = null;
      try {
        const paymentResponse = await axios.post(`${PAYMENT_URL}/payments/process`, {
          order_id: orderId,
          user_id: userId,
          amount: cart.totalAmount,
          currency: 'USD',
          method: customerInfo.paymentMethod || 'credit_card'
        }, { timeout: 10000 });
        paymentResult = paymentResponse.data;
      } catch (err) {
        console.error('[Order] Payment processing failed:', err.message);
      }

      // 6. Update order status based on payment
      const orderStatus = (paymentResult && paymentResult.status === 'success') ? 'confirmed' : 'pending';
      await connection.execute(
        'UPDATE orders SET status = ? WHERE id = ?',
        [orderStatus, orderId]
      );

      await connection.commit();

      // 7. Clear cart
      await cartService.clearCart(sessionId);

      // 8. Log activity to auth service
      if (userId) {
        try {
          await axios.post(`${AUTH_URL}/activity/log`, {
            userId,
            orderId,
            transactionId: paymentResult?.transactionId || null,
            activityType: 'order_placed',
            metadata: { totalAmount: cart.totalAmount, itemCount: cart.items.length }
          }, { timeout: 3000 });
        } catch (err) {
          console.error('[Order] Activity logging failed:', err.message);
        }
      }

      return {
        orderId,
        status: orderStatus,
        totalAmount: cart.totalAmount,
        items: cart.items,
        payment: paymentResult,
        message: orderStatus === 'confirmed' ? 'Order placed successfully!' : 'Order placed, payment pending.'
      };

    } catch (err) {
      await connection.rollback();
      throw err;
    } finally {
      connection.release();
    }
  }

  /**
   * Get order by ID
   */
  async getOrder(orderId) {
    const [orders] = await db.execute(
      `SELECT o.*, c.name as customer_name, c.email as customer_email 
       FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.id = ?`,
      [orderId]
    );

    if (orders.length === 0) return null;

    const [items] = await db.execute(
      'SELECT * FROM order_items WHERE order_id = ?',
      [orderId]
    );

    return { ...orders[0], items };
  }

  /**
   * Get orders by user ID
   */
  async getOrdersByUser(userId) {
    const [orders] = await db.execute(
      `SELECT o.*, c.name as customer_name, c.email as customer_email 
       FROM orders o JOIN customers c ON o.customer_id = c.id 
       WHERE o.user_id = ? ORDER BY o.created_at DESC`,
      [userId]
    );

    for (const order of orders) {
      const [items] = await db.execute(
        'SELECT * FROM order_items WHERE order_id = ?',
        [order.id]
      );
      order.items = items;
    }

    return orders;
  }

  /**
   * Get orders by session
   */
  async getOrdersBySession(sessionId) {
    const [customers] = await db.execute(
      'SELECT id FROM customers WHERE session_id = ?',
      [sessionId]
    );

    if (customers.length === 0) return [];

    const [orders] = await db.execute(
      'SELECT * FROM orders WHERE customer_id = ? ORDER BY created_at DESC',
      [customers[0].id]
    );

    return orders;
  }
}

module.exports = new OrderService();
