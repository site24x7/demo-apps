'use strict';
const express = require('express');
const transfersController = require('../controllers/transfersController');
const { validateBody } = require('../middleware/validate');
const {
  initiateTransferSchema,
  createPaymentRequestSchema,
  settlePaymentRequestSchema,
} = require('../validation/schemas');

const router = express.Router();

router.post('/initiate', validateBody(initiateTransferSchema), transfersController.initiateTransfer);
router.post('/requests', validateBody(createPaymentRequestSchema), transfersController.createPaymentRequest);
router.get('/requests', transfersController.listPaymentRequests);
router.post('/requests/:id/settle', validateBody(settlePaymentRequestSchema), transfersController.settlePaymentRequest);
router.post('/requests/:id/decline', transfersController.declinePaymentRequest);

module.exports = router;
