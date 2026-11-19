'use strict';
const express = require('express');
const cardsController = require('../controllers/cardsController');
const { validateBody } = require('../middleware/validate');
const {
  createCardSchema,
  cardFundWithdrawSchema,
  cardStatusSchema,
} = require('../validation/schemas');

const router = express.Router();

router.get('/', cardsController.listCards);
router.post('/', validateBody(createCardSchema), cardsController.createCard);
router.get('/:id', cardsController.getCard);
router.post('/:id/fund', validateBody(cardFundWithdrawSchema), cardsController.fundCard);
router.post('/:id/withdraw', validateBody(cardFundWithdrawSchema), cardsController.withdrawCard);
router.patch('/:id/status', validateBody(cardStatusSchema), cardsController.updateCardStatus);

module.exports = router;
