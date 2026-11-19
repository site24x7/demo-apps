'use strict';
const { test, describe, after } = require('node:test');
const assert = require('node:assert/strict');
const http = require('http');
const { app, appReady } = require('../src/app');
const db = require('../src/db/pool');
const kafkaProducer = require('../src/kafka/producer');

describe('Health Endpoint', () => {
  let server;
  let testPort;

  after(async () => {
    if (app.chaosEngine && typeof app.chaosEngine.stop === 'function') {
      try {
        app.chaosEngine.stop();
      } catch (_) {}
    }
    await db.close();
    await kafkaProducer.close();
  });

  test('GET /health returns 200 with status UP when all dependencies are healthy', async () => {
    await appReady;

    // Mock dependencies to be UP
    const origDbCheck = db.checkHealth;
    const origKafkaCheck = kafkaProducer.checkHealth;

    db.checkHealth = async () => ({ status: 'UP' });
    kafkaProducer.checkHealth = async () => ({ status: 'UP' });

    server = app.listen(0);
    testPort = server.address().port;

    const res = await new Promise((resolve, reject) => {
      http.get(`http://127.0.0.1:${testPort}/health`, (resp) => {
        let data = '';
        resp.on('data', (c) => (data += c));
        resp.on('end', () => resolve({ statusCode: resp.statusCode, body: JSON.parse(data) }));
      }).on('error', reject);
    });

    assert.equal(res.statusCode, 200);
    assert.equal(res.body.status, 'UP');
    assert.equal(res.body.service, 'financial-gateway');
    assert.equal(res.body.checks.postgres.status, 'UP');
    assert.equal(res.body.checks.kafka.status, 'UP');

    // Restore
    db.checkHealth = origDbCheck;
    kafkaProducer.checkHealth = origKafkaCheck;
    await new Promise((resolve) => server.close(resolve));
  });

  test('GET /health returns 200 with status DEGRADED when dependencies are down', async () => {
    await appReady;

    const origDbCheck = db.checkHealth;
    const origKafkaCheck = kafkaProducer.checkHealth;

    db.checkHealth = async () => ({ status: 'DOWN', error: 'ECONNREFUSED' });
    kafkaProducer.checkHealth = async () => ({ status: 'DOWN', error: 'ECONNREFUSED' });

    server = app.listen(0);
    testPort = server.address().port;

    const res = await new Promise((resolve, reject) => {
      http.get(`http://127.0.0.1:${testPort}/health`, (resp) => {
        let data = '';
        resp.on('data', (c) => (data += c));
        resp.on('end', () => resolve({ statusCode: resp.statusCode, body: JSON.parse(data) }));
      }).on('error', reject);
    });

    assert.equal(res.statusCode, 200, 'Health check must return 200 even when degraded');
    assert.equal(res.body.status, 'DEGRADED');
    assert.equal(res.body.checks.postgres.status, 'DOWN');
    assert.equal(res.body.checks.kafka.status, 'DOWN');

    db.checkHealth = origDbCheck;
    kafkaProducer.checkHealth = origKafkaCheck;
    await new Promise((resolve) => server.close(resolve));
  });
});
