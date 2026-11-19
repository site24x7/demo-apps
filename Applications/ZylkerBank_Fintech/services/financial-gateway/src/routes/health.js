'use strict';
const express = require('express');
const db = require('../db/pool');
const kafkaProducer = require('../kafka/producer');
const { config } = require('../config');

const router = express.Router();

router.get('/', async (req, res) => {
  const [dbHealth, kafkaHealth] = await Promise.all([
    db.checkHealth(),
    kafkaProducer.checkHealth(),
  ]);

  const isDbUp = dbHealth.status === 'UP';
  const isKafkaUp = kafkaHealth.status === 'UP' || kafkaHealth.status === 'DISABLED';
  const overallStatus = isDbUp && isKafkaUp ? 'UP' : 'DEGRADED';

  const body = {
    status: overallStatus,
    service: config.serviceName,
    timestamp: new Date().toISOString(),
    checks: {
      postgres: dbHealth,
      kafka: kafkaHealth,
    },
  };

  // Health endpoint returns 200 even when optional/down dependencies are degraded per CONTRACTS.md
  return res.status(200).json(body);
});

module.exports = router;
