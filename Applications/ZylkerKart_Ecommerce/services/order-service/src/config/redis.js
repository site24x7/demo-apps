const Redis = require('ioredis');

function createRedisClient() {
  const host = process.env.REDIS_HOST || 'localhost';
  const port = parseInt(process.env.REDIS_PORT || '6379');

  const client = new Redis({
    host,
    port,
    maxRetriesPerRequest: 3,
    retryStrategy(times) {
      if (times > 3) return null;
      return Math.min(times * 200, 2000);
    },
    connectTimeout: 5000,
    lazyConnect: false
  });

  client.on('error', (err) => {
    console.error('[Redis] Connection error:', err.message);
  });

  client.on('connect', () => {
    console.log('[Redis] Connected successfully');
  });

  return client;
}

let redisClient = createRedisClient();

function getRedis() {
  return redisClient;
}

module.exports = { getRedis };
